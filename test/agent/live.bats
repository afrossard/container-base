#!/usr/bin/env bats
#
# The live lifecycle test issue #144 rests on: create a runtime, write a
# marker to its rootfs (not a volume), stop it, start it, and confirm the
# marker survived - then that agent-bringup brings the docker daemon back
# up on the resumed runtime, which `msb start` leaves down.
#
# Needs a real `msb` on a KVM-capable host and an agent image `msb` can
# boot, named by MSB_LIVE_IMAGE. Skips cleanly everywhere else, so it is
# inert in CI (no msb) and in a plain `npm run test:agent`.
#
#   MSB_LIVE_IMAGE=ghcr.io/afrossard/container-base:X.Y.Z-agent \
#     bats test/agent/live.bats

setup_file() {
  if ! command -v msb >/dev/null 2>&1; then
    export LIVE_SKIP="no msb on PATH"
  elif [ -z "${MSB_LIVE_IMAGE:-}" ]; then
    export LIVE_SKIP="set MSB_LIVE_IMAGE to an agent image msb can boot"
  elif ! msb doctor >/dev/null 2>&1; then
    export LIVE_SKIP="msb doctor reports the host cannot run sandboxes (no KVM?)"
  fi

  export LIVE_NAME="cb144-live-$$"
  export LIVE_DOCKER_VOL="${LIVE_NAME}-docker-data"
  export LIVE_MARKER="/home/vscode/.msb-lifecycle-marker"
}

teardown_file() {
  [ -n "${LIVE_SKIP:-}" ] && return 0
  msb rm -f "$LIVE_NAME" >/dev/null 2>&1 || true
  msb volume rm "$LIVE_DOCKER_VOL" >/dev/null 2>&1 || true
}

setup() {
  [ -n "${LIVE_SKIP:-}" ] && skip "$LIVE_SKIP"
}

exec_in() {
  msb exec --no-tty "$LIVE_NAME" -- "$@"
}

@test "a marker on the rootfs survives stop then start, and bringup restores dockerd" {
  # Create. `sleep` keeps the runtime up; the entrypoint still runs
  # agent-bringup first, so this is a real first boot.
  msb run --no-tty --name "$LIVE_NAME" --net public \
    --mount-named "${LIVE_DOCKER_VOL}:/var/lib/docker:kind=disk,size=10G" \
    "$MSB_LIVE_IMAGE" -- sleep 3600 &
  local run_pid=$!

  # Wait for the agent to answer.
  local i
  for i in $(seq 1 60); do
    msb exec --no-tty "$LIVE_NAME" -- true >/dev/null 2>&1 && break
    sleep 2
  done

  run exec_in sh -c "echo lifecycle-ok > '$LIVE_MARKER' && cat '$LIVE_MARKER'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"lifecycle-ok"* ]]

  # First boot converged the daemon.
  run exec_in docker info
  [ "$status" -eq 0 ]

  run msb stop "$LIVE_NAME"
  [ "$status" -eq 0 ]

  run msb start "$LIVE_NAME"
  [ "$status" -eq 0 ]
  for i in $(seq 1 60); do
    msb exec --no-tty "$LIVE_NAME" -- true >/dev/null 2>&1 && break
    sleep 2
  done

  # The marker - on the rootfs upper layer, not a volume - is still there.
  run exec_in cat "$LIVE_MARKER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"lifecycle-ok"* ]]

  # `msb start` re-ran nothing, so dockerd is down until the launcher's
  # bringup call.
  run exec_in docker info
  [ "$status" -ne 0 ]

  run exec_in agent-bringup
  [ "$status" -eq 0 ]

  run exec_in docker info
  [ "$status" -eq 0 ]

  kill "$run_pid" 2>/dev/null || true
}
