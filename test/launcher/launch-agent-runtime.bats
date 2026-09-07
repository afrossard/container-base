#!/usr/bin/env bats
#
# Argument-assembly tests for scripts/launch-agent-runtime: a stub `msb`
# earlier on PATH records the assembled command line and exits.
#
# The stub records one argument per line, never "$*", so a value that
# word-split into two arguments fails here rather than reading identically
# in a flattened string. A stub cannot check whether msb honours what it
# was handed; that is live-checked separately.

setup() {
  stub_dir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$stub_dir"
  export MSB_ARGS_FILE="$BATS_TEST_TMPDIR/msb-args"
  export MSB_START_FILE="$BATS_TEST_TMPDIR/msb-start"
  export MSB_EXEC_FILE="$BATS_TEST_TMPDIR/msb-exec"

  # Runtime state the stub answers `list` from: names in STUB_ALL exist,
  # names also in STUB_RUNNING are running. Empty by default, so the common
  # case is "no runtime yet" and the launcher takes its create path.
  export STUB_ALL=""
  export STUB_RUNNING=""

  # The launcher must not call jq (issue #83). Exit 127 alone isn't enough:
  # sandbox_is_running runs as `... || return 0`, which suppresses set -e,
  # so the stub records the call and the test asserts on the recording.
  export JQ_CALLED_FILE="$BATS_TEST_TMPDIR/jq-called"
  cat > "$stub_dir/jq" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$JQ_CALLED_FILE"
exit 127
STUB
  chmod +x "$stub_dir/jq"

  # A state-driven stub: `list` answers from STUB_ALL/STUB_RUNNING, and
  # each lifecycle subcommand records what it was handed so a test can
  # assert which one the launcher chose (create / resume / attach).
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
  volume)
    # Succeeding means ensure_volume never calls create.
    exit 0
    ;;
  start)
    printf '%s\n' "$@" >> "$MSB_START_FILE"
    exit 0
    ;;
  exec)
    # Both the agent-bringup call and the shell/command call land here,
    # appended so a test can assert on either.
    printf '%s\n' "$@" >> "$MSB_EXEC_FILE"
    exit 0
    ;;
  run)
    printf '%s\n' "$@" > "$MSB_ARGS_FILE"
    exit 0
    ;;
  *)
    # Loud, so an unrecognized subcommand can't become a silent pass.
    echo "msb stub: unexpected subcommand: $1" >&2
    exit 64
    ;;
esac
STUB
  chmod +x "$stub_dir/msb"
  export PATH="$stub_dir:$PATH"
}

# Explicit --name skips sandbox resolution and --clone-url skips the remote
# lookup, so each test drives only the assembly it cares about.
launch() {
  "$BATS_TEST_DIRNAME/../../scripts/launch-agent-runtime" \
    --name test-session \
    --clone-url https://example.invalid/repo.git \
    "$@" -- true
}

# Matched as a whole line, so a word-split value fails rather than matching
# on a substring.
has_arg() {
  grep -Fxq -- "$1" "$MSB_ARGS_FILE"
}

# $2 is the argument immediately following $1, again as whole lines.
has_flag_value() {
  grep -A1 -Fx -- "$1" "$MSB_ARGS_FILE" | grep -Fxq -- "$2"
}

# --- generic secret passthrough (kept; the GitHub specialisation is not) ---

@test "a plain --secret is forwarded to msb run unchanged" {
  run launch --secret OTHER@example.com
  [ "$status" -eq 0 ]
  has_flag_value "--secret" "OTHER@example.com"
}

@test "--secret alone adds no --on-secret-violation of its own" {
  run launch --secret OTHER@example.com
  [ "$status" -eq 0 ]
  ! has_arg "--on-secret-violation"
}

@test "an explicit --on-secret-violation is forwarded verbatim" {
  run launch --secret OTHER@example.com --on-secret-violation block-and-terminate
  [ "$status" -eq 0 ]
  has_flag_value "--on-secret-violation" "block-and-terminate"
}

# --- flags removed with the disposable model get no special handling; they
#     fall to the generic unknown-argument path. --github-token and
#     --persist-claude-auth are retired (ADR-0022); --force skipped the
#     replace confirmation that no longer exists, and returns with the reset
#     path (issue #146). ---

@test "the removed flags are rejected as unknown arguments" {
  for flag in --github-token --persist-claude-auth --no-persist-claude-auth --force; do
    run launch "$flag"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unrecognized argument"* ]]
    [ ! -f "$MSB_ARGS_FILE" ]
  done
}

@test "the create path carries no ~/.claude volume or PERSIST_CLAUDE_AUTH env" {
  run launch
  [ "$status" -eq 0 ]
  ! grep -q "/home/vscode/.claude" "$MSB_ARGS_FILE"
  ! grep -q "agent-claude-creds" "$MSB_ARGS_FILE"
  ! grep -q "PERSIST_CLAUDE_AUTH" "$MSB_ARGS_FILE"
}

# The sandbox lookup is the path that used jq (issue #83), so a launch that
# resolves its own name exercises it - unlike launch(), which passes --name.
@test "a launch never calls jq" {
  run "$BATS_TEST_DIRNAME/../../scripts/launch-agent-runtime" \
    --clone-url https://example.invalid/repo.git -- true
  [ "$status" -eq 0 ]
  [ ! -f "$JQ_CALLED_FILE" ]
}

# --- runtime lifecycle: which subcommand for which state (issue #144) ---
#
# The bare launch attaches to a running runtime, resumes a stopped one, and
# creates one only when none exists - never `msb run --replace`.

@test "no runtime for the repo: the launcher creates one with 'msb run'" {
  run launch
  [ "$status" -eq 0 ]
  [ -f "$MSB_ARGS_FILE" ]
  [ ! -f "$MSB_START_FILE" ]
  [ ! -f "$MSB_EXEC_FILE" ]
}

@test "a stopped runtime: the launcher resumes with 'msb start' then attaches, never 'msb run'" {
  export STUB_ALL="test-session"
  run launch
  [ "$status" -eq 0 ]
  grep -Fxq "test-session" "$MSB_START_FILE"
  [ -f "$MSB_EXEC_FILE" ]
  [ ! -f "$MSB_ARGS_FILE" ]
}

@test "a running runtime: the launcher attaches with 'msb exec' only, never 'msb start' or 'msb run'" {
  export STUB_ALL="test-session" STUB_RUNNING="test-session"
  run launch
  [ "$status" -eq 0 ]
  [ -f "$MSB_EXEC_FILE" ]
  [ ! -f "$MSB_START_FILE" ]
  [ ! -f "$MSB_ARGS_FILE" ]
}

@test "attach converges the runtime with agent-bringup before handing over" {
  export STUB_ALL="test-session" STUB_RUNNING="test-session"
  run launch
  [ "$status" -eq 0 ]
  grep -Fxq "agent-bringup" "$MSB_EXEC_FILE"
}

@test "attach runs the command as the vscode user in the workspace directory" {
  export STUB_ALL="test-session" STUB_RUNNING="test-session"
  run launch
  [ "$status" -eq 0 ]
  grep -A1 -Fx -- "-u" "$MSB_EXEC_FILE" | grep -Fxq -- "vscode"
  grep -A1 -Fx -- "-w" "$MSB_EXEC_FILE" | grep -Fxq -- "/home/vscode/repo"
}

@test "the create path no longer replaces a runtime or registers a boot script" {
  run launch
  [ "$status" -eq 0 ]
  ! has_arg "--replace"
  ! has_arg "--script-path"
  ! grep -q "workspace-init" "$MSB_ARGS_FILE"
}

@test "the create path passes the command straight through, unwrapped" {
  run launch
  [ "$status" -eq 0 ]
  # `-- true`, not `-- workspace-init true`.
  grep -A1 -Fx -- "--" "$MSB_ARGS_FILE" | grep -Fxq -- "true"
}

@test "the create path still forwards the clone URL and dotfiles repo as env" {
  run launch
  [ "$status" -eq 0 ]
  has_flag_value "--env" "WORKSPACE_CLONE_URL=https://example.invalid/repo.git"
  has_arg "--env"
}
