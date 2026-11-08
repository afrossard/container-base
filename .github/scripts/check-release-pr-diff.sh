#!/usr/bin/env bash
# Fails a release PR that changes more than release-please's own version data
# (issue #239). release-please writes whole files from a tree it may have read
# before main moved, so a release PR can silently revert a merged change
# (https://github.com/googleapis/release-please/issues/2890).
#
# Compares from the merge base, so a main that has moved on since the release
# branch was cut doesn't read as a revert.
#
# Usage: .github/scripts/check-release-pr-diff.sh <base> <head>

set -euo pipefail

range="$1...$2"

unexpected=()

while IFS= read -r file; do
  allowed_lines='x-release-please-version'
  case "$file" in
    CHANGELOG.md | .release-please-manifest.json) continue ;;
    images/agent/Containerfile) allowed_lines+='|^[-+]ARG BASE_VERSION=' ;;
  esac

  # Everything after the first hunk header is a changed line, whatever it
  # starts with, so a removed "-- " line can't pass for a "---" file header.
  changed=$(git diff -U0 --no-renames "$range" -- "$file" |
    awk '/^@@/ { in_hunk = 1; next } in_hunk && /^[-+]/')

  # No changed lines means a mode or binary change, which is never a version bump.
  if [ -z "$changed" ] || grep -qvE "$allowed_lines" <<<"$changed"; then
    unexpected+=("$file")
  fi
done < <(git diff --name-only --no-renames "$range")

if [ "${#unexpected[@]}" -gt 0 ]; then
  echo "check-release-pr-diff: this release PR changes more than version data:" >&2
  printf '  %s\n' "${unexpected[@]}" >&2
  echo "Do not merge it: release-please may have reverted a merged change." >&2
  echo "To repair it, dispatch the release workflow, which regenerates every file from current main (docs/agents/gotchas.md)." >&2
  exit 1
fi
