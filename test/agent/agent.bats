#!/usr/bin/env bats
#
# Runs against the real image built from images/agent/, not the Containerfile
# or devcontainer.json source. See issue #1's "Test assertions" section:
# assert through the door a user walks through.
#
# A plain `docker run` nests this image's own dockerd inside a container
# whose root filesystem is already overlayfs, so /var/lib/docker needs its
# own filesystem or the daemon fails to mount its first layer - the same
# nested-overlay failure docs/research/0022 found for microsandbox's default
# mount, worked around here with a scratch docker volume in place of msb's
# disk-backed one. --privileged is this suite's own substitute for whatever
# capabilities a real launch profile grants; it is not the launcher script's
# own profile (that's exercised separately, against msb itself).
#
# Expects IMAGE to name an already-built image (set by `npm run test:agent`,
# which passes the same tag `npm run build:agent` built).

setup_file() {
  : "${IMAGE:?set IMAGE to the image tag built by \`npm run build:agent\`}"
}

setup() {
  volume="agent-test-docker-data-${BATS_TEST_NUMBER}-$$"
  docker volume create "$volume" >/dev/null
}

teardown() {
  docker volume rm -f "$volume" >/dev/null 2>&1 || true
}

@test "an explicit command runs and its output comes through" {
  run docker run --rm --privileged -v "${volume}:/var/lib/docker" "$IMAGE" echo hello
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}

@test "no command given fails rather than falling back to a default" {
  run docker run --rm --privileged -v "${volume}:/var/lib/docker" "$IMAGE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no default command"* ]]
}

@test "the container exits when the given command exits, with no lingering process" {
  name="agent-lingering-test-$$"
  docker run -d --privileged -v "${volume}:/var/lib/docker" --name "$name" "$IMAGE" \
    sh -c 'sleep 1; echo done' >/dev/null

  run docker wait "$name"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  run docker inspect -f '{{.State.Status}}' "$name"
  [ "$status" -eq 0 ]
  [ "$output" = "exited" ]

  docker rm -f "$name" >/dev/null
}

@test "dockerd starts with overlayfs storage, not a vfs fallback" {
  run docker run --rm --privileged -v "${volume}:/var/lib/docker" "$IMAGE" \
    sh -c 'docker info --format "{{.Driver}}"'
  [ "$status" -eq 0 ]
  [ "$output" = "overlayfs" ]
}

@test "a real container build and run succeeds inside the guest" {
  run docker run --rm --privileged -v "${volume}:/var/lib/docker" "$IMAGE" sh -c '
    set -e
    docker run --rm alpine echo container-ok
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"container-ok"* ]]
}

@test "tini is PID 1, reaping dockerd" {
  run docker run --rm --privileged -v "${volume}:/var/lib/docker" "$IMAGE" \
    sh -c 'ps -o pid,comm -p 1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"tini"* ]]
}
