#!/usr/bin/env bats
#
# Tests for scripts/cleanup-agent-sessions, which had none before issue #83
# moved its sandbox lookup into the shared lib. A fault in that helper is now
# a fault in both host-side scripts, so the script that removes things is the
# one worth covering: its whole job is to refuse in the cases where removing
# would be wrong.
#
# A stub msb answers from STUB_ALL and STUB_RUNNING and records what it was
# asked to remove, so nothing here needs a hypervisor or a real sandbox.

setup() {
  stub_dir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$stub_dir"
  export MSB_RM_FILE="$BATS_TEST_TMPDIR/msb-rm"

  # See the launcher suite for why a recording stub, not exit 127 alone:
  # the callers test these helpers with `||`, which suppresses set -e.
  export JQ_CALLED_FILE="$BATS_TEST_TMPDIR/jq-called"
  cat > "$stub_dir/jq" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$JQ_CALLED_FILE"
exit 127
STUB
  chmod +x "$stub_dir/jq"

  export STUB_ALL=""
  export STUB_RUNNING=""

  cat > "$stub_dir/msb" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  list)
    want=all
    for a in "$@"; do
      case "$a" in
        --running) want=running ;;
        --stopped) want=stopped ;;
      esac
    done
    for n in $STUB_ALL; do
      case " $STUB_RUNNING " in
        *" $n "*) [ "$want" = stopped ] || printf '%s\n' "$n" ;;
        *) [ "$want" = running ] || printf '%s\n' "$n" ;;
      esac
    done
    ;;
  rm) printf '%s\n' "$3" >> "$MSB_RM_FILE" ;;
  volume) exit 0 ;;
  *)
    echo "msb stub: unexpected subcommand: $1" >&2
    exit 64
    ;;
esac
exit 0
STUB
  chmod +x "$stub_dir/msb"
  export PATH="$stub_dir:$PATH"
}

cleanup() {
  "$BATS_TEST_DIRNAME/../../scripts/cleanup-agent-sessions" "$@"
}

@test "a running sandbox is not removed without --force" {
  export STUB_ALL="alpha" STUB_RUNNING="alpha"
  run cleanup --name alpha
  [ "$status" -ne 0 ]
  [[ "$output" == *"currently running"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "--force removes a running sandbox" {
  export STUB_ALL="alpha" STUB_RUNNING="alpha"
  run cleanup --name alpha --force
  [ "$status" -eq 0 ]
  grep -Fxq alpha "$MSB_RM_FILE"
}

# Distinct from "exists but is stopped": an unknown name is the operator's
# typo, and silently doing nothing would read as success.
@test "a name that does not exist is reported, not ignored" {
  export STUB_ALL="alpha" STUB_RUNNING=""
  run cleanup --name beta --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"no sandbox named"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "a stopped sandbox is removed without --force needing to be given" {
  export STUB_ALL="alpha" STUB_RUNNING=""
  run cleanup --name alpha --force
  [ "$status" -eq 0 ]
  grep -Fxq alpha "$MSB_RM_FILE"
}

@test "--dry-run removes nothing" {
  export STUB_ALL="alpha" STUB_RUNNING=""
  run cleanup --name alpha --dry-run
  [ "$status" -eq 0 ]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "cleanup never calls jq" {
  export STUB_ALL="alpha" STUB_RUNNING="alpha"
  run cleanup --name alpha --force
  [ "$status" -eq 0 ]
  [ ! -f "$JQ_CALLED_FILE" ]
}
