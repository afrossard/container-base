#!/usr/bin/env bash
# Sourced by scripts/launch-agent-runtime and scripts/cleanup-agent-sessions:
# the narrow ADR-0001/ADR-0014 host-tooling exception.

# Repo name: git remote's basename, else the toplevel dir, else $PWD.
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

# git remote get-url origin, verbatim - no fallback, a clone needs a real URL.
repo_url() {
  git remote get-url origin
}

# Prints the sourcing script's "# Usage:" block ($0 is that script, not this).
usage() {
  sed -n '/^# Usage:/,/^$/p' "$0" | cut -c3-
}

# Stops with one message if a host prerequisite is missing (see the README).
require_tools() {
  local tool missing=""
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing="$missing $tool"
    fi
  done
  if [ -n "$missing" ]; then
    echo "$(basename "$0"): missing host prerequisite(s):$missing" >&2
    echo "$(basename "$0"): see the README's \"Host prerequisites\" section" >&2
    exit 1
  fi
}

# `msb list` filters only by --running/--stopped, so test list membership
# rather than parse a status string.
contains_line() {
  case $'\n'"$1"$'\n' in
    *$'\n'"$2"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

sandbox_exists() {
  contains_line "$(msb list -q 2>/dev/null || true)" "$1"
}

sandbox_is_running() {
  contains_line "$(msb list --running -q 2>/dev/null || true)" "$1"
}

# Creates a named msb volume if it doesn't already exist. Extra args pass
# straight through to `msb volume create` (--kind, --size, ...).
ensure_volume() {
  local name="$1"
  shift
  msb volume inspect "$name" >/dev/null 2>&1 || msb volume create --name "$name" "$@"
}
