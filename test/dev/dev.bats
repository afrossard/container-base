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

@test "uv is installed to a system path, not \$HOME" {
  run docker run --rm "$IMAGE" sh -c 'command -v uv && command -v uvx'
  [ "$status" -eq 0 ]
}

@test "mise is installed via apt, at /usr/bin/mise" {
  run docker run --rm "$IMAGE" sh -c 'dpkg -s mise >/dev/null && command -v mise'
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/bin/mise" ]
}

@test "mise's data directory is vscode-owned" {
  run docker run --rm "$IMAGE" stat -c '%U:%G' /usr/local/share/mise
  [ "$status" -eq 0 ]
  [ "$output" = "vscode:vscode" ]
}

@test "the mise shims directory is prepended to sudo's secure_path" {
  run docker run --rm "$IMAGE" grep secure_path /etc/sudoers
  [ "$status" -eq 0 ]
  [[ "$output" == *'secure_path="/usr/local/share/mise/shims:'* ]]
}

@test "MISE_GLOBAL_CONFIG_FILE is not set" {
  run docker run --rm "$IMAGE" sh -c 'printenv MISE_GLOBAL_CONFIG_FILE'
  [ "$status" -ne 0 ]
}

# One test, not three: all three assertions share a single `mise install`,
# which downloads a real Node build. Splitting them would triple that
# download for no gain (ADR-0008 measures the same three outcomes together).
@test "mise resolves a real binary through shims, under sudo, and reports unset outside any project" {
  run docker run --rm --user vscode "$IMAGE" zsh -lc '
    set -e
    mkdir -p /tmp/proj && cd /tmp/proj
    printf "[tools]\nnode = \"22\"\n" > .mise.toml
    mise trust >/dev/null
    mise install >/dev/null 2>&1
    echo "IN_PROJECT=$(node --version)"
    echo "UNDER_SUDO=$(sudo node --version)"
    cd /tmp
    if node --version 2>&1 | grep -q "No version is set for shim: node"; then
      echo "OUTSIDE_PROJECT=no-version-set"
    else
      echo "OUTSIDE_PROJECT=unexpected"
    fi
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"IN_PROJECT=v22"* ]]
  [[ "$output" == *"UNDER_SUDO=v22"* ]]
  [[ "$output" == *"OUTSIDE_PROJECT=no-version-set"* ]]
}

@test "uv can resolve and fetch a Python interpreter" {
  run docker run --rm --user vscode "$IMAGE" zsh -lc 'uv python install 3.13'
  [ "$status" -eq 0 ]
}
