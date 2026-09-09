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
  export MSB_RM_FILE="$BATS_TEST_TMPDIR/msb-rm"
  export MSB_VOLUME_FILE="$BATS_TEST_TMPDIR/msb-volume"

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
    labelled=0
    for a in "$@"; do
      case "$a" in
        --running) want=running ;;
        --stopped) want=stopped ;;
        --label) labelled=1 ;;
      esac
    done
    # `list --label repo=<repo>` answers from STUB_LABELLED when set, so a
    # test can make a name exist globally but not for this repo; every
    # other `list` still answers from STUB_ALL.
    src="$STUB_ALL"
    if [ "$labelled" = 1 ] && [ -n "${STUB_LABELLED+x}" ]; then
      src="$STUB_LABELLED"
    fi
    for n in $src; do
      case " $STUB_RUNNING " in
        *" $n "*) [ "$want" = stopped ] || printf '%s\n' "$n" ;;
        *) [ "$want" = running ] || printf '%s\n' "$n" ;;
      esac
    done
    ;;
  volume)
    # Records the call ("$2" is the verb: inspect / create / remove), then
    # succeeds - a successful `volume inspect` means ensure_volume never
    # calls create.
    printf '%s\n' "$@" >> "$MSB_VOLUME_FILE"
    exit 0
    ;;
  rm)
    printf '%s\n' "$@" >> "$MSB_RM_FILE"
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
#     --persist-claude-auth are retired (ADR-0022). --force is no longer
#     retired: it is the reset path's confirmation override (issue #146),
#     tested below. ---

@test "the removed credential flags are rejected as unknown arguments" {
  for flag in --github-token --persist-claude-auth --no-persist-claude-auth; do
    run launch "$flag"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unrecognized argument"* ]]
    [ ! -f "$MSB_ARGS_FILE" ]
  done
}

# --- reset: the one launcher path that destroys a runtime (issue #146) ---
#
# reset() calls the script directly: unlike launch(), it appends no
# `-- true` and no --clone-url, because reset returns before either is
# read. reset_bare() drops --name too, exercising reset's own runtime
# resolution.

reset() {
  "$BATS_TEST_DIRNAME/../../scripts/launch-agent-runtime" \
    --name test-session --reset "$@"
}

reset_bare() {
  "$BATS_TEST_DIRNAME/../../scripts/launch-agent-runtime" --reset "$@"
}

@test "--reset with --force destroys the runtime and its paired docker volume, and creates nothing" {
  export STUB_ALL="test-session"
  run reset --force
  [ "$status" -eq 0 ]
  grep -Fxq "test-session" "$MSB_RM_FILE"
  grep -Fxq "remove" "$MSB_VOLUME_FILE"
  grep -Fxq "test-session-docker-data" "$MSB_VOLUME_FILE"
  [ ! -f "$MSB_ARGS_FILE" ]
  [ ! -f "$MSB_START_FILE" ]
}

@test "--reset honours DOCKER_DATA_VOLUME when removing the paired volume" {
  export STUB_ALL="test-session"
  export DOCKER_DATA_VOLUME="custom-data-vol"
  run reset --force
  [ "$status" -eq 0 ]
  grep -Fxq "custom-data-vol" "$MSB_VOLUME_FILE"
}

@test "--reset --name for a runtime that does not exist removes nothing and says so" {
  export STUB_ALL=""
  run reset --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"no runtime named 'test-session'"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

# --reset acts only on this repo's label set, so a --name that exists for
# another repo is refused, not destroyed.
@test "--reset --name for a runtime outside this repo's label set is refused" {
  export STUB_ALL="test-session other-repo-box"
  export STUB_LABELLED="test-session"
  run "$BATS_TEST_DIRNAME/../../scripts/launch-agent-runtime" \
    --name other-repo-box --reset --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"no runtime named 'other-repo-box'"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "a bare --reset with no runtime for the repo removes nothing and says so" {
  export STUB_ALL=""
  run reset_bare --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"no runtime for"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

# reset targets this repo's runtime directly - it must never fall through
# to the attach picker's "start a new one" branch.
@test "a bare --reset with several matching runtimes refuses and asks for --name" {
  export STUB_ALL="one two"
  run reset_bare --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"pass --name"* ]]
  [[ "$output" != *"start a new one"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "a bare --reset with exactly one matching runtime destroys it" {
  export STUB_ALL="solo"
  run reset_bare --force
  [ "$status" -eq 0 ]
  grep -Fxq "solo" "$MSB_RM_FILE"
  grep -Fxq "solo-docker-data" "$MSB_VOLUME_FILE"
}

@test "--reset without --force refuses when stdin isn't a terminal, and removes nothing" {
  export STUB_ALL="test-session"
  run reset
  [ "$status" -ne 0 ]
  [[ "$output" == *"terminal"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "--force without --reset is rejected" {
  run launch --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"--force only applies to --reset"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "no bare launch path removes a runtime" {
  export STUB_ALL="test-session" STUB_RUNNING="test-session"
  run launch
  [ "$status" -eq 0 ]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "the usage text names reset as the launcher's only destruction path" {
  run "$BATS_TEST_DIRNAME/../../scripts/launch-agent-runtime" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--reset is the only launcher path that destroys a runtime"* ]]
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
