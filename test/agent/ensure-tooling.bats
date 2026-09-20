#!/usr/bin/env bats
#
# Direct guest-script tests for images/agent/ensure-tooling (issue #172):
# run it against a local clone URL in a throwaway $HOME, twice, and
# alongside ensure-workspace for the workspace-equals-tooling-clone
# collision case. Prior art: test/agent/ensure-workspace.bats.
#
# No image needed: the script is /bin/sh plus git.

setup() {
  script="$BATS_TEST_DIRNAME/../../images/agent/ensure-tooling"
  workspace_script="$BATS_TEST_DIRNAME/../../images/agent/ensure-workspace"

  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"

  # A bare repo named like a real remote, so `basename URL .git` resolves
  # the tooling directory the way it does in production.
  work="$BATS_TEST_TMPDIR/work"
  mkdir -p "$work"
  git -C "$work" init -q -b main
  echo "first" > "$work/file.txt"
  git -C "$work" -c user.email=t@example.com -c user.name=t add -A
  git -C "$work" -c user.email=t@example.com -c user.name=t commit -q -m init
  git clone -q --bare "$work" "$BATS_TEST_TMPDIR/repo.git"

  export TOOLING_REPO="file://$BATS_TEST_TMPDIR/repo.git"
  repo_dir="$HOME/git/repo"
}

@test "first run clones the tooling repo" {
  run sh "$script"
  [ "$status" -eq 0 ]
  [ -f "$repo_dir/file.txt" ]
  [ "$(cat "$repo_dir/file.txt")" = "first" ]
}

@test "a second run against an existing clone succeeds and is a no-op" {
  run sh "$script"
  [ "$status" -eq 0 ]

  # Local edit that a re-clone, or a force-update, would blow away.
  echo "local work" > "$repo_dir/file.txt"

  run sh "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already present"* ]]
  [ "$(cat "$repo_dir/file.txt")" = "local work" ]
}

@test "an unset TOOLING_REPO is a no-op that exits 0 (bare image run)" {
  unset TOOLING_REPO
  run sh "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to clone"* ]]
  [ ! -e "$repo_dir" ]
}

# --- collision: this repo's own runtime, where the workspace clone and the
#     tooling clone default to the same URL and land at the same path
#     (#169's stated no-special-casing case). ---

@test "workspace-equals-tooling-clone collision: ensure-workspace then ensure-tooling clones once and both no-op after" {
  export WORKSPACE_CLONE_URL="$TOOLING_REPO"

  run sh "$workspace_script"
  [ "$status" -eq 0 ]
  [ -f "$repo_dir/file.txt" ]

  run sh "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already present"* ]]
  [ "$(cat "$repo_dir/file.txt")" = "first" ]
}

@test "workspace-equals-tooling-clone collision, reversed order: ensure-tooling then ensure-workspace clones once and both no-op after" {
  export WORKSPACE_CLONE_URL="$TOOLING_REPO"

  run sh "$script"
  [ "$status" -eq 0 ]
  [ -f "$repo_dir/file.txt" ]

  run sh "$workspace_script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already present"* ]]
  [ "$(cat "$repo_dir/file.txt")" = "first" ]
}
