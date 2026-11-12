#!/usr/bin/env bash
# Packs the host-side scripts into the release asset the tap's formula
# installs, with the launcher's agent image pinned by digest (ADR-0028).
#
# The committed launcher names the image by tag only, because the release
# commit is tagged before the image exists. This writes the digest of the
# image that release published into a copy, so the formula's sha256 covers
# the exact image the launcher runs.
#
# Run from the repo root.
# Usage: .github/scripts/package-launcher.sh <version> <digest> <out-file>

set -euo pipefail

version="$1"
digest="$2"
out="$3"

launcher=scripts/launch-agent-runtime
image_line='image="ghcr.io/afrossard/container-base:${version}-agent"'

if ! [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "package-launcher: '$digest' is not a sha256 digest" >&2
  exit 1
fi

# A launcher from another release would pin this release's digest under the
# wrong version, so the tree must be the release commit's.
if ! grep -qxF "version=\"${version}\" # x-release-please-version" "$launcher"; then
  echo "package-launcher: $launcher does not carry version ${version}" >&2
  exit 1
fi

if [ "$(grep -cxF "$image_line" "$launcher")" -ne 1 ]; then
  echo "package-launcher: $launcher needs exactly one line: $image_line" >&2
  exit 1
fi

staging="$(mktemp -d "$(dirname "$out")/.package-launcher.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

top="agent-runtime-${version}"
mkdir -p "$staging/$top"
cp -Rp scripts LICENSE "$staging/$top/"

pinned_line="${image_line%\"}@${digest}\""
awk -v from="$image_line" -v to="$pinned_line" \
  '$0 == from { print to; next } { print }' \
  "$launcher" > "$staging/$top/$launcher"

tar -czf "$out" -C "$staging" "$top"
