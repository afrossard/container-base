#!/usr/bin/env bash
# Used by the publish-*-image workflows to skip an unchanged variant's
# rebuild/republish: a version tag that only touches one variant's own
# directory shouldn't force a wasted, identical republish of the other.
# Needs full history and tags (actions/checkout with fetch-depth: 0),
# since it walks commit ancestry to find the previous tag.
#
# Usage: .github/scripts/changed-since-last-tag.sh <path> <current-tag>
# Prints "true" if <path> changed since the previous tag - or if there's
# no previous tag at all (the first release ever cut) - "false" otherwise.

set -euo pipefail

path="$1"
current_tag="$2"

previous_tag=$(git describe --tags --abbrev=0 "${current_tag}^" 2>/dev/null || true)

if [ -z "$previous_tag" ]; then
  echo "true"
  exit 0
fi

if git diff --quiet "$previous_tag" "$current_tag" -- "$path"; then
  echo "false"
else
  echo "true"
fi
