#!/usr/bin/env bats
#
# Direct guest-script tests for images/agent/ensure-workspace: run it
# against a local clone URL in a throwaway $HOME, twice. The second run is
# what a resumed runtime does (issue #144), and it must succeed on a
# workspace that is already there.
#
# No image needed: the script is /bin/sh plus git.

setup() {
  script="$BATS_TEST_DIRNAME/../../images/agent/ensure-workspace"

  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"

  # A bare repo named like a real remote, so `basename URL .git` resolves
  # the workspace directory the way it does in production.
  work="$BATS_TEST_TMPDIR/work"
  mkdir -p "$work"
  git -C "$work" init -q -b main
  echo "first" > "$work/file.txt"
  git -C "$work" -c user.email=t@example.com -c user.name=t add -A
  git -C "$work" -c user.email=t@example.com -c user.name=t commit -q -m init
  git clone -q --bare "$work" "$BATS_TEST_TMPDIR/repo.git"

  export WORKSPACE_CLONE_URL="file://$BATS_TEST_TMPDIR/repo.git"
  repo_dir="$HOME/repo"
}

@test "first run clones the workspace" {
  run sh "$script"
  [ "$status" -eq 0 ]
  [ -f "$repo_dir/file.txt" ]
  [ "$(cat "$repo_dir/file.txt")" = "first" ]
}

@test "a second run against an existing workspace succeeds and is a no-op" {
  run sh "$script"
  [ "$status" -eq 0 ]

  # Local edit that a re-clone would blow away.
  echo "local work" > "$repo_dir/file.txt"

  run sh "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already present"* ]]
  [ "$(cat "$repo_dir/file.txt")" = "local work" ]
}

@test "a directory that exists but is not a clone is not mistaken for one" {
  mkdir -p "$repo_dir"
  echo "junk" > "$repo_dir/stray"

  run sh "$script"
  [ "$status" -ne 0 ]
}

@test "an unset WORKSPACE_CLONE_URL is a no-op that exits 0 (bare image run)" {
  unset WORKSPACE_CLONE_URL
  run sh "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to clone"* ]]
  [ ! -e "$repo_dir" ]
}
