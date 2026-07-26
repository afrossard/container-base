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
# dockerd itself is started by docker-init.sh, installed by the
# docker-in-docker devcontainer feature (images/agent/devcontainer.json);
# the entrypoint drops the given command to vscode via runuser once the
# daemon is up, so several assertions below check for that user rather
# than root.
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

# docker-init.sh (the docker-in-docker feature) prints its own startup
# chatter to the same stream before handing off, so assertions below match
# a substring rather than the whole of $output.
@test "an explicit command runs and its output comes through" {
  run docker run --rm --privileged -v "${volume}:/var/lib/docker" "$IMAGE" echo hello
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
}

# Regression test for a bug this suite previously missed: the entrypoint's
# own log-filtering step (silencing docker-init.sh's cgroup-nesting noise)
# wrote its scratch file under /tmp, which docker-init.sh itself remounts
# as a fresh tmpfs partway through its own setup - wiping the file before
# the entrypoint could read it back, and leaking a "grep: ... No such file
# or directory" line into every single invocation. Only ever exercised
# under msb before, where /tmp happens to already be a mountpoint so the
# remount (and the bug) never fired; this suite's own docker run is what
# should have caught it, so this test exists specifically to keep it caught.
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

# docs/research/0022's header finding: a trivial pull/run can pass while a
# real multi-layer build still fails, because nested overlayfs only breaks
# once a build actually exercises the snapshotter. This fixture is a build,
# not just a run, for that reason.
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

@test "tini is PID 1, reaping dockerd" {
  run docker run --rm --privileged -v "${volume}:/var/lib/docker" "$IMAGE" \
    sh -c 'ps -o pid,comm -p 1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"tini"* ]]
}
