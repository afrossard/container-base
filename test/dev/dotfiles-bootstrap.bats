#!/usr/bin/env bats
#
# Runs against the real image built from images/dev/, not against the
# dotfiles-bootstrap script source. See issue #6's acceptance criteria:
# bootstrap from a fixture dotfiles repository, never a personal one -
# asserting against one developer's repo would bake their configuration
# into the definition of a working image.
#
# Expects IMAGE to name an already-built image (set by `npm run test:dev`,
# which passes the same tag `npm run build:dev` built).
#
# Cold, warm and drift tests share one $HOME, held in a Docker named volume
# across separate `docker run` invocations, so each test builds on the
# previous one's state - the same progression ADR-0009's measurement table
# walks through.

setup_file() {
  : "${IMAGE:?set IMAGE to the image tag built by \`npm run build:dev\`}"

  export FIXTURE_UPSTREAM="$BATS_FILE_TMPDIR/upstream"
  cp -r "$BATS_TEST_DIRNAME/fixtures/dotfiles" "$FIXTURE_UPSTREAM"
  git -C "$FIXTURE_UPSTREAM" init -q -b main
  git -C "$FIXTURE_UPSTREAM" -c user.email=test@example.com -c user.name=test \
    add -A
  git -C "$FIXTURE_UPSTREAM" -c user.email=test@example.com -c user.name=test \
    commit -q -m "fixture v1"

  # A real dotfiles clone never hits this: git only checks ownership on a
  # local filesystem source, not a network remote. The fixture stands in
  # for "upstream" as a bind-mounted local path, so on native Linux Docker
  # (not macOS Docker Desktop, which translates bind-mount ownership away)
  # its host-side owner doesn't match the container's vscode (uid 1000),
  # and git refuses it as a "dubious ownership" source. Trusting it via a
  # dedicated GIT_CONFIG_GLOBAL file - rather than chowning the fixture -
  # keeps the mount read-only and never touches host-owned files.
  export GIT_CONFIG_FIXTURE="$BATS_FILE_TMPDIR/gitconfig"
  printf '[safe]\n\tdirectory = *\n' > "$GIT_CONFIG_FIXTURE"

  export HOME_VOLUME="dotfiles-bootstrap-test-home-$$"
  docker volume create "$HOME_VOLUME" >/dev/null
}

teardown_file() {
  docker volume rm -f "$HOME_VOLUME" >/dev/null 2>&1 || true
}

run_bootstrap() {
  docker run --rm --user vscode \
    -e DOTFILES_REPO=/fixtures/upstream \
    -e GIT_CONFIG_GLOBAL=/fixtures/gitconfig \
    -v "$FIXTURE_UPSTREAM:/fixtures/upstream:ro" \
    -v "$GIT_CONFIG_FIXTURE:/fixtures/gitconfig:ro" \
    -v "$HOME_VOLUME:/home/vscode" \
    "$IMAGE" dotfiles-bootstrap
}

home_file() {
  docker run --rm -v "$HOME_VOLUME:/home/vscode" "$IMAGE" cat "/home/vscode/$1"
}

home_stat() {
  docker run --rm -v "$HOME_VOLUME:/home/vscode" "$IMAGE" stat -c '%a' "/home/vscode/$1"
}

@test "cold bootstrap: exits 0 with no TTY, fixture's ~/.zshrc lands" {
  run run_bootstrap
  [ "$status" -eq 0 ]

  run home_file .zshrc
  [ "$status" -eq 0 ]
  [[ "$output" == *"DOTFILES_BOOTSTRAP_FIXTURE=v1"* ]]
}

@test "warm bootstrap picks up a new upstream commit" {
  echo 'export DOTFILES_BOOTSTRAP_FIXTURE=v2' > "$FIXTURE_UPSTREAM/dot_zshrc"
  git -C "$FIXTURE_UPSTREAM" -c user.email=test@example.com -c user.name=test \
    commit -aqm "fixture v2"

  run run_bootstrap
  [ "$status" -eq 0 ]

  run home_file .zshrc
  [ "$status" -eq 0 ]
  [[ "$output" == *"DOTFILES_BOOTSTRAP_FIXTURE=v2"* ]]
}

@test "a drifted \$HOME recovers" {
  docker run --rm -v "$HOME_VOLUME:/home/vscode" "$IMAGE" \
    sh -c 'echo "drifted" > /home/vscode/.zshrc'

  run run_bootstrap
  [ "$status" -eq 0 ]

  run home_file .zshrc
  [ "$status" -eq 0 ]
  [[ "$output" == *"DOTFILES_BOOTSTRAP_FIXTURE=v2"* ]]
}

@test "the ssh directory is 0700 and its config file is 0600 after apply" {
  run home_stat .ssh
  [ "$status" -eq 0 ]
  [ "$output" = "700" ]

  run home_stat .ssh/config
  [ "$status" -eq 0 ]
  [ "$output" = "600" ]
}

@test "with no repository configured, bootstrap is a no-op that exits 0" {
  run docker run --rm --user vscode "$IMAGE" dotfiles-bootstrap
  [ "$status" -eq 0 ]
}

@test "chezmoi is installed to /usr/local/bin" {
  run docker run --rm "$IMAGE" sh -c 'command -v chezmoi'
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/local/bin/chezmoi" ]
}

@test "dotfiles-bootstrap is installed to /usr/local/bin" {
  run docker run --rm "$IMAGE" sh -c 'command -v dotfiles-bootstrap'
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/local/bin/dotfiles-bootstrap" ]
}

@test "the image declares no ENTRYPOINT" {
  run docker inspect --format '{{.Config.Entrypoint}}' "$IMAGE"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}
