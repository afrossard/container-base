#!/usr/bin/env bats
#
# Runs against the real image built from images/dev/, not against the
# Containerfile or devcontainer.json source. See issue #1's "Test assertions"
# section: assert through the door a user walks through.
#
# Expects IMAGE to name an already-built image (set by `npm run test:dev`,
# which passes the same tag `npm run build:dev` built).

setup_file() {
  : "${IMAGE:?set IMAGE to the image tag built by \`npm run build:dev\`}"
}

@test "vscode is uid 1000, gid 1000, login shell /bin/zsh" {
  run docker run --rm "$IMAGE" getent passwd vscode
  [ "$status" -eq 0 ]
  IFS=: read -r _ _ uid gid _ _ shell <<<"$output"
  [ "$uid" = "1000" ]
  [ "$gid" = "1000" ]
  [ "$shell" = "/bin/zsh" ]
}

@test "vscode has passwordless sudo" {
  run docker run --rm --user vscode "$IMAGE" sudo -n whoami
  [ "$status" -eq 0 ]
  [ "$output" = "root" ]
}

@test "LANG is set" {
  run docker run --rm "$IMAGE" sh -c 'printenv LANG'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "\$HOME has no chezmoi-managed file after build" {
  run docker run --rm "$IMAGE" sh -c '[ ! -e /home/vscode/.zshrc ] && [ ! -e /home/vscode/.oh-my-zsh ]'
  [ "$status" -eq 0 ]
}
