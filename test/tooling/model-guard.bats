#!/usr/bin/env bats
#
# tooling/firstmate/model-guard: exits non-zero when configuration or a
# live process selects a barred model tier (opus, fable), and stays quiet
# when nothing does. Config roots and the process source are both
# injectable, so these cover the check logic directly.

GUARD="$BATS_TEST_DIRNAME/../../tooling/firstmate/model-guard"

setup() {
  root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root"
  # No live processes unless a test overrides this.
  export MODEL_GUARD_PS=true
}

@test "a clean config tree and no processes: exit 0" {
  printf 'model: sonnet\n' >"$root/agent.yaml"
  run "$GUARD" "$root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean"* ]]
}

@test "a yaml model assignment to a barred tier: exit 1, names the file" {
  printf 'agent:\n  model: opus\n' >"$root/no-mistakes.yaml"
  run "$GUARD" "$root"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no-mistakes.yaml"* ]]
  [[ "$output" == *"opus"* ]]
}

@test "a barred slug anywhere in a nested file: exit 1" {
  mkdir -p "$root/config"
  printf 'anthropic/claude-fable-5\n' >"$root/config/supervision-branch-model"
  run "$GUARD" "$root"
  [ "$status" -eq 1 ]
  [[ "$output" == *"supervision-branch-model"* ]]
}

@test "the match is case-insensitive" {
  printf 'MODEL=OPUS\n' >"$root/captain.env"
  run "$GUARD" "$root"
  [ "$status" -eq 1 ]
}

@test "a leading-comment line naming a barred tier does not trip the guard" {
  printf '# never select opus or fable here\nmodel: sonnet\n' >"$root/notes.conf"
  run "$GUARD" "$root"
  [ "$status" -eq 0 ]
}

@test "a file opting out of the prose scan is skipped" {
  printf '<!-- model-guard: skip-prose-scan -->\nThe opus and fable tiers are barred.\n' >"$root/POLICY.md"
  run "$GUARD" "$root"
  [ "$status" -eq 0 ]
}

@test "a live process on a barred tier: exit 1, shows the command" {
  printf 'model: sonnet\n' >"$root/agent.yaml"
  echo 'node /x/claude --model opus --print' >"$BATS_TEST_TMPDIR/ps.txt"
  export MODEL_GUARD_PS="cat $BATS_TEST_TMPDIR/ps.txt"
  run "$GUARD" "$root"
  [ "$status" -eq 1 ]
  [[ "$output" == *"process"* ]]
  [[ "$output" == *"--model opus"* ]]
}

@test "live processes all on allowed models: exit 0" {
  printf 'model: sonnet\n' >"$root/agent.yaml"
  echo 'node /x/claude --model sonnet' >"$BATS_TEST_TMPDIR/ps.txt"
  export MODEL_GUARD_PS="cat $BATS_TEST_TMPDIR/ps.txt"
  run "$GUARD" "$root"
  [ "$status" -eq 0 ]
}

@test "the guard's own scan pipeline in the process list is not a hit" {
  printf 'model: sonnet\n' >"$root/agent.yaml"
  {
    echo 'grep -iE opus|fable'
    echo 'node /x/claude --model sonnet'
  } >"$BATS_TEST_TMPDIR/ps.txt"
  export MODEL_GUARD_PS="cat $BATS_TEST_TMPDIR/ps.txt"
  run "$GUARD" "$root"
  [ "$status" -eq 0 ]
}

@test "explicit ROOT args are honoured over the defaults" {
  clean="$BATS_TEST_TMPDIR/clean"
  dirty="$BATS_TEST_TMPDIR/dirty"
  mkdir -p "$clean" "$dirty"
  printf 'model: sonnet\n' >"$clean/a.yaml"
  printf 'model: fable\n' >"$dirty/b.yaml"
  run "$GUARD" "$clean"
  [ "$status" -eq 0 ]
  run "$GUARD" "$clean" "$dirty"
  [ "$status" -eq 1 ]
  [[ "$output" == *"b.yaml"* ]]
}

@test "the recipe's own shipped configuration passes the guard" {
  run "$GUARD" "$BATS_TEST_DIRNAME/../../tooling/firstmate"
  [ "$status" -eq 0 ]
}

@test "the guard excludes its own file even via a non-normalized root" {
  recipe="$BATS_TEST_DIRNAME/../../tooling/firstmate"
  run "$GUARD" "$recipe/../firstmate"
  [ "$status" -eq 0 ]
}
