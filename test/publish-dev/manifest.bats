#!/usr/bin/env bats
#
# Asserts the manifest pushed to GHCR is multi-arch. A multi-platform
# manifest can only be pushed, not loaded locally, so this runs against the
# real registry after publish (issues #1, #3).
#
# Expects IMAGE to name the tag just pushed (set by the publish workflow).

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
