#!/usr/bin/env bash
# Shared by scripts/launch-agent-runtime and scripts/cleanup-agent-sessions.
# Sourced, not executed - both scripts are the narrow ADR-0001/ADR-0014
# exception; this file lives alongside them rather than widening it.

# The repo a launch/cleanup invocation is acting on: git remote get-url
# origin's basename, falling back to the toplevel directory name, falling
# back to the current directory name outside any git repo.
repo_name() {
  local repo
  if repo=$(git remote get-url origin 2>/dev/null); then
    repo=$(basename "$repo" .git)
  elif repo=$(git rev-parse --show-toplevel 2>/dev/null); then
    repo=$(basename "$repo")
  else
    repo=$(basename "$PWD")
  fi
  printf '%s' "$repo"
}

# The URL workspace-init clones from by default: git remote get-url
# origin, verbatim. Unlike repo_name() this has no fallback - a clone
# needs a real URL, and there is no sane default once origin is absent.
repo_url() {
  git remote get-url origin
}

# Extracts the "# Usage:" comment block from whichever script sources this
# file - $0 is the top-level script actually being run, not this file.
usage() {
  sed -n '/^# Usage:/,/^$/p' "$0" | cut -c3-
}

# Creates a named msb volume if it doesn't already exist. Extra args pass
# straight through to `msb volume create` (--kind, --size, ...).
ensure_volume() {
  local name="$1"
  shift
  msb volume inspect "$name" >/dev/null 2>&1 || msb volume create --name "$name" "$@"
}
