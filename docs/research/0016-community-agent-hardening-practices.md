# Community agent-hardening practices beyond Anthropic's reference devcontainer

Research for [issue #16](https://github.com/afrossard/container-base/issues/16), which is the follow-up to [issue #13](https://github.com/afrossard/container-base/issues/13).
Issue #13 weighed this repo's dev image against a single threat model: Anthropic's own reference devcontainer for Claude Code.
That comparison produced [ADR-0011](../adr/0011-agent-hardening-is-composed-at-launch-time.md), which settled on a four-tier home for any hardening mechanism: **image** (this repo's Containerfile), **launch** (the consumer's devcontainer.json / `docker run` / compose / k8s securityContext), **dotfiles** (personal, chezmoi-applied), and **org policy** (a separate repo).

Issue #16 asks a narrower question: Anthropic's reference is one community voice among several, and other engineers hardening coding agents in containers have identified categories that reference omits.
This document surveys those other primary sources - vendor docs, standards bodies, and independently published hardening writeups - and maps each mechanism they raise onto the same four-tier model, calling out where sources disagree with each other or with Anthropic's reference (which issue #13 already documents in detail and is only referenced here, not re-derived).

## Sources consulted

- **Seed source**: Daniel Demmel, ["Coding agents in secured VS Code dev containers"](https://www.danieldemmel.me/blog/coding-agents-in-secured-vscode-dev-containers) ([raw source](https://raw.githubusercontent.com/daaain/danieldemmel.me-next/main/data/blog/coding-agents-in-secured-vscode-dev-containers.mdx)), a single practitioner's own hardened devcontainer for running Claude Code and similar agents. Treated as primary because it documents the author's own configuration and reasoning, not a summary of someone else's.
- Michael, The Red Guild, ["Leveraging VSCode internals to escape containers"](https://blog.theredguild.org/leveraging-vscode-internals-to-escape-containers/) (Nov 2025) and ["Where do you run your code? part II - devcontainer security"](https://blog.theredguild.org/where-do-you-run-your-code-part-ii-2/). **Could not be fetched directly** - the site returns HTTP 403 to automated fetches. Everything attributed to these posts below comes from search-engine-extracted snippets, not a verified full-text read, and is flagged as lower-confidence accordingly.
- OWASP, [Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html) - a maintained community standard, fetched directly.
- Docker Inc., official CLI reference: [`docker container run`](https://docs.docker.com/reference/cli/docker/container/run/), fetched directly.
- Linux kernel documentation, [`no_new_privs`](https://www.kernel.org/doc/html/latest/userspace-api/no_new_privs.html) - the kernel mechanism Docker's `no-new-privileges` flag wraps, fetched directly.
- The Dev Container Spec maintainers, [`devcontainer.json` reference](https://containers.dev/implementors/json_reference/), fetched directly.
- The `devcontainers/features` repository, [`docker-outside-of-docker` feature README](https://github.com/devcontainers/features/tree/main/src/docker-outside-of-docker) and [`common-utils` feature README](https://github.com/devcontainers/features/tree/main/src/common-utils) - these are the exact upstream features this repo's own devcontainers consume, fetched directly.
- GitHub, [Security in GitHub Codespaces](https://docs.github.com/en/codespaces/reference/security-in-github-codespaces) - a first-party vendor doc for a comparable managed devcontainer product, fetched directly.
- Microsoft, [`vscode-remote-release` issue #6608, "Document the security model of VSCode Remote Development"](https://github.com/microsoft/vscode-remote-release/issues/6608) - open since April 2022, still open as of this research, 22 comments, no published resolution. Confirmed via `gh api`.
- OpenAI, Codex documentation: [security](https://learn.chatgpt.com/docs/security) and [sandboxing](https://learn.chatgpt.com/docs/sandboxing), fetched directly.
- Cursor, [Implementing a secure sandbox for local agents](https://cursor.com/blog/agent-sandboxing), fetched directly.
- Anthropic, the reference devcontainer's own [`Dockerfile`](https://github.com/anthropics/claude-code/blob/main/.devcontainer/Dockerfile) and [`devcontainer.json`](https://github.com/anthropics/claude-code/blob/main/.devcontainer/devcontainer.json), fetched directly to get exact wording where issue #13 only described them.

## Mechanism catalogue

### 1. Docker socket mounting (`docker-outside-of-docker`)

**What it is.** Mounting the host's `/var/run/docker.sock` into a container, or using a devcontainer feature that does so on your behalf, gives that container's process the ability to talk to the host's Docker daemon directly.
The daemon runs as root on the host, so anything that can reach the socket can ask it to start a new container with arbitrary bind mounts and `--privileged`, which is a full host root shell.

**Tier: launch.** The socket is supplied by whichever `runArgs`, feature, or compose file wires it in; the base image installs nothing docker-related.
This repo's shared image (`images/dev/Containerfile`, driven by `images/dev/devcontainer.json`) does not install a Docker CLI, mount a socket, or reference `docker-outside-of-docker` anywhere; only this repo's own consumer profile, `.devcontainer/devcontainer.json`, adds the feature.
That placement is already correct under ADR-0011; the open question issue #16 raises is whether the launch-tier profile should use it at all.

**Sources.**

- OWASP's cheat sheet states plainly: "Do not expose `/var/run/docker.sock` to other containers" and that even a read-only mount "only makes it harder to exploit," not safe (<https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html>).
- The seed post treats direct socket access as a critical risk and instead runs a Tecnativa `docker-socket-proxy` in front of it, allowlisting only read-only endpoints (`CONTAINERS`, `IMAGES`, `INFO`, `NETWORKS`, `VOLUMES`) and blocking the dangerous ones (`POST`, `BUILD`, `COMMIT`, `EXEC`, `SWARM`), trading away the ability to build or exec into sibling containers in exchange for closing the escape (<https://www.danieldemmel.me/blog/coding-agents-in-secured-vscode-dev-containers>).
- The `docker-outside-of-docker` feature's own README - the exact upstream this repo consumes - documents what the feature does ("re-use the host docker socket, adding the Docker CLI to a container") but **does not mention the privilege implication of that reuse anywhere in its own documentation** (<https://github.com/devcontainers/features/tree/main/src/docker-outside-of-docker>). This is a real gap, not an oversight in this survey: the primary source this repo's own devcontainer directly depends on is silent on the risk issue #16 raises.

**Disagreement.** Anthropic's reference devcontainer does not use `docker-outside-of-docker`, `docker-in-docker`, or any docker socket mechanism at all - its Dockerfile and `devcontainer.json` contain no docker-related configuration, because the reference agent workflow never needs to run nested containers (confirmed by direct fetch of both files).
Issue #13's own comment thread ruled `docker-in-docker` out of scope because it needs `--privileged`, but that thread evaluated `docker-outside-of-docker` only against that alternative, never against "no docker access at all," which is what both Anthropic's reference and (implicitly, via the socket-proxy workaround) the seed post choose.
Compared side by side: Anthropic avoids the tradeoff entirely (no docker need), the seed author needs limited docker visibility and pays for it with a locked-down proxy, and this repo's own consumer devcontainer grants full, unproxied host-socket access - the widest exposure of the three, for a repo whose entire purpose is building and testing container images and therefore has a stronger, more central need for docker access than either comparison source.
That widest-exposure framing describes the status quo only; the recommendation below resolves it at the substrate tier rather than the socket tier (ADR-0012).

### 2. Sudo and passwordless privilege escalation

**What it is.** A non-root container user with unrestricted, passwordless `sudo` access can trivially become root inside the container, undermining whatever protection running as non-root was meant to buy.

**Tier: image**, for whether sudo exists and how it's configured at all (baked into the filesystem at build time); the actual _neutralization_ of the escalation, however, is a **launch**-tier control (see disagreement below).

**Sources.**

- The seed post calls unrestricted sudo access mandatory to remove: "A non-root user with sudo access can escalate to root and bypass container restrictions," and verifies its absence with `sudo -l` returning "command not found" (<https://www.danieldemmel.me/blog/coding-agents-in-secured-vscode-dev-containers>).
- OWASP's cheat sheet does not address sudo-in-container specifically at all (confirmed by direct fetch - no sudo section exists). Its privilege-escalation guidance is expressed entirely in terms of unprivileged users, dropped capabilities, and `no-new-privileges`, not sudo removal. This means the "remove sudo outright" recommendation currently has exactly one primary source behind it (the seed post); no second primary source in this survey independently corroborates sudo-removal as the fix, so it is reported here as one author's stance, not community consensus.
- Docker's own CLI reference states what `no-new-privileges` actually does: "Disable container processes from gaining new privileges," explicitly naming that this "prevents commands like `su` or `sudo` from working" (<https://docs.docker.com/reference/cli/docker/container/run/>).
- The Linux kernel's own documentation for the underlying `no_new_privs` mechanism confirms why: with the bit set, "setuid and setgid bits [are prevented] from changing uid or gid," which is exactly the mechanism `sudo`'s setuid-root binary relies on (<https://www.kernel.org/doc/html/latest/userspace-api/no_new_privs.html>).

**Disagreement, and a source Anthropic's reference itself demonstrates.** Anthropic's reference devcontainer does ship sudo, but scoped to a single command, not blanket: its Dockerfile grants `node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh` and nothing else (confirmed by direct fetch of the Dockerfile) - the `node` user cannot run arbitrary commands as root, only that one firewall script.
This repo's image instead inherits **blanket** `NOPASSWD: ALL` sudo for the `vscode` user, and this is not a decision this repo made: it is the unconfigurable default behavior of the upstream `ghcr.io/devcontainers/features/common-utils:2` feature this repo's own `images/dev/devcontainer.json` consumes.
That feature's own options table (confirmed by direct fetch) offers no sudo-scoping option at all - `installZsh`, `configureZshAsDefaultShell`, `installOhMyZsh`, `installOhMyZshConfig`, `upgradePackages`, `username`, `userUid`, `userGid`, `nonFreePackages`, and nothing sudo-related.
So there are three positions among the sources surveyed, not two: remove sudo entirely (seed post), scope it to exactly what's needed (Anthropic's reference), or accept the upstream feature's blanket default (this repo, currently, by omission rather than by decision).

### 3. VS Code IPC sockets and host-access environment variables

**What it is.** VS Code's remote/container development model creates Unix sockets under `/tmp` (`vscode-ipc-*.sock`, `vscode-git-*.sock`, and related names) and injects environment variables (`VSCODE_IPC_HOOK_CLI`, `GIT_ASKPASS`, `BROWSER`, `SSH_AUTH_SOCK`) that let processes inside the container reach back out to the host: opening a browser tab, using host git credentials, or in the worst case executing commands on the host through the IPC protocol.

**Tier: launch and dotfiles**, split. The seed post's own three-layer mitigation shows the split cleanly: clearing `remoteEnv` in `devcontainer.json` is launch-tier; a shell-startup script that unsets the variables VS Code re-injects anyway, sourced ahead of the interactive-shell guard because agents invoke non-interactive login shells, is more of a dotfiles/shell-init concern; and a `postStartCommand`/background-loop socket-deletion pass is again launch-tier (it lives in the devcontainer/compose lifecycle, not personal shell config).

**Sources.**

- The seed post is the fullest treatment found: it names the specific sockets and variables, and states its central finding - clearing `remoteEnv` alone is not sufficient because "VS Code re-injects its own variables ... when spawning new processes" - which is why it adds the second and third layers (<https://www.danieldemmel.me/blog/coding-agents-in-secured-vscode-dev-containers>).
- The Red Guild's "Leveraging VSCode internals to escape containers" independently names the same core mechanism - a window during which an attacker could connect directly to `vscode-ipc-*.sock` using VS Code's internal IPC protocol - and separately notes that Microsoft's own Remote-SSH extension security README warns "a compromised remote could use the VS Code Remote connection to execute code on your local machine." **This is reported with reduced confidence**: the post itself returned HTTP 403 to direct fetch, so this description is reconstructed from search-result text, not a verified read of the source.
- **First-party confirmation of the underlying gap, verified directly**: `microsoft/vscode-remote-release` issue #6608, "Document the security model of VSCode Remote Development," opened April 2022, asks Microsoft directly whether a fully-attacker-controlled remote server can run arbitrary code on the local machine via this mechanism. Verified via `gh api` as still **open**, with 22 comments and no published resolution as of this research. This corroborates, from Microsoft's own issue tracker rather than a third party's interpretation, that no official security model for this mechanism has been published.

**Disagreement.** None found between sources on whether this is a real risk - The Red Guild, the seed post, and the unresolved Microsoft issue all agree it exists and is unresolved.
The disagreement, such as it is, is with the underlying tool's design intent rather than between hardening authors: the seed post states outright that "VS Code dev containers are designed to be convenient, not secure. They actively work against you by injecting various - otherwise helpful - features that happen to be security holes."
This repo's own `.devcontainer/devcontainer.json` does not currently clear `remoteEnv` or run a socket-cleanup pass; it is unmitigated on this mechanism today.

### 4. `cap_drop: [ALL]` and `no-new-privileges: true`

**What it is.** Dropping every Linux capability the container is granted by default (Docker grants ~14 by default: `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `FSETID`, `KILL`, `MKNOD`, `NET_BIND_SERVICE`, `NET_RAW`, `SETFCAP`, `SETGID`, `SETPCAP`, `SETUID`, `SYS_CHROOT`, `AUDIT_WRITE`), then adding back only what's actually needed, combined with `no-new-privileges` to block escalation through setuid/setgid binaries or file capabilities at `execve()` time.

**Tier: launch.** Both are `docker run` flags / compose `security_opt` / devcontainer `runArgs` entries; nothing about them can be baked into an image.

**Sources.**

- OWASP: "The most secure setup is to drop all capabilities `--cap-drop all` and then add only required ones," and "Always run your docker images with `--security-opt=no-new-privileges`" (<https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html>).
- Docker's own CLI reference documents both flags directly, including that `--privileged` is the flag that "enables all Linux kernel capabilities," which `cap_drop: [ALL]` is the direct inverse of (<https://docs.docker.com/reference/cli/docker/container/run/>).
- The seed post uses exactly this pair in its own `docker-compose.yml`, reasoning that "the container only runs Node.js, git, and bash - none of which need special capabilities at runtime," and verifies the result with `grep 'CapEff' /proc/self/status` and `grep 'NoNewPrivs' /proc/self/status` (<https://www.danieldemmel.me/blog/coding-agents-in-secured-vscode-dev-containers>).
- The Dev Container Spec itself exposes the equivalent knobs (`capAdd`, `securityOpt`, `runArgs`) as first-class, cross-orchestrator `devcontainer.json` properties, confirming this is spec-supported, not a compose-only workaround (<https://containers.dev/implementors/json_reference/>).

**Interaction worth flagging explicitly, since it is the one place this mechanism collides with another in this catalogue**: an egress firewall built on `iptables`/`ipset` (mechanism 5, and Anthropic's `init-firewall.sh`) needs `NET_ADMIN` and `NET_RAW` re-added after a blanket `cap_drop: [ALL]`, which the OWASP and Docker sources' generic "drop everything, add back only what's needed" phrasing doesn't call out but which Anthropic's reference devcontainer's own `runArgs` (`--cap-add=NET_ADMIN --cap-add=NET_RAW`, confirmed by direct fetch) makes concrete.

**Disagreement.** None on the mechanism itself - every source that addresses it recommends the same drop-then-add-back pattern.
This repo's `.devcontainer/devcontainer.json` currently sets neither flag.

### 5. Network egress control

**What it is.** Whether the container's outbound network access is restricted (a default-deny firewall allowlisting only needed domains, Anthropic's approach) or left open (accepted risk, monitored rather than blocked).

**Tier: launch**, per ADR-0011 (already established; not re-derived here).

**Sources and the live disagreement issue #16 named.**

- Anthropic's reference devcontainer makes the firewall central: `init-firewall.sh`, `NET_ADMIN`/`NET_RAW`, default-deny, allowlist - already documented in issue #13, referenced not repeated here.
- The seed post takes the opposite position explicitly: "Development requires internet access," so egress isn't blocked; the stated mitigation is that "network egress could be monitored," not prevented (<https://www.danieldemmel.me/blog/coding-agents-in-secured-vscode-dev-containers>).
- No third primary source in this survey stakes out a position on egress control specifically (OWASP's cheat sheet, the Dev Container spec, and the devcontainers features surveyed are all silent on network egress policy). This is reported as a genuine two-source disagreement, not padded with a manufactured majority.

### 6. Credential and secrets handling (SSH keys, git push, host credential mounts)

**What it is.** Whether host secrets (`~/.ssh`, cloud credential files, long-lived tokens) are bind-mounted or otherwise made reachable from inside the agent's container, and what that lets a compromised or misbehaving agent do (most concretely: push to a remote and establish persistence, or exfiltrate a long-lived credential).

**Tier: launch and dotfiles**, split by mechanism. Not bind-mounting `~/.ssh` is a launch-tier decision (what `mounts`/`runArgs` do or don't do). Managing an isolated, repo-scoped credential file instead is closer to a dotfiles/per-developer concern, though it can also be composed at launch via a scoped mount.

**Sources.**

- The seed post is explicit: not mounting `~/.ssh` is deliberate, "malicious code could (force-)push itself to a remote repository, establishing persistence," and instead keeps an isolated credential file "in a gitignored directory on the host" mounted only to the specific path the CLI tool reads, e.g. `.claude-docker/.claude.json:/home/vscode/.claude.json` (<https://www.danieldemmel.me/blog/coding-agents-in-secured-vscode-dev-containers>).
- GitHub's own Codespaces security documentation makes the analogous first-party recommendation for a managed devcontainer product: "Always use development environment secrets" (its scoped secrets mechanism) rather than embedding credentials directly, and states that such secrets are withheld entirely from environments the user lacks write access to (<https://docs.github.com/en/codespaces/reference/security-in-github-codespaces>). Notably, this same GitHub doc does **not** address docker socket exposure, sudo, or unprivileged-user configuration anywhere - confirmed by direct fetch - so it should not be read as endorsing or rejecting those other mechanisms, only as silent on them.
- Issue #13 already surfaces the same principle from Anthropic's own docs (mounting host secrets discouraged, repo-scoped/short-lived tokens preferred) - referenced, not repeated.

**Disagreement.** None found; every source that addresses secrets handling agrees on the same shape (scoped/short-lived over host-mounted long-lived credentials). This repo's own `dotfiles-bootstrap` manages `~/.ssh/config` via chezmoi, which - as issue #13 already notes - is distinct from a host bind mount and doesn't conflict with this guidance, but is worth restating here since it's the one place this repo's own tooling touches the exact path this mechanism warns about.

### 7. Agent-vendor-side sandboxing (bubblewrap, seccomp, Landlock, Seatbelt)

**What it is.** Sandboxing enforced by the coding-agent CLI itself, independent of and in addition to whatever container-level hardening wraps it: syscall filtering and filesystem-access restriction applied to the agent's own process tree.

**Tier: image**, for whatever the sandbox mechanism's binary dependency is (this repo already ships `bubblewrap` for exactly this reason, per ADR-... / issue #1, confirmed still present and tested in `test/dev/dev.bats`); the sandbox's _policy_ (what's allowed) is typically the agent CLI's own runtime concern, not something this repo's image or launch tier configures.

**Sources.**

- OpenAI's Codex documentation: on Linux/WSL2, "Codex uses the first `bwrap` executable it finds on `PATH`," i.e. the same bubblewrap binary this repo already ships; on macOS it uses the Seatbelt framework instead (<https://learn.chatgpt.com/docs/sandboxing>). Codex's docs further note that inside a container, the sandbox depends on the host/container allowing unprivileged user-namespace creation - if blocked, Codex documents falling back to `--sandbox danger-full-access` and relying on the container boundary itself for isolation instead.
- Cursor's own engineering blog describes the same class of mechanism for a different vendor: Landlock and seccomp on Linux ("seccomp blocks unsafe syscalls, while Landlock enforces filesystem restrictions"), Seatbelt on macOS, and WSL2's Linux sandbox on Windows because "most existing sandboxing primitives are tailored to browsers and do not support general-purpose developer tools" (<https://cursor.com/blog/agent-sandboxing>). Cursor reports sandboxed agents "stop 40% less often than unsandboxed ones."

**Disagreement.** None on the mechanism category - both vendors converge on syscall filtering plus filesystem restriction as the shape of agent-level sandboxing, distinct from container-level hardening (mechanisms 1-5 above), and both explicitly note that these OS-level primitives can silently degrade inside a container if kernel features they depend on (unprivileged user namespaces, Landlock, seccomp availability) aren't present - which is itself a mechanism-5/6-adjacent argument for keeping the _container_ boundary trustworthy rather than assuming the agent's own sandbox is sufficient on its own. This corroborates, from two independent vendors rather than the seed post, the general principle behind ADR-0011: hardening is layered and composed, not concentrated in one place.

## Recommendations

### Passwordless sudo vs. removing sudo from the dev image

**Recommendation: keep passwordless sudo in the image, unchanged; do not remove or scope it there. Prevent it instead in the _agent runtime_ - the isolated environment an autonomous agent executes in, distinct from a human's dev container - with `no-new-privileges`, as cheap defence-in-depth on top of the isolation substrate (ADR-0012) that already does the real containing.**

Why not touch the image: this repo has a load-bearing, tested dependency on sudo.
ADR-0008 prepends the mise shims directory to `secure_path` specifically because sudo reads it, and `test/dev/dev.bats`'s `"mise resolves a real binary through shims, under sudo, and reports unset outside any project"` exercises `sudo node --version` directly.
Removing sudo would break that test and the workflow it protects, and it is the wrong tier anyway: passwordless sudo at the image tier is fine because the image presumes no threat model (ADR-0011), and the threat model is applied a tier up.

Why the risk is narrower than it first looks, once the substrate is in place: passwordless sudo grants root _inside the container_, but under a disposable-VM substrate that root buys almost nothing new.
It is not a stepping-stone off the box - the agent already reaches VM-root by the shorter path of the docker socket, and the VM is disposable either way (ADR-0012) - and it does not widen access to the workspace or the granted secrets, which the non-root `vscode` user already holds.
The one thing container-root uniquely buys is the ability to _dismantle the in-container guardrails watching the agent_: flush a future egress firewall's `iptables` rules (mechanism 5), kill a socket-cleanup loop, disable a monitor.
That self-disarming capability is the residual risk sudo-prevention actually closes.

Why `no-new-privileges`, and why scoped to the agent runtime: the flag makes setuid-root binaries like `sudo` fail outright (<https://docs.docker.com/reference/cli/docker/container/run/>, <https://www.kernel.org/doc/html/latest/userspace-api/no_new_privs.html>), a single launch-tier `runArg` that touches nothing in the image and needs no change to `dev.bats`, which tests the bare image in isolation.
Scoping it to the agent runtime rather than a shared dev container matters, because `no-new-privileges` disables sudo for _every_ process in the container: folding it into a human's dev container would cost that human interactive `sudo apt install` for a risk that is purely the agent's.
It also closes the self-disarming path as a side effect - a non-root process under `no-new-privileges` cannot acquire `NET_ADMIN`, so it cannot flush the very egress firewall it would want to tear down - and wherever the agent runtime is eventually tested, the closing assertion is that `sudo -n whoami` **fails** under the flag, the mirror of `dev.bats`'s `"vscode has passwordless sudo"` for the bare image.

The honest scope of the benefit: under the VM substrate this is defence-in-depth verging on redundant - the VM, not the missing sudo, is what actually contains a hostile agent.
Its importance rises sharply in the _absence_ of a VM: any container-only agent-runtime approach (chosen for a good reason, without a substrate backstop) should treat sudo-prevention as a primary control rather than an optional one, because there the in-container guardrails are the only guardrails.
And as with the socket, this is a launch-tier control the image cannot turn on for a consumer: an agent runtime that omits it inherits the blanket-sudo surface, consistent with ADR-0011's stated tradeoff.

### `docker-outside-of-docker` host-socket exposure in this repo's own devcontainer

**Recommendation: keep `docker-outside-of-docker`, but stop treating the socket as a risk to _accept_ and treat it as a risk to _contain by substrate_.**
The socket's host-root risk is irreducible while the container runs directly on the host, so the fix is not any socket configuration but the isolation substrate underneath it: run docker-heavy agent sessions inside a disposable micro VM holding only the assigned workspace and docker, where an escape reaches only a scope that already contains nothing more than what the agent was granted.
This is recorded as [ADR-0012](../adr/0012-the-isolation-substrate-is-a-fifth-tier.md), which names the isolation substrate as a fifth tier, one below ADR-0011's launch tier.

**Why the risk is irreducible in-substrate, not merely large.**
The escape is not "break out of this container" but "ask the host daemon to start a different, privileged one" (`docker run --privileged -v /:/host`), which bypasses every launch-tier control - dropped capabilities, `no-new-privileges`, the egress firewall, the non-root user - at once, because none of them constrain a container the host daemon starts fresh.
No socket-level configuration closes this for this repo's workload.
A socket-proxy filters by API endpoint, not request body, so even a `create`/`start`-permitting configuration cannot distinguish an ordinary `docker run` from `docker run --privileged -v /:/host`; and `container-base`'s whole job is building and testing images, so it genuinely needs the `create`/`build`/`start` endpoints a protective proxy would have to block.
The seed post's proxy buys that author safety only because that author needs read-mostly visibility and can block those endpoints outright - a position that does not transfer to this repo.
Anthropic's reference sidesteps the tradeoff entirely by needing no docker access at all (confirmed by direct fetch of its Dockerfile and `devcontainer.json`), which this repo cannot copy.

**Why the substrate, and why a disposable VM specifically.**
Rootless Docker is the lighter alternative and is worth documenting, but it is not sufficient on its own: it demotes the escape from host root to the developer's own uid, which still exposes the developer's home, SSH keys, and shell rc files - persistence and credential theft, the exact assets mechanism 6 above exists to protect.
A disposable micro VM whose only contents are the workspace and docker makes the escape _boring_ instead: escaping to VM-root grants exactly `{workspace, docker}`, which is what the agent already had, so the blast radius collapses to "what you already gave it."
This is the default-deny principle the whole mechanism serves - the agent's world is the code it is assigned plus the services it is explicitly given, and nothing else of the host exists.
Sysbox is the Linux-native way to get the same isolation without a separate VM (isolated in-container docker, no host socket) but is Linux-host-only, so it does not cover a macOS dev host; on macOS the substrate is nearly free, since the daemon already runs in a VM (Docker Desktop's) and the move is only to a dedicated, home-free micro VM such as Colima or Lima.

**What this changes in practice.**
`docker-outside-of-docker` stays in `.devcontainer/devcontainer.json`; under a disposable-VM substrate the mounted socket is the VM's daemon, not the host's, so it upholds the default-deny principle rather than violating it.
CI needs no change: GitHub-hosted `ubuntu-latest` runners are already ephemeral, per-job VMs, so the CI path is substrate-confined for free, and this recommendation targets the persistent dev host only.
The workspace mount must be scoped to the single repo, not its parent directory or `$HOME`, or "only the code it is assigned" leaks the sibling repos beside it.
The unattended / auto-mode combination issue #13 flags is not a separate caution to document but the exact case the substrate neutralizes: it is what makes escaping to VM-root uninteresting, so a fully unattended session against a VM-confined profile no longer carries the materially larger blast radius it would against a container-on-host profile.

### VS Code IPC sockets: eliminate with a headless agent runtime, don't strip

**Recommendation: the agent runtime is _headless_ - no VS Code Server, no attached editor - which removes the entire mechanism-3 surface by construction. The seed post's env-stripping is demoted to a fallback for the one case it actually fits: running an agent inside a human's live VS Code devcontainer.**

Reframing the mechanism: every artefact mechanism 3 names - `vscode-ipc-*.sock`, `VSCODE_IPC_HOOK_CLI`, `GIT_ASKPASS`, `SSH_AUTH_SOCK`, `BROWSER` - is created by the VS Code Server when a client attaches, as the channel back to that client on the laptop.
It is therefore a property of _attaching an editor_, not of _running a container_.
An agent runtime that is separate from the dev container and headless has none of it, and does not need the seed post's three-layer strip at all.
This matters the more because the channel can bypass the substrate: the VS Code remote tunnel is a connection the human punches from the laptop into the confined environment, and - per the Red Guild post and Microsoft's still-open issue #6608, which publishes no security model for it - a compromised container-side can ride it back out to the laptop, with `SSH_AUTH_SOCK` additionally handing over live use of the host's SSH agent (overlapping mechanism 6).
Stripping re-injected variables is whack-a-mole against a tool the seed author says "actively works against you"; eliminating the tool from the agent runtime removes the class.

Keeping "separate" actually separate at launch: the agent runtime may be launched from the dev container for convenience, but "launched from" must not become "inherits from." Two launch-hygiene rules preserve the separation:

- **Clean environment.** The launcher must not forward the dev container's environment into the agent runtime, or it carries `VSCODE_IPC_HOOK_CLI`, `GIT_ASKPASS`, `SSH_AUTH_SOCK`, and `BROWSER` straight in. `docker run` starts clean by default; the trap is a wrapper that passes `-e`/`--env-file` of the current environment.
- **No socket mounts.** The launcher must not bind-mount the dev container's `/tmp` IPC sockets or the forwarded `SSH_AUTH_SOCK` path into the agent runtime.

One composed caveat, mechanism 3 combined with mechanism 1: because the agent runtime holds the docker socket, "separate" also requires that its daemon has no live VS-Code-attached sibling to `docker exec` into - otherwise the agent reaches a human's devcontainer, and through it the IPC channel, via the socket.
ADR-0012's dedicated, disposable VM (contents: only the workspace and docker, not the human's dev container) already guarantees this; a shortcut that runs the agent as a sibling on the human's shared Docker Desktop would break it.

Tier, restated: the primary control is not the survey's launch-and-dotfiles env-stripping but an _agent-runtime architecture_ decision (headless) plus launch hygiene.
The dotfiles-tier shell-init strip survives only inside the fallback, for an agent sharing a human's VS Code devcontainer, and should carry the explicit caveat that it patches a re-injecting tool against an undocumented threat model.

### `cap_drop` and `no-new-privileges`: defence-in-depth inside the VM, not the boundary

**Recommendation: `no-new-privileges` is already the agent-runtime control from the sudo recommendation above; add `cap_drop: [ALL]` with nothing added back. Treat both as cheap defence-in-depth on the VM interior, not as the security boundary - under a VM substrate the hypervisor is the boundary, and these harden a disposable interior the socket already lets the agent own.**

Two observations settle the capability posture.

First, `cap_drop` is a container control with no bearing on the VM boundary.
Capabilities are per-process privileges against a _shared_ kernel; the container-inside-VM boundary is namespaces / caps / seccomp, but the VM-to-host boundary is the hypervisor, which capabilities cannot cross - which is exactly why `--privileged` inside the VM yields only VM-root (mechanism 1).
So dropping capabilities protects only the VM's interior, and that interior is disposable (ADR-0012) and already VM-root-reachable by the agent through the docker socket.
`cap_drop: [ALL]` is worth setting because it is free, but it is the same category as sudo-prevention: belt-and-suspenders over the hypervisor, decisive only in a non-VM container-only runtime where the in-OS controls _are_ the boundary.

Second, the add-back list is empty because egress is enforced outside the VM.
An egress firewall inside the container, or even in the VM's own `iptables`, is flushable by the socket-holding agent (a privileged `--net=host` sibling runs `iptables -F`), so egress must live at the host / hypervisor network layer, outside the VM, where VM-root cannot alter it (see mechanism 5).
Because egress is not in the container at any layer, the agent container never needs `NET_ADMIN` / `NET_RAW`, and `cap_drop: [ALL]` needs no add-back - unlike Anthropic's in-container `init-firewall.sh`, which re-adds both precisely because it assumes no VM substrate to host egress on.

### Network egress: enforce outside the VM, and a deliberately simple policy

**Recommendation: egress control belongs outside the VM (host / hypervisor network layer), not inside it; and the policy leaning is deliberately minimal - internet access allowed, local / private-network access denied unless explicitly allowed. Full implementation is deprioritized for now.**

Location is settled by the socket (mechanisms 1 and 4): any egress rule the agent can reach through the docker socket, it can flush, so the rule must live where VM-root cannot - outside the VM.

On policy, this repo takes a third position distinct from the two the survey found.
Anthropic runs default-deny with a domain allowlist; the seed post leaves egress open and monitors it.
This repo's leaning is neither: allow outbound internet, but deny the private and link-local ranges (RFC1918, `169.254.0.0/16` including the cloud-metadata endpoint) unless a target is explicitly allowed.
The intent is to block the high-value, low-cost harm - the agent pivoting into the local network or reaching a metadata endpoint - while accepting exfiltration risk rather than paying the ongoing cost of maintaining a domain allowlist.
This is recorded as the current leaning, not a built control: egress matters but is time-consuming, and full treatment - including any company deployment, where a stricter allowlist would be warranted - is deferred.

### Credentials and secrets: the capability the substrate cannot contain

**Recommendation: the agent runtime carries no host credential and no durable secret. It gets at most one repo-scoped, short-lived credential, and this repo's current (work-in-progress) setting is: local commits yes, push no, and a fine-grained PAT scoped to this repo with `Issues: write` only.**

Why this is the mechanism the VM does not help with: filesystem, process, capability, and network harms all dead-end at a disposable VM, but a credential is an authorization to act on a system _outside_ the VM - the remote, a cloud API - so persistence (a backdoor pushed to the remote), exfiltration of a long-lived secret (still valid after the VM is gone), and over-broad reach (a host key spanning every repo) all pass straight through the hypervisor boundary.
Short-lived is therefore as load-bearing as scoped: a scoped-but-permanent token is still a durable exfil prize.

What the agent runtime does _not_ get, restated as closed channels: no `~/.ssh`, no `SSH_AUTH_SOCK` forward or `GIT_ASKPASS` (mechanism 3), no host cloud-cred files, and no `dotfiles-bootstrap` - applying the human's chezmoi bundle is a dev-container convenience that can carry `~/.ssh/config` and shell-rc secrets, so the agent runtime, being minimal, does not run it (the third human-convenience layer it strips, after VS Code and sudo).

The current setting, and why it is a work in progress: this is a live convenience-versus-security tradeoff and a moving target.
For now the agent commits locally but does not push, interacts with issues through a fine-grained PAT scoped to this repo with only `Issues: write`, and delivers code as a diff a human applies.
The natural next step, if the PR flow is wanted inside the runtime, is push-to-branch-but-not-`main`, and the key fact for that is that the per-branch restriction is not a token property: a fine-grained PAT's permissions are per-repository and per-capability (`Contents`, `Issues`, `Pull requests`), not per-branch, so "push branches, not `main`" is enforced by a **branch-protection ruleset on `main`** (require a PR, block direct pushes) layered over a `Contents: write` + `Pull requests: write` token, not by the token alone.
That step is deferred; the commit-no-push / issues-only baseline is what stands today.

### Agent-vendor-side sandboxing: a defence-in-depth layer the substrate makes safe to trust loosely

**Recommendation: run the agent CLI's own sandbox (bubblewrap / seccomp / Landlock) on top, as defence-in-depth. The image already ships `bubblewrap`, so nothing new is needed there; the sandbox _policy_ is the agent CLI's runtime concern, not the image's or the launch tier's.**

Under the in-VM-OS-is-defence-in-depth principle (mechanism 4), the agent's own `bwrap` / seccomp sandbox is one more layer inside the VM, not the boundary - worth having, but not load-bearing.
What is worth recording is the payoff the substrate delivers here, because it turns a caveat both vendor sources raise into a non-issue.

Both Codex and Cursor note that these OS-level primitives can _silently degrade inside a container_: bubblewrap needs unprivileged user-namespace creation, and where that (or Landlock, or seccomp) is unavailable, Codex documents falling back to `--sandbox danger-full-access` and relying on the container boundary instead.
A sandbox that silently fails open is normally worse than a known-absent one.
But under our substrate that silent fallback is exactly the designed behaviour: the VM is the real boundary, so a degraded agent sandbox loses only a supplementary layer, not the boundary - which is precisely the case that would be catastrophic in a non-VM runtime, where the same silent failure removes the primary control.
The substrate defangs the fragility.

Two operational notes follow.
For the sandbox to engage rather than silently fall back, the VM should permit unprivileged user-namespace creation; the user-namespace attack surface that normally argues against enabling it is itself defanged here, since a userns-based escape reaches only VM-root (disposable).
And since the agent runs inside a Linux VM, the relevant primitives are bubblewrap / seccomp / Landlock; Seatbelt matters only for a no-VM agent running directly on a macOS host, which is not this model.
