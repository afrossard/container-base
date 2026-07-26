# The isolation substrate is a fifth tier, and docker-heavy agent work is confined by a disposable VM

> **Reasoning superseded by [ADR-0013](./0013-the-agent-runtime-is-a-disposable-per-repo-vm.md).**
> The conclusion below - a disposable VM - still holds, but it is reached from a premise that turned out to be wrong: that the agent runtime is a container on the host with the _host's_ docker socket mounted in.
> Under ADR-0013 the agent runtime is a VM with its own daemon inside it, so what forces the VM is the daemon, not the socket.

Issue #16's survey of community hardening practices reached mechanism 1, the host docker socket that this repo's own `.devcontainer/devcontainer.json` mounts via `docker-outside-of-docker`.
That socket is host-root equivalent: an untrusted action running at the agent's privilege can ask the host daemon to launch `docker run --privileged -v /:/host` and own the host, bypassing every launch-tier control (dropped capabilities, `no-new-privileges`, the egress firewall, the non-root user) at once, because the escape is not "break out of this container" but "start a different, privileged one."

The risk is **irreducible while the container runs directly on the host**.
A socket proxy filters by API endpoint, not request body, so it cannot distinguish an ordinary `docker run` from `docker run --privileged -v /:/host`; and this repo's whole job is building and testing images, so it genuinely needs the `create`/`build`/`start` endpoints a protective proxy would have to block.
No socket-level configuration closes the gap for this workload.

So the fix is not in the socket but in the **substrate**: the host or VM the container launches onto.
ADR-0011's four-tier model - image, launch, dotfiles, org - has no tier that owns this, because a `devcontainer.json` (launch tier) cannot choose the host it runs on; that is the developer's docker context, one level below launch.
The isolation substrate is that fifth tier.

The decision: **docker-heavy agent sessions run inside a disposable micro VM whose only contents are the assigned workspace and docker.**
Under that substrate the mounted socket is the VM's daemon, so an escape reaches only the VM - and because the VM already holds nothing but the workspace and docker, the escape yields exactly what the agent was already granted.
The blast radius collapses to "what you already gave it," which is the principle the whole mechanism serves: the agent's world is default-deny, the code it is assigned and the services it is explicitly given, and nothing else of the host exists.

## Considered options

- **Accept the socket risk and document it** (the research doc's first-pass recommendation). Rejected: it leaves host-root escape live, and it compounds badly with the unattended / auto-mode agent use issue #13 already flags as a distinct risk axis.
- **A socket proxy** (the seed post's Tecnativa `docker-socket-proxy`). Rejected: endpoint-level filtering cannot tell `docker run` from `docker run --privileged -v /:/host`, and this repo needs the very endpoints a protective configuration blocks. It buys the seed author safety only because that author does not need those endpoints.
- **Rootless Docker as the sole fix.** Rejected as insufficient: it demotes the escape from host root to the developer's own uid, but that still exposes the developer's home, SSH keys, and shell rc files - persistence and credential theft, the exact assets mechanism 6 exists to protect. Documented as a weaker fallback, not the recommendation.
- **Sysbox runtime.** Viable and purpose-built - isolated in-container docker with no host socket at all - but Linux-host-only, so it does not cover a macOS dev host. Noted as the Linux-native alternative to a VM.

## Consequences

- **This repo cannot enforce the substrate.** It sits below launch, in the developer's docker context, so this ADR is a recommendation the consumer composes, not something the image or `devcontainer.json` can turn on - consistent with ADR-0011's "the image presumes no threat model."
- **CI needs no change.** GitHub-hosted `ubuntu-latest` runners are already ephemeral, per-job VMs, so the CI path is substrate-confined for free; the recommendation targets the persistent dev host only.
- **The workspace mount must be scoped to the single repo**, not its parent directory or `$HOME`, or "only the code it is assigned" leaks the sibling repos beside it.
- **`docker-outside-of-docker` stays** in `.devcontainer/devcontainer.json`; under a disposable-VM substrate the mounted socket is the VM's, not the host's, which brings it into line with the default-deny principle rather than violating it.
- **On macOS the substrate is nearly free**: the daemon already runs in a VM (Docker Desktop's), so the move is to a dedicated, home-free micro VM (Colima or Lima), not a new layer.
- **In-VM-OS hardening is defence-in-depth, not the boundary.** Dropping capabilities, preventing sudo, seccomp, an in-VM firewall - all harden the VM's disposable interior over the hypervisor that actually contains the agent, and all are reachable by the socket-holding agent anyway (VM-root via `docker run --privileged`). They are worth adding because they are free, but their importance _inverts_ for a non-VM, container-only agent runtime, where the in-OS controls are the only boundary and become primary rather than supplementary.
