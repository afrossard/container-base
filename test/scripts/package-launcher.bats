#!/usr/bin/env bats
#
# Tests for .github/scripts/package-launcher.sh, which packs the host-side
# scripts into the release asset the tap's formula installs, with the agent
# image pinned by digest (ADR-0028). Each test runs against a fixture tree
# shaped like the repo, so the real launcher's version never matters.

digest="sha256:$(printf 'a%.0s' {1..64})"

setup() {
  script="$BATS_TEST_DIRNAME/../../.github/scripts/package-launcher.sh"

  root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root/scripts/lib"
  cat > "$root/scripts/launch-agent-runtime" <<'EOF'
#!/usr/bin/env bash
version="1.2.3" # x-release-please-version
image="ghcr.io/afrossard/container-base:${version}-agent"
EOF
  printf '#!/usr/bin/env bash\n' > "$root/scripts/cleanup-agent-sessions"
  printf '# lib\n' > "$root/scripts/lib/agent-runtime.sh"
  chmod +x "$root/scripts/launch-agent-runtime" "$root/scripts/cleanup-agent-sessions"
  printf 'license\n' > "$root/LICENSE"

  out="$BATS_TEST_TMPDIR/agent-runtime-1.2.3.tar.gz"
  unpacked="$BATS_TEST_TMPDIR/unpacked"
  mkdir -p "$unpacked"
}

unpack() {
  tar -xzf "$out" -C "$unpacked"
}

@test "pins the launcher's image to the digest under a versioned top-level directory" {
  cd "$root"
  run "$script" 1.2.3 "$digest" "$out"

  [ "$status" -eq 0 ]
  unpack
  grep -qxF "image=\"ghcr.io/afrossard/container-base:\${version}-agent@${digest}\"" \
    "$unpacked/agent-runtime-1.2.3/scripts/launch-agent-runtime"
}

@test "packs every host-side script, executable, plus the license" {
  cd "$root"
  run "$script" 1.2.3 "$digest" "$out"

  [ "$status" -eq 0 ]
  unpack
  [ -x "$unpacked/agent-runtime-1.2.3/scripts/launch-agent-runtime" ]
  [ -x "$unpacked/agent-runtime-1.2.3/scripts/cleanup-agent-sessions" ]
  [ -f "$unpacked/agent-runtime-1.2.3/scripts/lib/agent-runtime.sh" ]
  [ -f "$unpacked/agent-runtime-1.2.3/LICENSE" ]
}

@test "leaves the committed launcher untouched" {
  cd "$root"
  before="$(cat scripts/launch-agent-runtime)"
  run "$script" 1.2.3 "$digest" "$out"

  [ "$status" -eq 0 ]
  [ "$(cat scripts/launch-agent-runtime)" == "$before" ]
}

@test "refuses a version the launcher does not carry, so a stale tree cannot ship" {
  cd "$root"
  run "$script" 1.2.4 "$digest" "$out"

  [ "$status" -ne 0 ]
  [[ "$output" == *"1.2.4"* ]]
  [ ! -e "$out" ]
}

@test "refuses anything but a full sha256 digest" {
  cd "$root"
  run "$script" 1.2.3 "sha256:abc" "$out"

  [ "$status" -ne 0 ]
  [ ! -e "$out" ]
}

@test "refuses a launcher whose image line it cannot pin" {
  cd "$root"
  sed -i.bak 's/^image=.*/image="somewhere-else"/' scripts/launch-agent-runtime
  run "$script" 1.2.3 "$digest" "$out"

  [ "$status" -ne 0 ]
  [[ "$output" == *"image="* ]]
  [ ! -e "$out" ]
}
