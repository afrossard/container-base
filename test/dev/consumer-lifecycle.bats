#!/usr/bin/env bats
#
# Opens a minimal consumer devcontainer on the real image built from
# images/dev/ with `devcontainer up`, the door a consumer walks through, and
# asserts the lifecycle the image ships in its devcontainer.metadata label
# reaches it (ADR-0029). The consumer config names nothing but the image,
# a mount for the fixture dotfiles repo, and a postCreateCommand of its own.
#
# Expects IMAGE to name an already-built image (set by `npm run test:dev`).
#
# Unreliable when run inside this repo's own devcontainer - see
# docs/agents/gotchas.md.

bats_require_minimum_version 1.5.0

setup_file() {
  : "${IMAGE:?set IMAGE to the image tag built by \`npm run build:dev\`}"

  export FIXTURE_UPSTREAM="$BATS_FILE_TMPDIR/upstream"
  cp -r "$BATS_TEST_DIRNAME/fixtures/dotfiles" "$FIXTURE_UPSTREAM"
  git -C "$FIXTURE_UPSTREAM" init -q -b main
  git -C "$FIXTURE_UPSTREAM" -c user.email=test@example.com -c user.name=test \
    add -A
  git -C "$FIXTURE_UPSTREAM" -c user.email=test@example.com -c user.name=test \
    commit -q -m "fixture v1"

  export WORKSPACE="$BATS_FILE_TMPDIR/consumer"
  mkdir -p "$WORKSPACE/.devcontainer"
  # The bind-mounted fixture's host-side owner isn't the container's vscode,
  # so git refuses to clone it as "dubious ownership". The consumer's
  # postCreateCommand trusts it, and runs before the image's
  # postStartCommand bootstraps from it.
  cat >"$WORKSPACE/.devcontainer/devcontainer.json" <<EOF
{
  "image": "$IMAGE",
  "mounts": ["source=$FIXTURE_UPSTREAM,target=/fixtures/upstream,type=bind,readonly"],
  "postCreateCommand": "git config --global --add safe.directory '*' && touch /tmp/consumer-post-create"
}
EOF

  # Resolved on the host when the container opens, as a consumer's
  # ${localEnv:DOTFILES_REPO} is.
  DOTFILES_REPO=/fixtures/upstream \
    devcontainer up --workspace-folder "$WORKSPACE" >"$BATS_FILE_TMPDIR/up.log" 2>&1 ||
    { cat "$BATS_FILE_TMPDIR/up.log" >&3; return 1; }
}

teardown_file() {
  docker ps -aq --filter "label=devcontainer.local_folder=$WORKSPACE" |
    xargs -r docker rm -f >/dev/null 2>&1 || true
}

in_consumer() {
  devcontainer exec --workspace-folder "$WORKSPACE" "$@"
}

@test "the image's postStartCommand bootstraps dotfiles from the consumer host's DOTFILES_REPO" {
  run in_consumer sh -c 'cat "$HOME/.zshrc"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"DOTFILES_BOOTSTRAP_FIXTURE=v1"* ]]
}

@test "the image's postStartCommand trusts the consumer's workspace folder" {
  run in_consumer sh -c 'git config --global --get-all safe.directory | grep -Fx "$PWD"'
  [ "$status" -eq 0 ]
}

@test "the consumer's own postCreateCommand still runs" {
  run in_consumer test -e /tmp/consumer-post-create
  [ "$status" -eq 0 ]
}

@test "the consumer inherits waitFor and the shared extensions" {
  run --separate-stderr devcontainer read-configuration \
    --workspace-folder "$WORKSPACE" --include-merged-configuration
  [ "$status" -eq 0 ]
  merged=$(jq -c '.mergedConfiguration' <<<"$output")

  [ "$(jq -r '.waitFor' <<<"$merged")" = "postStartCommand" ]

  run jq -r '[.customizations.vscode | .. | objects | .extensions? // empty | .[]] | unique | .[]' <<<"$merged"
  [ "$status" -eq 0 ]
  [ "$output" = "EditorConfig.EditorConfig
donjayamanne.githistory
eamodio.gitlens
esbenp.prettier-vscode
mhutchie.git-graph
ms-azuretools.vscode-containers" ]
}
