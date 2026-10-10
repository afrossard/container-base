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

# Writes stdin to ~/.docker/config.json as vscode, runs the script with the
# given shell prelude, and prints the script's output, a separator, then the
# resulting config (or ABSENT).
prune() {
  docker run --rm -i --user vscode "$IMAGE" sh -c '
    mkdir -p "$HOME/.docker"
    cat > "$HOME/.docker/config.json"
    '"${1:-}"'
    docker-prune-credsstore || exit
    echo ---
    cat "${DOCKER_CONFIG:-$HOME/.docker}/config.json" 2>/dev/null || echo ABSENT
  '
}

@test "a credsStore whose helper is not on PATH is removed, other keys kept" {
  run prune <<'EOF'
{
  "auths": { "ghcr.io": {} },
  "credHelpers": { "gcr.io": "gcloud" },
  "credsStore": "desktop",
  "currentContext": "default"
}
EOF
  [ "$status" -eq 0 ]
  config="${output#*---$'\n'}"
  run jq -e '
    (has("credsStore") | not)
    and .auths == { "ghcr.io": {} }
    and .credHelpers == { "gcr.io": "gcloud" }
    and .currentContext == "default"
  ' <<<"$config"
  [ "$status" -eq 0 ]
}

@test "removing a credsStore keeps the config's file mode" {
  run docker run --rm -i --user vscode "$IMAGE" sh -c '
    mkdir -p "$HOME/.docker"
    cat > "$HOME/.docker/config.json"
    chmod 0640 "$HOME/.docker/config.json"
    docker-prune-credsstore >/dev/null
    stat -c "%a" "$HOME/.docker/config.json"
  ' <<<'{ "credsStore": "desktop" }'
  [ "$status" -eq 0 ]
  [ "$output" = "640" ]
}

@test "removing a credsStore says which helper was missing" {
  run prune <<<'{ "credsStore": "desktop" }'
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker-credential-desktop"* ]]
}

@test "a credsStore whose helper is on PATH is kept, file untouched" {
  input='{"credsStore":"pass"}'
  run prune '
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
  run prune <<<"$input"
  [ "$status" -eq 0 ]
  [ "$output" = "---
$input" ]
}

@test "DOCKER_CONFIG is honoured over ~/.docker" {
  run prune '
    export DOCKER_CONFIG="$HOME/elsewhere"
    mkdir -p "$DOCKER_CONFIG"
    mv "$HOME/.docker/config.json" "$DOCKER_CONFIG/config.json"
  ' <<<'{ "credsStore": "desktop" }'
  [ "$status" -eq 0 ]
  config="${output#*---$'\n'}"
  run jq -e 'has("credsStore") | not' <<<"$config"
  [ "$status" -eq 0 ]
}

@test "with no docker config, it is a no-op that exits 0 and creates nothing" {
  run prune 'rm -r "$HOME/.docker"' </dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "---
ABSENT" ]
}

@test "an unparseable config fails loudly and is left untouched" {
  run prune <<<'{ not json'
  [ "$status" -ne 0 ]

  run docker run --rm -i --user vscode "$IMAGE" sh -c '
    mkdir -p "$HOME/.docker"
    cat > "$HOME/.docker/config.json"
    docker-prune-credsstore 2>/dev/null
    cat "$HOME/.docker/config.json"
  ' <<<'{ not json'
  [ "$output" = "{ not json" ]
}

@test "docker-prune-credsstore is installed to /usr/local/bin" {
  run docker run --rm "$IMAGE" sh -c 'command -v docker-prune-credsstore'
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/local/bin/docker-prune-credsstore" ]
}
