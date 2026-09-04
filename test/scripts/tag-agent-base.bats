#!/usr/bin/env bats
#
# Tests for .github/scripts/tag-agent-base.sh, which parses the agent
# Containerfile's `ARG BASE_VERSION=` line and retags a source image as the
# pinned base agent-image.yml builds FROM (ADR-0018). A stub `docker` on
# PATH records the arguments it would have received.

setup() {
  stub_dir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$stub_dir"
  export DOCKER_ARGS_FILE="$BATS_TEST_TMPDIR/docker-args"

  cat > "$stub_dir/docker" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$DOCKER_ARGS_FILE"
STUB
  chmod +x "$stub_dir/docker"
  export PATH="$stub_dir:$PATH"

  script="$BATS_TEST_DIRNAME/../../.github/scripts/tag-agent-base.sh"
}

@test "tags the source image against the version parsed from the ARG line" {
  containerfile="$BATS_TEST_TMPDIR/Containerfile"
  cat > "$containerfile" <<'EOF'
# x-release-please-start-version
ARG BASE_VERSION=0.0.9
# x-release-please-end
FROM ghcr.io/afrossard/container-base:${BASE_VERSION}-dev
EOF

  run "$script" "container-base:dev-test" "$containerfile"

  [ "$status" -eq 0 ]
  [ "$(cat "$DOCKER_ARGS_FILE")" == "$(printf 'tag\ncontainer-base:dev-test\nghcr.io/afrossard/container-base:0.0.9-dev\n')" ]
}

@test "fails loudly rather than tagging a malformed version when the ARG line is missing" {
  containerfile="$BATS_TEST_TMPDIR/Containerfile"
  cat > "$containerfile" <<'EOF'
FROM ghcr.io/afrossard/container-base:0.0.9-dev
EOF

  run "$script" "container-base:dev-test" "$containerfile"

  [ "$status" -ne 0 ]
  [[ "$output" == *"no 'ARG BASE_VERSION=' line found"* ]]
  [ ! -e "$DOCKER_ARGS_FILE" ]
}
