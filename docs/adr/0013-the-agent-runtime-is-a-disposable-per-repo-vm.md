# The agent runtime is a disposable per-repo VM, not a hardened container

ADR-0012 concluded that docker-heavy agent work is confined by a disposable VM, reasoning from mechanism 1: a container running directly on the host with the host's docker socket mounted into it.
That reasoning silently assumed the agent runtime _is_ the reference profile devcontainer, hardened - which is not the architecture.

The architecture is two siblings.
A trusted human clones the repo and opens it in the dev container, on Docker Desktop, for reproducibility and nothing else.
When that human wants an autonomous agent with relaxed permissions, they start an **agent runtime**: a virtual machine of its own, one per agent session, holding a clone of one repo and its own docker daemon and nothing else, which the agent cannot leave.
No host docker socket is bridged into it, and nothing outside it talks to the daemon inside it.

The verdict of ADR-0012 survives the change of premise, but the reason is different and worth stating plainly, because it inverts the argument that produced it: **a docker socket is dangerous only when it reaches a daemon that owns more than the agent does.**
Inside the agent runtime it does not, so the socket stops being a threat and goes back to being plumbing.
What forces the VM is no longer the socket but the daemon: the agent needs a docker daemon of its own, and on a macOS dev host a container cannot be given one without `--privileged` (host-root-equivalent) or Sysbox (Linux-only).

## Considered options

- **A hardened container on the host, with the host socket mounted or proxied.** Rejected for the reasons ADR-0012 already gives: endpoint-level filtering cannot distinguish `docker run` from `docker run --privileged -v /:/host`, and this workload needs those endpoints.
- **One container per session inside a single long-lived VM.** Cheap, fast, and launchable from inside the dev container over that VM's socket with no host reach at all - but the agent needs docker, so the session's real boundary is the VM, and concurrent sessions share a blast radius, a filesystem, and a `.git`. Kept as an optimisation to reach for under measured latency pressure, not as the default.
- **Bind-mounting the human's checkout, or a `git worktree` of it, into the VM.** Rejected, and the worktree form is worse than the plain one. A writable shared path is a channel _out_ of the VM that needs no hypervisor escape: the agent writes `.git/hooks/pre-commit` and the human's next commit executes it. From inside a worktree, `git rev-parse --git-common-dir` resolves to the _main_ checkout's `.git`, so a worktree hands over the primary checkout's hooks and config rather than a slice of the repo. Verified by experiment, not assumed.
- **Sysbox.** Still the Linux-native way to get an isolated in-container daemon with no host socket, and still Linux-only, so it does not cover the macOS dev host this repo is developed on.

## Consequences

- **The reusable part is a prebuilt image** (ADR-0014), not a provisioning script and not a persistent data volume. A fresh VM whose first act is to mount the previous session's writable state has paid for isolation and not bought it.
- **The launcher is host-side.** Nothing inside a Linux container can create a macOS VM - the dev container runs inside Docker Desktop's own VM, and Apple's `Virtualization.framework` is a macOS userspace API. `initializeCommand` is the only devcontainer hook documented to run on the host machine, so a devcontainer can manage the runtime at container start but never on demand from inside.
- **The reference profile stops being the vehicle for agent hardening.** ADR-0011's four tiers still hold, but for the agent the launch tier is the agent runtime's own launch (its capability set, its mounts, its network), not `.devcontainer/devcontainer.json`.
- **The workspace enters by clone and leaves as a branch or PR** - provisional, recorded here as the assumption in force rather than as a settled decision.
- **Egress enforcement is deliberately unresolved.** The agent is root inside its own VM and holds the docker socket there, so any in-guest firewall is defence-in-depth; where the real enforcement point lives is an open question, and issue #19's script is defence-in-depth until it is answered.
- **The tool is not chosen yet.** The deciding fact is whether a full docker daemon runs inside the candidate's guest - proven for Lima (it ships a `docker` template), unverified for both OCI-native candidates, `apple/container` and microsandbox, whose per-workload-VM model otherwise fits this ADR exactly. A stated preference for a cross-platform stack weighs against `apple/container`, which is macOS-only by construction. See `docs/research/0021-vm-microvm-isolation-for-agent-runtimes.md` and issue #22.
- **ADR-0012 keeps its conclusion and loses its reasoning.** The socket it treats as the irreducible risk is, under this architecture, a socket the agent already owns everything behind.
