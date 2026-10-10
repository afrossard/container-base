#!/usr/bin/env bats
#
# Runs against the real image built from images/dev/ (issue #205): a macOS
# host's `"credsStore": "desktop"` reaches the container's docker config,
# where no docker-credential-desktop exists, and every `docker pull` fails.
#
# Expects IMAGE to name an already-built image (set by `npm run test:dev`).
#
# Each test pipes its config in on stdin rather than bind-mounting it, so
# it holds under docker-outside-of-docker too (docs/agents/gotchas.md).

setup_file() {
  : "${IMAGE:?set IMAGE to the image tag built by \`npm run build:dev\`}"
}

# Seeds ~/.docker/config.json from stdin as vscode, runs the `setup` shell
# snippet, then docker-prune-credsstore, then the `report` snippet. The
# default report prints a `---` separator and the resulting config (or
# ABSENT), which `config_after_separator` extracts.
prune_stdin_config() {
  local setup="${1:-}"
  local report='echo ---; cat "${DOCKER_CONFIG:-$HOME/.docker}/config.json" 2>/dev/null || echo ABSENT'
  [ $# -lt 2 ] || report="$2"
  docker run --rm -i --user vscode "$IMAGE" sh -c '
    mkdir -p "$HOME/.docker"
    cat > "$HOME/.docker/config.json"
    '"$setup"'
    docker-prune-credsstore || exit
    '"$report"'
  '
}

config_after_separator() {
  printf '%s\n' "${output#*---$'\n'}"
}

@test "a credsStore whose helper is not on PATH is removed, other keys kept" {
  run prune_stdin_config <<'EOF'
{
  "auths": { "ghcr.io": {} },
  "credHelpers": { "gcr.io": "gcloud" },
  "credsStore": "desktop",
  "currentContext": "default"
}
EOF
  [ "$status" -eq 0 ]
  run jq -e '
    (has("credsStore") | not)
    and .auths == { "ghcr.io": {} }
    and .credHelpers == { "gcr.io": "gcloud" }
    and .currentContext == "default"
  ' < <(config_after_separator)
  [ "$status" -eq 0 ]
}

@test "removing a credsStore keeps the config's file mode" {
  run prune_stdin_config \
    'chmod 0640 "$HOME/.docker/config.json"' \
    'stat -c "%a" "$HOME/.docker/config.json"' \
    <<<'{ "credsStore": "desktop" }'
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "640" ]
}

@test "a symlinked config is edited at its target and stays a symlink" {
  run prune_stdin_config '
    mv "$HOME/.docker/config.json" "$HOME/real-config.json"
    chmod 0600 "$HOME/real-config.json"
    ln -s "$HOME/real-config.json" "$HOME/.docker/config.json"
  ' '
    [ -L "$HOME/.docker/config.json" ] && echo symlink
    stat -c "%a" "$HOME/real-config.json"
    jq -e "has(\"credsStore\") | not" "$HOME/real-config.json"
  ' <<<'{ "credsStore": "desktop" }'
  [ "$status" -eq 0 ]
  [ "${lines[-3]}" = "symlink" ]
  [ "${lines[-2]}" = "600" ]
}

@test "removing a credsStore says which helper was missing" {
  run prune_stdin_config <<<'{ "credsStore": "desktop" }'
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker-credential-desktop"* ]]
}

@test "a credsStore whose helper is on PATH is kept, file untouched" {
  input='{"credsStore":"pass"}'
  run prune_stdin_config '
    mkdir -p "$HOME/bin"
    printf "#!/bin/sh\n" > "$HOME/bin/docker-credential-pass"
    chmod +x "$HOME/bin/docker-credential-pass"
    PATH="$HOME/bin:$PATH"
  ' <<<"$input"
  [ "$status" -eq 0 ]
  [ "$output" = "---
$input" ]
}

@test "a config with no credsStore is left byte-for-byte untouched" {
  input='{"auths":{}}'
  run prune_stdin_config <<<"$input"
  [ "$status" -eq 0 ]
  [ "$output" = "---
$input" ]
}

@test "DOCKER_CONFIG is honoured over ~/.docker" {
  run prune_stdin_config '
    export DOCKER_CONFIG="$HOME/elsewhere"
    mkdir -p "$DOCKER_CONFIG"
    mv "$HOME/.docker/config.json" "$DOCKER_CONFIG/config.json"
  ' <<<'{ "credsStore": "desktop" }'
  [ "$status" -eq 0 ]
  run jq -e 'has("credsStore") | not' < <(config_after_separator)
  [ "$status" -eq 0 ]
}

@test "with no docker config, it is a no-op that exits 0 and creates nothing" {
  run prune_stdin_config 'rm -r "$HOME/.docker"' </dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "---
ABSENT" ]
}

@test "an unparseable config fails loudly and is left untouched" {
  run prune_stdin_config '' \
    'echo unreachable' \
    <<<'{ not json'
  [ "$status" -ne 0 ]
  [[ "$output" != *unreachable* ]]

  run prune_stdin_config \
    'trap "cat \"\$HOME/.docker/config.json\"" EXIT' \
    '' \
    <<<'{ not json'
  [ "${lines[-1]}" = "{ not json" ]
}

@test "docker-prune-credsstore is installed to /usr/local/bin" {
  run docker run --rm "$IMAGE" sh -c 'command -v docker-prune-credsstore'
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/local/bin/docker-prune-credsstore" ]
}
