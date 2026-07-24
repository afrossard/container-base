#!/usr/bin/env bats
#
# Asserts the manifest actually pushed to GHCR is multi-arch. A
# multi-platform manifest cannot be loaded into the local docker image
# store, only pushed, so this runs against the real registry after
# publish - see issue #1's "Test assertions" item 12, and issue #3 for
# why the assertion has to live here rather than in test/dev.
#
# Expects IMAGE to name the tag just pushed (set by the publish
# workflow, e.g. ghcr.io/afrossard/container-base:1.4.2-dev).

setup_file() {
  : "${IMAGE:?set IMAGE to the pushed image ref}"
}

@test "published manifest lists linux/amd64 and linux/arm64" {
  run docker buildx imagetools inspect "$IMAGE" --raw
  [ "$status" -eq 0 ]

  platforms=$(jq -c '[.manifests[].platform | select(.architecture != "unknown") | "\(.os)/\(.architecture)"] | unique' <<<"$output")

  [[ "$platforms" == *"linux/amd64"* ]]
  [[ "$platforms" == *"linux/arm64"* ]]
}
