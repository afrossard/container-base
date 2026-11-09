# A failed bring-up never blocks the shell

`agent-bringup` could fail in two opposite ways (issue #225).
When dockerd did not start, `docker-init.sh` gave up silently and still exited 0, so bring-up reported success and dockerd's reason stayed in a log nothing printed.
When any other step failed, `set -e` stopped bring-up there, and on a first boot that also stopped the entrypoint before the operator's command ran.

**Decision: every launch path that reaches a running guest ends in the operator's command, with each failure named.**
`agent-bringup` runs every step regardless of earlier failures, warns about each one, prints dockerd's own log when dockerd is down, ends with a summary of what failed, and exits non-zero.
The entrypoint and the launcher both report that failure and carry on.
Both fall back to the working user's home directory when the workspace clone is missing, because a missing working directory would otherwise fail the handover.

## Considered options

- **Stop bring-up at the first failure.** Rejected: a first boot would then end with no clone, and the shell the operator needs to debug in would be the thing that failed.
- **Keep the entrypoint failing fast, and only finish the remaining steps.** Rejected: the operator would get no shell on the launch that failed, and would have to launch again to reach one.

## Consequences

- The entrypoint's exit status no longer says whether bring-up worked, so a bare `docker run` of the image continues without a docker daemon unless its command needs one. Anything that must know calls `agent-bringup` directly and reads its exit status.
- A guest that never answers `msb exec`, or an `msb start` that fails, still ends the launch: there is no guest to open a shell in.
- The missing-command check in the entrypoint (ADR-0013) still fails fast, because it reports a mistake in the invocation and not a failed step.
