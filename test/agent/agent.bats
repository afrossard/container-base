#!/usr/bin/env bats
#
# Runs against the real image built from images/agent/ (issue #1: assert
# through the door a user walks through).
#
# A `docker run` nests this image's dockerd inside an already-overlayfs
# container, so /var/lib/docker needs its own filesystem (docs/research/0022);
# a scratch docker volume stands in for msb's disk-backed mount. --privileged
# substitutes for a real launch profile's capabilities.
#
# The entrypoint drops the command to vscode via runuser once dockerd is up,
# so several assertions check for that user rather than root.
#
# Expects IMAGE to name an already-built image (set by `npm run test:agent`).

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

# docker-init.sh prints startup chatter to the same stream, so assertions
# match a substring rather than the whole of $output.
@test "an explicit command runs and its output comes through" {
  run docker run --rm --privileged -v "${volume}:/var/lib/docker" "$IMAGE" echo hello
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
}

# Regression: the entrypoint's log-filtering step wrote its scratch file
# under /tmp, which docker-init.sh remounts as a fresh tmpfs mid-setup,
# leaking a "grep: No such file or directory" line. Never fired under msb,
# where /tmp is already a mountpoint; this suite's docker run catches it.
@test "no entrypoint plumbing (grep/log-file errors) leaks into the output" {
  run docker run --rm --privileged -v "${volume}:/var/lib/docker" "$IMAGE" echo hello
  [ "$status" -eq 0 ]
  [[ "$output" != *"No such file or directory"* ]]
  [[ "$output" != *"grep:"* ]]
}

@test "the given command runs as vscode, not root, and can reach the docker socket without sudo" {
  run docker run --rm --privileged -v "${volume}:/var/lib/docker" "$IMAGE" id
  [ "$status" -eq 0 ]
  [[ "$output" == *"uid=1000(vscode) gid=1000(vscode) groups=1000(vscode),999(docker)"* ]]
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
  [[ "$output" == *"overlayfs"* ]]
}

@test "a real container run succeeds inside the guest" {
  run docker run --rm --privileged -v "${volume}:/var/lib/docker" "$IMAGE" sh -c '
    set -e
    docker run --rm alpine echo container-ok
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"container-ok"* ]]
}

# docs/research/0022: a trivial pull/run can pass while a real multi-layer
# build fails, since nested overlayfs only breaks once a build exercises
# the snapshotter.
@test "a real multi-layer docker build succeeds inside the guest" {
  run docker run --rm --privileged \
    -v "${volume}:/var/lib/docker" \
    -v "${BATS_TEST_DIRNAME}/fixtures/multilayer:/build:ro" \
    "$IMAGE" sh -c '
      set -e
      docker build -f /build/Containerfile -t multilayer-test /build
      docker run --rm multilayer-test
    '
  [ "$status" -eq 0 ]
  [[ "$output" == *"layer1"* ]]
  [[ "$output" == *"layer2"* ]]
  [[ "$output" == *"layer3"* ]]
}

# Issue #66: with no service manager, an in-session containerd.io upgrade
# leaves the old daemon forking a new shim, breaking every `docker run` for
# the boot with "failed to create TTRPC connection: unsupported protocol:
# Yunix".
@test "the docker engine packages are held against in-session upgrades" {
  run docker run --rm --privileged -v "${volume}:/var/lib/docker" "$IMAGE" apt-mark showhold
  [ "$status" -eq 0 ]
  [[ "$output" == *"containerd.io"* ]]
  [[ "$output" == *"docker-ce"* ]]
  [[ "$output" == *"docker-ce-cli"* ]]
}

# The regression test proper for #66: a real upgrade, then a real
# container, so it goes red on the bug itself, not just on the hold.
@test "a docker run still works after an in-session apt upgrade" {
  run docker run --rm --privileged -v "${volume}:/var/lib/docker" "$IMAGE" sh -c '
    set -e
    sudo apt-get update -qq >/dev/null
    sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq >/dev/null
    docker run --rm alpine echo container-ok-after-upgrade
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"container-ok-after-upgrade"* ]]
}

@test "tini is PID 1, reaping dockerd" {
  run docker run --rm --privileged -v "${volume}:/var/lib/docker" "$IMAGE" \
    sh -c 'ps -o pid,comm -p 1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"tini"* ]]
}
