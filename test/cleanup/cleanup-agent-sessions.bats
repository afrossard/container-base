#!/usr/bin/env bats
#
# Tests for scripts/cleanup-agent-sessions: a bare call lists, --name and
# --all remove, and the script refuses in the cases where removing would
# be wrong.
#
# A stub msb answers list/list --running/list --stopped from STUB_ALL and
# STUB_RUNNING, and records what it was asked to remove.

setup() {
  stub_dir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$stub_dir"
  cp "$BATS_TEST_DIRNAME/../helpers/msb" "$BATS_TEST_DIRNAME/../helpers/jq" "$stub_dir/"
  chmod +x "$stub_dir/msb" "$stub_dir/jq"
  export PATH="$stub_dir:$PATH"

  # Read by the tests below; see test/helpers/msb for the stub itself.
  export MSB_RM_FILE="$BATS_TEST_TMPDIR/msb-rm"
  export JQ_CALLED_FILE="$BATS_TEST_TMPDIR/jq-called"

  export STUB_ALL=""
  export STUB_RUNNING=""
}

cleanup() {
  "$BATS_TEST_DIRNAME/../../scripts/cleanup-agent-sessions" "$@"
}

# --- bare: list, remove nothing (issue #146) ---

@test "a bare call lists this repo's runtimes with their state and removes nothing" {
  export STUB_ALL="alpha beta" STUB_RUNNING="alpha"
  run cleanup
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"running"* ]]
  [[ "$output" == *"beta"* ]]
  [[ "$output" == *"stopped"* ]]
  [[ "$output" == *"--name"* ]]
  [[ "$output" == *"--all"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "a bare call with no runtimes for the repo says so and removes nothing" {
  export STUB_ALL="" STUB_RUNNING=""
  run cleanup
  [ "$status" -eq 0 ]
  [[ "$output" == *"no runtimes for"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "the usage text describes the list default, both removal flags, and reset" {
  run cleanup --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"list this repo's runtimes"* ]]
  [[ "$output" == *"--name SESSION"* ]]
  [[ "$output" == *"--all"* ]]
  [[ "$output" == *"launch-agent-runtime --reset"* ]]
}

# --- --name: one runtime ---

@test "a running runtime is not removed by --name without --force" {
  export STUB_ALL="alpha" STUB_RUNNING="alpha"
  run cleanup --name alpha
  [ "$status" -ne 0 ]
  [[ "$output" == *"'alpha' is running"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

# --name acts only on this repo's label set; a name that exists for
# another repo is refused, not removed.
@test "--name for a runtime outside this repo's label set is refused" {
  export STUB_ALL="alpha other-repo-box" STUB_LABELLED="alpha"
  run cleanup --name other-repo-box --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"no runtime named 'other-repo-box'"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "--name --force removes a running runtime" {
  export STUB_ALL="alpha" STUB_RUNNING="alpha"
  run cleanup --name alpha --force
  [ "$status" -eq 0 ]
  grep -Fxq alpha "$MSB_RM_FILE"
}

# An unknown name is a typo; silently doing nothing would read as success.
@test "--name for a runtime that does not exist is reported, not ignored" {
  export STUB_ALL="alpha" STUB_RUNNING=""
  run cleanup --name beta --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"no runtime named"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "--name removes a stopped runtime without hitting the running-guard" {
  export STUB_ALL="alpha" STUB_RUNNING=""
  run cleanup --name alpha --force
  [ "$status" -eq 0 ]
  grep -Fxq alpha "$MSB_RM_FILE"
}

@test "--name --dry-run removes nothing" {
  export STUB_ALL="alpha" STUB_RUNNING=""
  run cleanup --name alpha --dry-run
  [ "$status" -eq 0 ]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "--name without --force refuses on a non-terminal stdin rather than removing unprompted" {
  export STUB_ALL="alpha" STUB_RUNNING=""
  run cleanup --name alpha
  [ "$status" -ne 0 ]
  [[ "$output" == *"terminal"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

# --- --all: the batch ---

@test "--all --force removes every runtime for the repo, running or not" {
  export STUB_ALL="alpha beta gamma" STUB_RUNNING="beta"
  run cleanup --all --force
  [ "$status" -eq 0 ]
  grep -Fxq alpha "$MSB_RM_FILE"
  grep -Fxq beta "$MSB_RM_FILE"
  grep -Fxq gamma "$MSB_RM_FILE"
}

@test "--all --force with only running runtimes still removes them" {
  export STUB_ALL="alpha" STUB_RUNNING="alpha"
  run cleanup --all --force
  [ "$status" -eq 0 ]
  grep -Fxq alpha "$MSB_RM_FILE"
}

@test "--all --dry-run lists the stopped ones, marks the running ones kept, removes nothing" {
  export STUB_ALL="alpha beta" STUB_RUNNING="beta"
  run cleanup --all --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"keeping these"* ]]
  [[ "$output" == *"beta"* ]]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"nothing removed"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "--all without --force and with only running runtimes removes nothing and says so" {
  export STUB_ALL="alpha" STUB_RUNNING="alpha"
  run cleanup --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"no stopped runtimes for"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "--all without --force refuses on a non-terminal stdin rather than removing unprompted" {
  export STUB_ALL="alpha beta" STUB_RUNNING=""
  run cleanup --all
  [ "$status" -ne 0 ]
  [[ "$output" == *"terminal"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "--all with no runtimes for the repo says so" {
  export STUB_ALL="" STUB_RUNNING=""
  run cleanup --all --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"no runtimes for"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "--name and --all together is rejected" {
  export STUB_ALL="alpha" STUB_RUNNING=""
  run cleanup --name alpha --all --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"not both"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "cleanup never calls jq" {
  export STUB_ALL="alpha" STUB_RUNNING="alpha"
  run cleanup --name alpha --force
  [ "$status" -eq 0 ]
  [ ! -f "$JQ_CALLED_FILE" ]
}
