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

# "name<TAB>status" for sandboxes matching this repo's label plus any
# exact-name match (pre-label sandboxes). A name in neither status list is
# reported "unknown", not dropped. Shared by the launcher's name
# resolution and cleanup-agent-sessions' listing.
matching_sandboxes() {
  local base="$1" names running stopped name status
  running=$(msb list --running -q 2>/dev/null || true)
  stopped=$(msb list --stopped -q 2>/dev/null || true)

  names=$(
    {
      msb list --label "repo=$base" -q 2>/dev/null || true
      if sandbox_exists "$base"; then printf '%s\n' "$base"; fi
    } | sort -u
  )
  if [ -z "$names" ]; then
    return 0
  fi

  while IFS= read -r name; do
    if [ -z "$name" ]; then
      continue
    fi
    if contains_line "$running" "$name"; then
      status=running
    elif contains_line "$stopped" "$name"; then
      status=stopped
    else
      status=unknown
    fi
    printf '%s\t%s\n' "$name" "$status"
  done <<<"$names"
}

# Creates a named msb volume if it doesn't already exist. Extra args pass
# straight through to `msb volume create` (--kind, --size, ...).
ensure_volume() {
  local name="$1"
  shift
  msb volume inspect "$name" >/dev/null 2>&1 || msb volume create --name "$name" "$@"
}

# Interactive "[y/N]" gate shared by every destructive host command. A
# no-op when $2 ("$force") is "1". Aborts the whole script (exit 1) on a
# non-terminal stdin or on any answer other than y/Y. $1 is the prompt
# string; messages are prefixed with $0's basename.
confirm_or_die() {
  local prompt="$1" force="$2" who reply
  who=$(basename "$0")
  [ "$force" = "1" ] && return 0
  if [ ! -t 0 ]; then
    echo "$who: stdin isn't a terminal to confirm on; pass --force to skip the prompt" >&2
    exit 1
  fi
  read -r -p "$prompt" reply
  case "$reply" in
    y | Y) return 0 ;;
    *)
      echo "$who: aborted" >&2
      exit 1
      ;;
  esac
}

# Destroys a sandbox and its paired docker-data volume - the single
# mechanism behind the launcher's --reset and cleanup-agent-sessions
# (ADR-0021). $2 overrides the volume name for a launch that set
# DOCKER_DATA_VOLUME; when it names no existing volume (the common case
# for cleanup, which cannot see that override) removal is simply skipped,
# but a volume that exists and then fails to remove is reported, not
# swallowed.
remove_runtime() {
  local name="$1" volume="${2:-${1}-docker-data}" who
  who=$(basename "$0")
  msb rm -f "$name"
  if msb volume inspect "$volume" >/dev/null 2>&1; then
    msb volume remove "$volume" >/dev/null 2>&1 \
      || echo "$who: could not remove docker volume '$volume'; remove it by hand with 'msb volume remove $volume'" >&2
  fi
}
