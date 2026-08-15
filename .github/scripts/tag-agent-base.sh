#!/usr/bin/env bash
# Tags a just-built dev image as the version-pinned base the agent image's
# Containerfile expects (ADR-0018), so `docker build`'s default (no
# --pull) behaviour resolves FROM against the local build rather than
# reaching for a registry copy that may not exist yet - a release PR's
# bumped pin has no published -dev tag until merge.
#
# Usage: .github/scripts/tag-agent-base.sh <source-image> <containerfile>

set -euo pipefail

source_image="$1"
containerfile="$2"

base_version=$(sed -n 's/^ARG BASE_VERSION=\(.*\)$/\1/p' "$containerfile")

if [ -z "$base_version" ]; then
  echo "tag-agent-base: no 'ARG BASE_VERSION=' line found in $containerfile" >&2
  exit 1
fi

docker tag "$source_image" "ghcr.io/afrossard/container-base:${base_version}-dev"
