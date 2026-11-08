#!/usr/bin/env bats
#
# Tests for .github/scripts/check-release-pr-diff.sh, which fails a release PR
# that changes more than release-please's own version data (issue #239). Each
# test commits to a throwaway repo laid out like this one, so the script reads
# real git output.

setup() {
  script="$BATS_TEST_DIRNAME/../../.github/scripts/check-release-pr-diff.sh"

  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

  cd "$BATS_TEST_TMPDIR"
  git init --quiet --initial-branch=main

  mkdir -p scripts images/agent
  printf '# Changelog\n' > CHANGELOG.md
  printf '{\n  ".": "1.0.0"\n}\n' > .release-please-manifest.json
  printf 'version="1.0.0" # x-release-please-version\nfeature=on\n' > scripts/launch-agent-runtime
  printf 'ARG BASE_VERSION=1.0.0\nRUN true\n' > images/agent/Containerfile
  printf 'readme\n' > README.md
  git add .
  git commit --quiet -m "initial"

  git switch --quiet -c release-branch
}

commit_on_release_branch() {
  git add .
  git commit --quiet -m "chore(main): release 1.1.0"
}

@test "fails a release PR that changes a file release-please does not own" {
  printf 'edited\n' > README.md
  commit_on_release_branch

  run "$script" main release-branch

  [ "$status" -ne 0 ]
  [[ "$output" == *"README.md"* ]]
}

@test "passes a release PR that changes only the changelog and the manifest" {
  printf '# Changelog\n\n## 1.1.0\n' > CHANGELOG.md
  printf '{\n  ".": "1.1.0"\n}\n' > .release-please-manifest.json
  commit_on_release_branch

  run "$script" main release-branch

  [ "$status" -eq 0 ]
}

@test "passes a release PR that bumps a line annotated x-release-please-version" {
  printf 'version="1.1.0" # x-release-please-version\nfeature=on\n' > scripts/launch-agent-runtime
  commit_on_release_branch

  run "$script" main release-branch

  [ "$status" -eq 0 ]
}

@test "fails a release PR that reverts another line in a file carrying a version line" {
  printf 'version="1.1.0" # x-release-please-version\n' > scripts/launch-agent-runtime
  commit_on_release_branch

  run "$script" main release-branch

  [ "$status" -ne 0 ]
  [[ "$output" == *"scripts/launch-agent-runtime"* ]]
}

@test "passes a release PR that bumps the agent image's pinned base version" {
  printf 'ARG BASE_VERSION=1.1.0\nRUN true\n' > images/agent/Containerfile
  commit_on_release_branch

  run "$script" main release-branch

  [ "$status" -eq 0 ]
}

@test "fails a release PR that changes a BASE_VERSION line outside the agent Containerfile" {
  printf 'ARG BASE_VERSION=9.9.9\n' >> README.md
  commit_on_release_branch

  run "$script" main release-branch

  [ "$status" -ne 0 ]
  [[ "$output" == *"README.md"* ]]
}

@test "ignores changes that reached main after the release branch was cut" {
  printf 'version="1.1.0" # x-release-please-version\nfeature=on\n' > scripts/launch-agent-runtime
  commit_on_release_branch
  git switch --quiet main
  printf 'version="1.0.0" # x-release-please-version\nfeature=off\n' > scripts/launch-agent-runtime
  git add .
  git commit --quiet -m "feat: a later merge"

  run "$script" main release-branch

  [ "$status" -eq 0 ]
}

@test "fails a release PR that only changes a file's mode" {
  chmod +x README.md
  commit_on_release_branch

  run "$script" main release-branch

  [ "$status" -ne 0 ]
  [[ "$output" == *"README.md"* ]]
}

@test "names the repair when it fails" {
  printf 'edited\n' > README.md
  commit_on_release_branch

  run "$script" main release-branch

  [ "$status" -ne 0 ]
  [[ "$output" == *"dispatch the release workflow"* ]]
}
