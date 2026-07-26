# VM and microVM isolation for the agent runtime

Research for [issue #21](https://github.com/afrossard/container-base/issues/21), the follow-up to [issue #16](https://github.com/afrossard/container-base/issues/16) and its parent [issue #13](https://github.com/afrossard/container-base/issues/13).

## The architecture this survey assumes

A first pass at this research asked the wrong question, and the wrong question came from [ADR-0012](../adr/0012-the-isolation-substrate-is-a-fifth-tier.md) rather than from the sources.
ADR-0012 reasons from mechanism 1 of the issue #16 survey - a container running on the host with the _host's_ docker socket mounted into it - which silently assumes the agent runtime is this repo's devcontainer, hardened.
Read that way, "choose a substrate" degenerates into "choose which VM the host docker socket belongs to," and the survey ends up ranking candidates by how conveniently they hand a docker socket back to the macOS host.

[ADR-0013](../adr/0013-the-agent-runtime-is-a-disposable-per-repo-vm.md) records the actual architecture, and this document is rewritten against it:

- A human clones the repo and opens it in the **dev container** on Docker Desktop.
  It is a recipe for reproducing a dev environment, not a security boundary.
- To run an autonomous agent, the human starts an **agent runtime**: a VM of its own, one per agent session, holding a clone of one repo and its own docker daemon and nothing else, which the agent cannot leave.
- No host docker socket is bridged into the agent runtime, and nothing outside it talks to the daemon inside it.
- The dev container may offer convenience tooling to launch a runtime, but cannot be the thing that creates it (see "The launch-point constraint" below).

That changes what a good candidate looks like.
The question is no longer "which VM gives my host docker CLI a socket" but **"which tool can create a disposable VM per repo, holding only that repo, running a full Linux guest with docker inside it, with egress controllable from outside the guest."**
A tool whose headline feature is exporting the guest's docker socket back to the host is answering a question this architecture does not ask.

## Sources consulted

Fetched directly in the rewrite pass:

- Apple, [`apple/container`](https://github.com/apple/container) repository README, [`docs/technical-overview.md`](https://github.com/apple/container/blob/main/docs/technical-overview.md), [`docs/container-machine.md`](https://github.com/apple/container/blob/main/docs/container-machine.md), and [`docs/how-to.md`](https://github.com/apple/container/blob/main/docs/how-to.md), via the GitHub contents API.
  This candidate does not appear in issue #21's candidate list at all; it is the closest fit on macOS to the architecture above.
- Colima, [`embedded/defaults/colima.yaml`](https://github.com/abiosoft/colima/blob/main/embedded/defaults/colima.yaml), the project's own annotated default configuration - source of the `$HOME`-writable and `autoActivate` findings below, which contradict the first pass's recommendation.
- Lima, [`templates/default.yaml`](https://github.com/lima-vm/lima/blob/main/templates/default.yaml), the project's own annotated default template - source of the mount and `vmType` defaults.
- Dev Containers specification, [`devcontainerjson-reference.md`](https://github.com/devcontainers/spec/blob/main/docs/specs/devcontainerjson-reference.md) - source of the `initializeCommand` semantics that bound the launch point.
- Local experiment on `git worktree` semantics (see "Why the workspace is a clone, not a mount").
- Local host facts: macOS 26.5.2 (`sw_vers`), Docker Desktop as the active docker context, no Lima or Colima installed.

Carried over from the first pass, all fetched directly then:

- e2b: [`e2b-dev/e2b`](https://github.com/e2b-dev/e2b), the [docs index](https://e2b.dev/docs) and [Sandbox reference](https://e2b.dev/docs/sandbox), [`e2b-dev/infra`](https://github.com/e2b-dev/infra), the first-party blog post ["Firecracker vs QEMU"](https://e2b.dev/blog/firecracker-vs-qemu), and the [Docker template example](https://e2b.dev/docs/template/examples/docker).
  The docs site is partially JS-rendered and `/docs/sandbox/api` returned HTTP 404, so the SDK's exact secret-injection and file-upload mechanisms could not be verified.
- microsandbox: [`superradcompany/microsandbox`](https://github.com/superradcompany/microsandbox) and [docs.microsandbox.dev](https://docs.microsandbox.dev).
- Firecracker: [project site](https://firecracker-microvm.github.io/) and [`getting-started.md`](https://github.com/firecracker-microvm/firecracker/blob/main/docs/getting-started.md).
- Cloud Hypervisor: [the GitHub README](https://github.com/cloud-hypervisor/cloud-hypervisor).
  `cloud-hypervisor.org` could not be reached (DNS failure); the README is the sole source for this candidate.
- Kata Containers: [project site](https://katacontainers.io/), [`README.md`](https://raw.githubusercontent.com/kata-containers/kata-containers/main/README.md), [`docs/hypervisors.md`](https://github.com/kata-containers/kata-containers/blob/main/docs/hypervisors.md).
- Apple Virtualization.framework: **not fetched directly**.
  Both the framework overview and the "Running Linux in a Virtual Machine" article are JS-rendered and returned only a title on repeated attempts; everything attributed to Apple's own docs for the framework itself is search-snippet-derived and flagged as lower confidence, in the same way the 0016 doc flags The Red Guild's 403-blocked posts.
  Note that `apple/container`'s docs, which _were_ fetched directly, cover the same substrate at one level up.
- Docker Inc., [Docker Desktop settings documentation](https://docs.docker.com/desktop/settings-and-maintenance/settings/).
- Lima: [`lima-vm/lima`](https://github.com/lima-vm/lima), [`config/vmtype`](https://lima-vm.io/docs/config/vmtype/), [`config/mount`](https://lima-vm.io/docs/config/mount/).
- Colima: [`abiosoft/colima`](https://github.com/abiosoft/colima) and its [`docs/FAQ.md`](https://github.com/abiosoft/colima/blob/main/docs/FAQ.md).
- gVisor: [project site](https://gvisor.dev/), [Docker user guide](https://gvisor.dev/docs/user_guide/docker/), [networking guide](https://gvisor.dev/docs/user_guide/networking/).
- Sysbox: [`nestybox/sysbox`](https://github.com/nestybox/sysbox).
- `gh issue view 19/20/21 --repo afrossard/container-base`.

Explicitly lower-confidence, search-derived claims, flagged individually where used: Kata's commonly cited 150-300ms boot range (third-party blogs, not Kata's own docs, which state no latency numbers); e2b's "Docker-in-Sandbox nested containerization" framing (comparison pages, not e2b's own docs); nested-virtualization overhead figures from a Spheron Network blog post.

## Two constraints that bound every candidate

### The launch-point constraint

A process inside the dev container cannot create a macOS VM.
The dev container is a Linux container inside Docker Desktop's own VM, and `Virtualization.framework` is a macOS userspace API.
"Launch the agent runtime from the dev container" therefore always means "signal something on the host," never "do it here."

The devcontainer specification has exactly one host-side hook.
`initializeCommand` is documented as running "on the **host machine** during initialization, including during container creation and on subsequent starts"; `onCreateCommand`, `postCreateCommand`, `postStartCommand`, and `postAttachCommand` all run inside the container.
So a devcontainer can reliably manage a host-side VM _at container start_, with no custom plumbing, and cannot do it _on demand_ from inside without granting itself a channel to the host (SSH into macOS, or a bespoke helper daemon) that the dev container has no other reason to hold.

This constraint disappears entirely for the one architecture ADR-0013 rejects as the default: if the disposable unit is a container inside an already-running VM, the dev container just needs that VM's socket.
It is the main practical argument for that option, and it is recorded in ADR-0013 as an optimisation rather than the default.

### Why the workspace is a clone, not a mount

Every candidate below can bind-mount a host directory into the guest.
Doing that for the agent's workspace defeats the boundary without needing an escape.

A writable shared path is a channel _out_ of the VM: the agent writes `.git/hooks/pre-commit`, or a `Makefile` target, or `.vscode/tasks.json`, and the next command the _human_ runs executes it on the host side.
The `git worktree` variant is worse, and this was verified by experiment rather than assumed.
From inside a worktree, `git rev-parse --git-common-dir` resolves to the **main** checkout's `.git`; writing `hooks/pre-commit` there and then committing in the main checkout executes it.
The worktree's `.git` is also a file containing an absolute host path (`gitdir: /.../main/.git/worktrees/<name>`), so a bind-mounted worktree does not even function without also mounting the parent `.git` at a matching path.

Worktrees are still useful - _inside_ the VM, over a clone the VM owns, as the mechanism that makes several sessions on one repo cheap.
That is the concrete benefit that would justify ADR-0013's option C, and the shared `.git` is exactly why C must not span trust levels.

## Candidate catalogue

Ordered by fitness for the architecture above, not by prominence.

### 1. `apple/container` - the closest fit on macOS

**Not in issue #21's candidate list.**
Apple's own tool, 48k stars, actively maintained (last push during this research), Apple silicon only, and supported on macOS 26 (this dev host runs macOS 26.5.2).

**Isolation model.**
Its own technical overview states it "runs a lightweight VM for each container that you create," and names the two properties ADR-0013 needs, in its own words:
"Security: Each container has the isolation properties of a full VM, using a minimal set of core utilities and dynamic libraries to reduce resource utilization and attack surface."
"Privacy: When sharing host data using `container`, you mount only necessary data into each VM. With a shared VM, you need to mount all data that you may ever want to use into the VM, so that it can be mounted selectively into containers."
That second sentence is the "home-free VM holding only the assigned workspace" property, stated as the design's own reason for existing rather than as something an operator must remember to configure.

**Boot cost.**
Its own docs claim "boot times that are comparable to containers running in a shared VM," with memory below a full VM.
No figures given; treated here as a first-party qualitative claim, not a measurement.

**OCI-native, which collapses the publishing problem.**
It consumes and produces standard OCI images, so `docker build` → GHCR → `container run ghcr.io/...` boots this repo's published image directly as a VM guest.
No VM disk-image format, no second pipeline.
This is the technical fact behind [ADR-0014](../adr/0014-the-agent-runtime-is-a-published-image-variant.md).

**Two shapes, and a trap.**
`container run` is the disposable per-container VM - the right shape for an agent runtime.
`container machine` is a persistent Linux environment whose home-mount **defaults to `rw`**, mapping the Mac `$HOME` into the guest ("Your repo lives in `$HOME` on macOS and is mounted at `/Users/<username>` inside the container machine").
It is settable to `ro` or `none`, but the ergonomic path mounts your home, exactly as Colima's does.

**Controls available at launch.**
`--cap-add` / `--cap-drop`, per-container `--network`, DNS control (`--dns`, `container system dns create`), and CPU/memory limits, all per its own command reference.
Nested virtualization exists but is gated (`--virtualization`, Apple silicon M3+, and a custom kernel with `CONFIG_KVM=y`, since "the default kernel does not support this") - not needed for a docker daemon, but a useful signal about what the default guest kernel is not built for.

**Docker-in-guest: unverified, and this is the deciding fact.**
Nothing in the README, technical overview, how-to, or command reference mentions running `dockerd` inside a guest.
The guest runs a minimal init, and `container build` runs BuildKit in a _separate_ utility VM on the host side rather than inside your container.
Whether a full docker daemon runs inside a `container run` guest is the single fact that decides this candidate, and it needs an experiment (below), not more reading.

**Egress.**
Container networking goes through Apple's `vmnet` framework with per-container network attachment and host-side DNS control.
No allow/deny policy engine is documented; enforcement would be host-side, as with every other candidate here.

### 2. microsandbox - the same bet as `apple/container`, with different backing

**Isolation model.**
Its own README claims "Hardware-level isolation with microVM technology" via `libkrun`, and its acknowledgements name `libkrun` (which lives under the `containers` org, alongside Podman) and `smoltcp` as the projects that made it possible.
Boot time: "Average boot times under 100 milliseconds," first-party, caveated in its own docs as "guest boot on an M1 machine," with no third-party reproduction found.

**Host-OS support: the broadest surveyed.**
macOS (Apple silicon), Linux (KVM enabled), and Windows (Windows Hypervisor Platform), per its own README.
It is the only candidate that could cover both the macOS dev host and a self-hosted Linux CI runner with one tool.

**OCI-native, the same model as `apple/container`.**
"Runs standard container images from Docker Hub, GHCR, or any OCI registry," with "Docker-Like Workflows: Familiar image, command, shell, and volume workflows."

**Docker-in-guest: unverified - the identical unknown.**
Its README mentions no docker daemon inside a guest.
The first pass rejected microsandbox on the grounds that "run an OCI image" is not "run a Linux guest with a docker daemon," while treating that same model as the argument _for_ `apple/container`; that reasoning is withdrawn, because it disqualifies both candidates or neither.
The question is open for both, and answering it is what issue #22 exists for.

**Egress: the strongest documented match in this survey.**
Its own docs state "All sandbox traffic flows through a host-side network stack," letting an operator "allow public internet access, block private networks, publish ports, deny by default, pin DNS behavior, or inspect TLS traffic without relying on guest cooperation."
The mechanism behind that claim is `smoltcp`, a userspace TCP/IP stack running in the VMM, so the guest has no host route at all and enforcement sits outside it structurally rather than by rule.
That is the same fail-closed shape this document otherwise recommends assembling by hand.

**Secrets.**
"Instead of putting real credentials inside the VM, microsandbox injects placeholders and swaps them for real values only when traffic goes to an allowed host," so the guest - and anything that reaches guest-root - never holds the real value.

**The real reservation, stated plainly.**
Not workload model: scale and backing.
7,024 stars against `apple/container`'s 48,287, one wrapper vendor rather than Apple, and no third-party-verified performance or security track record found.
It is actively developed (last push during this research), and its load-bearing dependencies are not single-vendor.
This is a judgement about who maintains the thing, not about whether it fits - on the two questions this document leaves open, it fits better than anything else surveyed.

### 3. Lima - the proven control

**Isolation model.**
A hypervisor inherited from its backend: Apple's Virtualization.framework (`vz`) or QEMU.
Lima's own `vmtype` docs state `vz` became the default on macOS 13.5+ for new instances as of Lima v1.0, and its own decision guidance routes macOS hosts to `vz` and Linux hosts to QEMU.
`vmType` cannot be changed after an instance is created.

**Docker-in-guest: proven.**
Lima ships a `template://docker`.
The guest is a full Linux kernel under a hypervisor, so `docker build` and `docker run` behave exactly as on any Linux docker install, with no nesting.
This is the reason Lima is the fallback rather than the also-ran: it is the candidate where the deciding fact is already known.

**Mounts.**
Lima's own default template comments state the builtin default is `[]` (mount nothing), with the shipped file mounting "the home as read-only" via its `base` mechanism.
Read-only is better than Colima's default and still not what ADR-0013 wants; an agent-runtime instance should declare `mounts: []` explicitly rather than inherit a template.
Mount type under `vz` on macOS is virtiofs; 9p under QEMU; reverse-sshfs as a portable third option that opens no host TCP port.

**Cost for this architecture.**
Instances are heavier to create than a per-container VM, and a per-session instance means per-session provisioning unless the image work of ADR-0014 is reproduced as a Lima disk image or a fast provisioning path.
This is the concrete price of the fallback.

**Egress.**
Inherits the backend's networking (the `vz` NAT device's host-routed egress, or QEMU's user-mode networking).
Lima layers no allow/deny policy of its own.

### 4. Colima - explicitly not recommended

Colima is a thin wrapper over Lima ("Colima means Containers on Lima"), and the first pass recommended it.
That recommendation is withdrawn, on two of Colima's own documented defaults plus one architectural mismatch.

**Its default config mounts your home, writable.**
Colima's own annotated default configuration says, verbatim: "Colima mounts user's home directory by default to provide a familiar user experience," and "Colima default behaviour: `$HOME` is mounted as writable."
That is the direct opposite of the property ADR-0012 and ADR-0013 lean on, and it is the default rather than an opt-in.

**It takes over the host docker context by default.**
`autoActivate: true`, per the same file: on startup it "sets as active Docker context (for Docker runtime)."
It also writes an SSH config entry for the VM by default (`sshConfig: true`).

**Its selling point is a non-goal here.**
Colima exists to give the macOS host a docker socket and context with zero setup - which is what the first pass valued, because it read the architecture as "swap the socket the devcontainer's `docker-outside-of-docker` points at."
Under ADR-0013 nothing outside the agent runtime should be talking to the daemon inside it, so the feature that made Colima the recommendation is a feature this design does not want.

None of this makes Colima a bad tool.
It makes it the wrong tool for an agent runtime, and a perfectly reasonable one for a human's docker host.

### 5. e2b - wrong shape, and not local on macOS

Firecracker microVMs, per e2b's own blog ("Firecracker to run AI generated code securely in the cloud") and its infra repo's own topics.
Firecracker's numbers as e2b cites them: boot "as little as 125ms," "less than 5MB RAM overhead."

Self-hosting targets are "GCP," "AWS (Beta)," and "General linux machine"; macOS does not appear, and the KVM dependency makes that structural.
On macOS it is usable only as a client of e2b's hosted service, which is not a local substrate.

Docker-in-guest is confirmed but modest: e2b's own Docker template installs Docker inside an Ubuntu sandbox via `get.docker.com` and runs `sudo docker` against pre-built images (`alpine`, `busybox`), with a stated recommendation of "at least 2 CPUs and 2 GB of RAM"; the page does not demonstrate `docker build`.
Sandboxes are bounded to 24 hours (Pro) or 1 hour (Base).
The "nested containerization" framing in third-party comparison pages is not corroborated by e2b's own docs and is flagged as the weaker characterization.

### 6. Firecracker and Cloud Hypervisor - substrate layers, not candidates

Firecracker is the reference microVM implementation: KVM-based, jailer-isolated, "as little as 125 ms" startup, "up to 150 microVMs per second per host," "less than 5 MiB" overhead per microVM, per its own docs.
Linux and hardware-virtualization only; no macOS.
It has no opinion on docker-in-guest - `firecracker-containerd` is its own named integration point.

Cloud Hypervisor is a Rust VMM on KVM or Microsoft Hypervisor, targeting "64-bit Linux and Windows 10/Windows Server 2019," with design goals of "Low latency" and "Low memory footprint" and no published figures.
Its README distinguishes itself from Firecracker by scope, not disagreement: a "general purpose VMM for Cloud Workloads and not limited to container/serverless or client workloads," sharing code through the Rust VMM initiative.
Its own documentation site could not be reached during this research (DNS failure), so the README is the sole source.

Both are evaluated here as the layer _under_ other candidates, and neither is usable on the macOS dev host.

### 7. Kata Containers - the self-hosted-CI answer

True hypervisor isolation behind an OCI/CRI runtime shim, with a choice of QEMU, Cloud Hypervisor, Firecracker, or the project's own Dragonball VMM (confirmed in `docs/hypervisors.md`).
Because it presents as a `containerd` shimv2 runtime, `docker run --runtime=kata-runtime ...` transparently yields a VM-backed container and normal docker build/run semantics survive - which is exactly the property a CI runner wants.

Linux only: `docs/hypervisors.md` lists x86_64/amd64, aarch64, ppc64le, s390x, and no macOS appears in any of the three Kata sources fetched.
Kata's own docs state no latency figures at all; the commonly cited 150-300ms range and the "Kata+Firecracker ~125-200ms vs Kata+QEMU ~500ms" comparison come from third-party blogs and are reported here as unverified.
Kata's own stated tradeoff among its hypervisors is feature coverage, not speed: "QEMU is the best supported hypervisor for NVIDIA-based GPUs and for confidential computing use-cases (such as Intel TDX and AMD SEV-SNP)."

### 8. gVisor and Sysbox - defence-in-depth, by their own maintainers' description

Included for the honest comparison issue #21 asked for, and both fail the boundary test for the same underlying reason.

gVisor is a user-space kernel (the "Sentry") "intercepting all sandboxed application system calls to the kernel," which "protects the host from the application"; its own marketing says "VM-like" rather than claiming to be a VM.
It has the strongest documented docker-in-guest story of anything surveyed - `docker run --runtime=runsc` as a drop-in, plus a first-party "Docker in gVisor" tutorial - and a real out-of-sandbox egress control (a Token Bucket Filter, `--qdisc-tbf-rate` / `--qdisc-tbf-burst`, settable per sandbox via OCI annotations).
The load-bearing caveat: that enforcement point runs on the same kernel as the host, so a Sentry bug reaches the host directly, whereas a VM escape still has to cross a hypervisor.

Sysbox is explicit in its own docs: "Sysbox does not use hardware virtualization... [it is] a pure OS-virtualization technology."
Its headline use case targets this repo's mechanism-1 problem head-on - "Securing CI/CD pipelines by enabling Docker-in-Docker (DinD)... without insecure privileged containers or host Docker socket mounts" - which is precisely why ADR-0012 flagged it as the Linux-native alternative to a VM.
Its own maintainers also state the argument against it for this threat model: Sysbox containers provide "weaker isolation than VMs (by sharing the Linux kernel among containers)," and "vulnerabilities have recently been found in the Linux kernel that in some cases reduce or negate the enhanced isolation provided by Sysbox containers."

Both are Linux-only, so neither is available on the macOS dev host in any case.
Either is worth layering _inside_ a VM-backed runtime for the same reason `cap_drop` is: cheap and additive.

## The deciding experiment - resolved

**Update: the experiment ran. See `docs/research/0022-vm-tool-experiment-results.md` for the full results; this section is left as it was written, as the record of what the experiment set out to answer.**

The short version: a full docker daemon runs inside the guest for all three candidates, so the recommendation below is superseded by an unconditional one in 0022, not by the conditional form still written here.

**Does a full docker daemon run inside an `apple/container` guest?**

Everything else about the macOS choice is close enough to be preference; this is not.
It is unverified for `apple/container` and proven for Lima, and it needs running rather than reading, because the answer is not in Apple's docs either way.
Installing `container` needs an admin-password installer, so it is a human-triggered step.

Three arms, one test, tracked as [issue #22](https://github.com/afrossard/container-base/issues/22):

- **`apple/container`**, using `container run` rather than `container machine`.
- **microsandbox** (`msb`), which additionally exercises the host-side egress stack and the placeholder-secret mechanism, since both bear on questions this document leaves open.
- **Lima** with `vmType: vz` and an explicit `mounts: []`, as the control - docker-in-guest is already proven there, so its value is a cold-start baseline.

Shape of the test:

1. Build a guest image carrying dockerd and an init or supervisor - the `-agent` variant ADR-0014 describes, in draft form.
2. Boot it under each arm, with whatever capability set turns out to be required, and inside the guest: start dockerd, then `docker build` a trivial image and `docker run` it.
3. If that passes, run this repo's real image build inside the guest.
4. Record which of the following actually bite: cgroup v2 availability under the default guest kernel, which storage driver docker settles on (an overlayfs-to-vfs fallback is a pass that is not really a pass), iptables/nftables for docker's own bridge networking, and whether the guest init tolerates a supervised daemon.
5. Record cold start and default mounts by observation rather than from docs, for every arm.

A clean pass on either OCI-native arm makes that arm the recommendation.
A failure not fixable from inside the image demotes that arm to a watch item, with its OCI-native argument waiting for whenever guest support broadens, and Lima takes the recommendation by default.

## Recommendation - superseded

**This section's conditional form ("adopt whichever candidate survives the experiment") is superseded by the unconditional recommendation in `docs/research/0022-vm-tool-experiment-results.md`: adopt microsandbox, launched with a disk-backed named volume mounted at `/var/lib/docker`, with `apple/container` as the documented fallback and Lima as the last resort.** The text below is left as originally written, as the reasoning that was available before the experiment ran.

### macOS dev host

**Adopt whichever OCI-native candidate survives the experiment - `apple/container` or microsandbox - and fall back to Lima with `vmType: vz` and an explicit `mounts: []` if neither does.**

Both OCI-native candidates have the property ADR-0013 asks for and Lima does not: their native unit _is_ a per-workload VM booted from an OCI image, so the published `-agent` image is the guest and ADR-0014 costs nothing extra.
They differ on which risk you would rather carry.
`apple/container` is Apple-maintained on Apple's own virtualization and networking frameworks, at roughly seven times the community size.
microsandbox is the smaller bet, and the only candidate in this survey with first-party answers to the egress and secret-injection questions - which are precisely the questions this document defers, so a pass there resolves more than tool choice.

If the experiment is a tie on docker-in-guest, the tiebreak is not performance.
Prefer `apple/container` for maintenance risk; prefer microsandbox if the host-side egress mechanism proves out, because that converts a deferred design problem into a solved one, or if one tool across platforms is worth more than that maintenance risk.

**Portability is a stated preference and cuts against `apple/container`.**
It is macOS-and-Apple-silicon only by construction - it is Apple's framework - so adopting it means running a _different_ tool wherever the agent runtime is wanted on Linux or Windows, and maintaining two launch paths, two guest-image assumptions, and two sets of egress plumbing.
microsandbox is the only candidate documenting all three host platforms (macOS on Apple silicon, Linux with KVM, Windows with the Windows Hypervisor Platform).
Lima documents macOS, Linux, and NetBSD, with experimental Windows support via WSL2 passthrough, so the fallback is portable too.
This does not disqualify `apple/container` - a macOS-only tool that works beats a portable one that does not - but it means a tie on the experiment should break against it, and a marginal win for it should be weighed against owning a second stack.

The case for Lima as the fallback is narrower and sturdier: docker-in-guest is proven, `vz` is the documented default on macOS 13.5+, and `mounts: []` gets the home-free property by declaration.
The price is per-session provisioning cost, since a Lima instance is not booted from an OCI image.

**Colima is not recommended**, reversing the first pass.
Its own default configuration mounts `$HOME` writable and takes over the host docker context, and the convenience it is built around - a docker socket on the macOS host - is a non-goal under ADR-0013.

**Egress remains this repo's own work**, on any of these.
None of `apple/container`, Lima, or Virtualization.framework ships an allow/deny policy engine (per each project's own docs; none found).
The open question is _where_ the enforcement point goes, and it is deliberately not answered here - see below.

### Linux CI

**No substrate change for GitHub-hosted runners**, unchanged from ADR-0012's finding: `ubuntu-latest` jobs already run in ephemeral, per-job VMs, so the CI path is substrate-confined for free.
Nothing in this research revises that.

**If self-hosted Linux runners are ever introduced**, Kata Containers with the Firecracker backend is the recommendation: true hypervisor isolation, a transparent `containerd` shimv2 drop-in so `docker build` / `docker run` need no workflow change, Linux-native, and it composes with whatever orchestrates the runner.
Raw Firecracker or Cloud Hypervisor are the leaner alternative if Kata's orchestration is unwanted, at the cost of owning VM lifecycle and the OCI translation.
gVisor and Sysbox are reasonable _additional_ layers inside such a job and must not be the only isolation, for the reasons their own maintainers give.

## Open questions

- **Where egress is enforced.** The agent is root inside its own VM and holds the docker socket there, so an in-guest firewall is defence-in-depth by construction. The candidates are host packet-filter rules against the VM's interface (true boundary, but IP-based against CDN-fronted allowlists), or a host-side proxy with a hostname allowlist and no default route in the guest (fail-closed, hostname-expressible, at the cost of every client in the guest having to honour a proxy). Deliberately deferred.
- **Whether Claude Code consumes Workload Identity Federation.** Anthropic's own CLI/SDK auth guidance names WIF as the path for "CI, servers, containers," and states Claude Code honours the same credential-profile resolution as the SDKs, but does not say in so many words that Claude Code reads the WIF environment variables. That matters because WIF is the difference between a short-lived federated token in the guest and a long-lived account credential.
- **Whether the agent runtime image stays in this repo.** ADR-0014's argument is that it is an image, and images are what this repo publishes. If the runtime accumulates parts that are not image-shaped - a host-side launcher, an egress proxy configuration - that argument weakens.
- **Workspace supply is provisional.** Clone-in-VM with output as a branch or PR is the assumption in force; it has not been chosen against the alternatives with the same weight as the decisions in ADR-0013.
- **How much a single cross-platform tool is worth.** The dev host is macOS today, but the preference is to keep the stack portable. That is a real weight against `apple/container`, which cannot be portable, and it is not yet quantified: if the agent runtime never needs to run anywhere but this laptop and GitHub-hosted CI, the cost of a macOS-only tool is zero.

## Relationship to #19 and #20

**Issue #19** ships an inert, default-deny egress firewall script.
Under this architecture that script runs _inside_ the agent runtime, where the agent can flush it, so it is defence-in-depth rather than the enforcement point - worth shipping for the same reason `cap_drop` is, and not a substitute for answering the egress question above.

**Issue #20** turns `.devcontainer/devcontainer.json` into the reference profile.
This research changes what that means: the reference profile is the _human's_ dev container, and per ADR-0013 it is a reproducibility recipe rather than the vehicle for agent hardening.
`docker-outside-of-docker` in that profile keeps pointing at Docker Desktop, and the agent runtime is a separate artifact (ADR-0014) launched host-side rather than a hardened variant of that profile.
