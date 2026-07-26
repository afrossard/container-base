# Which VM tool hosts the agent runtime: experiment results

Research for [issue #22](https://github.com/afrossard/container-base/issues/22), the follow-up to [issue #21](https://github.com/afrossard/container-base/issues/21) and its own research document, `docs/research/0021-vm-microvm-isolation-for-agent-runtimes.md`.

## What this settles

0021 named one fact that reading could not settle: whether a full docker daemon runs inside an `apple/container` guest, with microsandbox carrying the identical unknown.
This document reports the result of actually running all three candidates - `apple/container`, microsandbox, and Lima as the control - against a shared draft of the `-agent` image (ADR-0014), on the real dev host rather than from documentation.

**All three run a full docker daemon in the guest.**
The deciding fact from 0021 is answered yes for every candidate, so the tie-break moves to what 0021 held in reserve for that case: storage correctness, cold start, default mounts, and the egress/secret mechanisms that were previously only documented claims.

## Host and method

- macOS 26.5.2, Apple M4, 24 GB RAM, arm64.
- `apple/container` 1.1.0, microsandbox (`msb`) 0.6.7, Lima 2.2.0 - each installed by the human operator per issue #22's plan, since every installer needs an admin password.
- The draft `-agent` image: `ghcr.io/afrossard/container-base:0.0.3-dev` (this repo's own published dev image) plus `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `iptables`, and `tini`, with a small entrypoint script that starts `dockerd` in the background and waits for its socket before exec'ing the container's command.
- Built once with `docker build`, saved with `docker save`, and loaded locally into both `container` and `msb` (`container image load` / `msb image load`) - no registry push needed for either.
- Lima is not OCI-native, so its arm boots the project's own `template://docker` (an Ubuntu cloud image provisioned with Docker via `get.docker.com` through cloud-init) rather than the draft image; this is the same asymmetry 0021 already identified.
- Per arm: start the guest, confirm `dockerd` is up, `docker build`/`docker run` a trivial Alpine image, then `docker build` this repo's real `images/dev/Containerfile` inside the guest, copying the build context in via each tool's own file-transfer mechanism (no bind mount, per ADR-0013).
- Everything below is this session's own direct observation on this host, not documentation, except where explicitly marked otherwise.

**One confidence flag up front.**
The `apple/container` arm ran against a kernel the operator had already installed as the tool's default before testing began (a kata-containers arm64 static kernel, `kata-static-3.28.0-arm64.tar.zst`, set via `container system kernel set`), not the tool's own stock default kernel.
Whether the stock default kernel would have passed the same tests unmodified was not tested and is recorded as open, below.

## `apple/container`

**Docker-in-guest: passes, but not on the tool's default capability set.**
The first attempt with plain `container run` failed: `dockerd` could not create its NAT chain (`iptables ... Permission denied (you must be root)`, despite running as uid 0) and could not delete its own nftables rules (`cache initialization failed: Operation not permitted`).
`cat /proc/1/status` showed why: `CapEff` decoded to exactly Docker's own default non-privileged capability list (`CHOWN, DAC_OVERRIDE, FOWNER, FSETID, KILL, SETGID, SETUID, SETPCAP, NET_BIND_SERVICE, NET_RAW, SYS_CHROOT, MKNOD, AUDIT_WRITE, SETFCAP`) - missing `CAP_NET_ADMIN` and `CAP_SYS_ADMIN`.
This is worth stating plainly because it contradicts the natural assumption that a full per-container VM grants the guest's root user everything: `container run` applies a docker-style restricted default even though the isolation boundary is a hypervisor, not a shared kernel.
Adding exactly `--cap-add CAP_NET_ADMIN --cap-add CAP_SYS_ADMIN` (not `--cap-add ALL`) was sufficient; `dockerd` then started cleanly.

**Storage: a genuine pass.**
`docker info` reported `Storage Driver: overlayfs`, `Cgroup Version: 2`, and the root filesystem was `/dev/vdb`, a real ext4 block device (not `vfs`, not a size-capped overlay upper layer).
The trivial build/run and this repo's real `images/dev/Containerfile` build both completed without incident, the latter in **57 s** end to end (network-bound: apt, Homebrew, and the Claude Code apt repository, all reachable by default).

**Default mounts: clean.**
`mount` and `df -h` inside the guest showed only the root disk and standard virtual filesystems - no `$HOME`, confirming `container run` (unlike `container machine`, which the issue explicitly warned off) does not carry the operator's home directory in by default.

**Cold start.**
First-ever launch (fetching the kernel and a ~64 MB init image) took **~6 s**.
With both cached, a second launch took **~0.6 s**.

**Repo directory supply.**
No bind mount exists by default; `container copy <local-path> <container>:<path>` copied the build context into the running guest directly, with `--volume`/`--mount` available as an opt-in bind mount if ever wanted.

**Network egress.**
Open by default, through Apple's `vmnet` bridge with a real host-routed guest IP (`192.168.64.x`) and a default route to the host.
`container network create` exists for custom networks, but nothing in the CLI implements an allow/deny policy - matching 0021's reading of the docs, now confirmed by observation.

**Secrets.**
No placeholder mechanism; `-e`/`--env-file`/`--publish-socket` are the only injection paths, same as 0021 found in the docs.

**A minor rough edge.**
`container rm -f` against a running guest with `dockerd`'s own bridge still up sometimes failed once with a cgroup-kill error; `container stop` followed by `container delete` was reliable. Not load-bearing, but worth knowing before scripting around it.

## Lima (the control)

**Docker-in-guest: proven, as expected**, and unremarkable in the way a control result should be: `dockerd` came up through the project's own `template://docker` cloud-init provisioning, rootless, on `rootlesskit` with the `gvisor-tap-vsock` network driver. `docker info` showed `overlayfs` / cgroup v2 / systemd cgroup driver.

**The `mounts: []` override did not do what 0021 assumed - a real, undocumented finding.**
The first configuration tried was exactly what 0021 recommended: `base: [template:docker]` plus a top-level `mounts: []`.
`$HOME` was still mounted read-only via `virtiofs` afterward.
Lima's config merge across a `base:` chain concatenates list fields like `mounts` rather than letting a later file's empty list clear an earlier one - nothing in Lima's own mount or config-merge docs states this either way, so it was only found by trying it.
The fix was to stop including `template:_default/mounts` in the base chain at all (copying `template:docker`'s provisioning scripts directly into a new file instead of inheriting them), rather than trying to override an inherited list.
With that change, `mount` and `ls /Users` inside the guest confirmed zero host mounts.

**Cold start.**
First-ever launch, including the one-time Ubuntu cloud image download, took **~74 s** (~35 s of that was the download).
With the image cached, a fresh instance took **~33 s**, almost all of it cloud-init provisioning `dockerd` via `get.docker.com` on every new instance - Lima is not OCI-native, so there is no equivalent of loading a prebuilt `-agent` image straight into the guest; each session pays this cost unless the image work of ADR-0014 is separately reproduced as a Lima disk image.

**Real build.**
This repo's `images/dev/Containerfile` built in **53 s**, comparable to `apple/container`'s 57 s once the network-bound layers dominate either way.

**Repo directory supply.**
`limactl copy` (rsync/scp-backed) copies files in; like the others, this is a copy each session, not a live mount, with the same provisioning-cost implication noted above.

**Network egress.**
Open by default via `gvisor-tap-vsock`; Lima layers no allow/deny policy of its own, matching 0021.

## microsandbox (`msb`)

**Docker-in-guest: passes immediately, on generous defaults.**
`dockerd` started with no capability flags at all.
`CapEff` decoded to `0x1ffffffffff` - effectively every defined Linux capability - a materially more permissive default than `apple/container`'s docker-style restricted set.
`docker info` reported `overlayfs` and cgroup v2 at daemon start.

**Storage: the default is a false pass, and this is the header finding of the whole experiment.**
The trivial Alpine build/run succeeded, but building this repo's real, multi-layer `images/dev/Containerfile` failed outright: `failed to prepare ... mount source: "overlay" ... err: invalid argument`.
The cause: msb's own guest root is itself an overlay filesystem (`lowerdir=/.msb/rootfs/lower, upperdir=/.msb/rootfs/upperfs/upper`), and `/var/lib/docker` is a second overlay mount carved from that same backing - so when Docker's containerd snapshotter tries to overlay-mount _its own_ image layers on top, the kernel refuses to stack overlayfs on overlayfs.
`docker info` reporting `overlayfs` at daemon start is true and irrelevant: the driver only fails once a real build exercises it, which a smoke test that stops at `docker version` would never catch.
This is 0021's anticipated "an overlayfs-to-vfs fallback is a pass that is not really a pass" concern, materializing in a sharper form than expected: it does not quietly fall back, it errors.

**Two fixes exist, at different costs, and one is a clean fix rather than a fallback.**

1. **Force Docker's `storage-driver` to `vfs`** (`/etc/docker/daemon.json`). This works, but is markedly slower (the real build took **90 s**, worse than either other arm) and disk-hungry: on the default 3.9 GB root disk it ran the guest completely out of space mid-build (`no space left on device`) and needed the disk enlarged to complete at all.
2. **Give `/var/lib/docker` its own ext4-backed disk instead of nesting overlay on overlay**: `msb volume create --name docker-data --kind disk --size 20G` (msb formats the raw disk as ext4 itself), mounted at launch with `--mount-named "docker-data:/var/lib/docker:kind=disk,size=20G"`. With that single flag, `docker info` again reported genuine `overlayfs`, and the real build **passed**, in 98 s (layer export was slower here than the other two arms - virtiofs/disk I/O for the mounted volume, not a fundamental limit).

Read together with `apple/container`'s capability finding, the honest framing is symmetric: **neither OCI-native candidate passes this repo's real build on pure defaults.** Each needs exactly one non-default launch flag once you know which - `apple/container` needs two added capabilities, microsandbox needs its writable Docker storage backed by a real disk rather than the default nested overlay.

**Default mounts: clean.**
No host mount by default, same as the other two.

**Cold start.**
**~0.6-0.8 s** with the image already cached (comparable to `apple/container`'s warm number; both are far faster than Lima because neither pays Lima's per-session OS-install cost).

**Egress: the strongest documented claim in 0021, and it is now directly verified rather than quoted from docs.**
`--no-net` produced a guest with no default route and no reachability at all (confirmed via `ip route` and a failed `curl`).
A single rule, `--no-net --net-rule "allow@github.com:tcp:443"`, let `https://github.com` through (`200`) while `https://1.1.1.1` was refused (`000` - connection failure) - a working default-deny hostname allowlist enforced from outside the guest, exactly as documented, with DNS for the allowed hostname resolving correctly with no separate DNS rule needed.
(The `dns` semantic target mentioned in `msb run --help` - `allow@dns[:tcp|udp|any]` - rejected every syntax tried, in every combination; not needed for the test above, but recorded as a CLI/docs mismatch worth a bug report rather than a working feature.)

**Secrets: also directly verified.**
`--secret "MY_TOKEN@github.com"` (reading the real value from the host's own `MY_TOKEN` environment variable) resulted in the guest's `$MY_TOKEN` literally holding the placeholder string `$MSB_MY_TOKEN` - never the real value, confirmed by echoing it inside the guest - while an actual HTTPS request to the allowed host (`github.com`) using that same variable succeeded (`200`).
The real secret is substituted in-flight, only for traffic to the host it was scoped to, and the guest never holds it.
This is the single most direct, most load-bearing confirmation in this experiment: both of 0021's deferred open questions (egress enforcement, secret handling) are answered yes, by observation, for this candidate alone.

**Automation footgun, worth flagging plainly.**
`msb exec` without `--no-tty` hung indefinitely against every non-interactive script tried in this session - it appears to wait on an interactive PTY attach that a scripted caller never satisfies.
`--no-tty` (or `--stream`) fixed it every time.
Anything that scripts against `msb` - which an agent-runtime launcher necessarily does - must pass this flag explicitly.

**`msb copy` semantics.**
Copying a directory into an already-existing destination directory nests it under the source's own basename rather than merging into the destination; copying files individually, or into a not-yet-existing destination, avoided the surprise.

**An unresolved nuance on user namespaces.**
During the real `images/dev/Containerfile` build, Homebrew's own `bwrap` post-install self-test printed a warning ("No permissions to create a new namespace... the kernel does not allow non-privileged user namespaces"), though the build still completed.
A direct root-context `bwrap --unshare-all` invocation afterward succeeded without issue.
Since this repo's own dev image flags bubblewrap as non-optional for Claude Code's sandbox mode, and Claude Code inside an agent runtime would not necessarily run as root, whether _unprivileged_ `bwrap` works in an msb guest is a real open question this session did not chase down far enough to answer either way.

**A sandbox-registry rough edge, unrelated to the storage or capability findings.**
`msb rm -f <name>` twice reported "not found" for a sandbox that `msb run --name <name>` then refused to recreate ("already exists").
`--replace` worked around it both times. Not investigated further; recorded so a future session does not lose time on it.

## Recommendation

**Adopt microsandbox, launched with a disk-backed named volume mounted at `/var/lib/docker`, as the primary target for the agent runtime; keep `apple/container` as the documented fallback if microsandbox's maintenance risk proves unacceptable; keep Lima as the always-available last resort.**

This replaces 0021's conditional recommendation ("adopt whichever OCI-native candidate survives the experiment") with an unconditional one, because the experiment no longer leaves a tie to break on the deciding fact alone - both OCI-native candidates run docker in the guest, so the choice turns on what was previously undecided:

- **Both need one non-default launch flag to pass this repo's real build, and both costs are now known and bounded.** `apple/container` needs two added capabilities; microsandbox needs its Docker storage backed by a real disk (a `msb volume create ... --kind disk` plus one `--mount-named` flag) rather than the default nested-overlay layout. Neither is a research question anymore - both are one-line additions to whatever launches the agent runtime.
- **microsandbox is the only candidate that answers the two questions ADR-0013 and 0021 deliberately left open, and it answers them by direct proof, not documentation.** The egress allowlist and the placeholder-secret mechanism both worked exactly as claimed, in this session, against real network traffic. Choosing `apple/container` still leaves egress enforcement and secret injection as this repo's own future work, on top of whatever engineering `apple/container` itself required; choosing microsandbox converts both into "already built, verified once, wire it into the launch profile."
- **Portability now cuts further than a preference - it is a second, working use of the same tool.** microsandbox is the only candidate documenting, and expected to work on, all three host platforms this repo might ever run the agent runtime on. `apple/container` is Apple's own framework, unconditionally macOS-and-Apple-silicon-only; adopting it means a structurally different launcher, guest-image path, and egress mechanism wherever the runtime runs on Linux or Windows, in addition to still having to build the egress/secrets layer microsandbox already has.
- **The honest cost of this recommendation is the storage workaround's overhead** - the real build took 98 s under the disk-backed volume fix, against 57 s for `apple/container` and 53 s for Lima, and volume lifecycle (create once, reuse across sessions, size appropriately) needs to be part of whatever publishes the `-agent` image, not left to whoever launches it. This is a real, measured cost, not a hidden one, and it is the reason `apple/container` is recorded as a fallback rather than dismissed: if microsandbox's maintenance risk (7k stars against `apple/container`'s 48k, a single wrapper vendor, no third-party security track record - per 0021's own reservation, unchanged by this experiment) or its build-time overhead prove unacceptable in practice, `apple/container`'s clean storage pass and Apple-maintained backing make it the direct substitute, at the cost of building egress and secret injection by hand.

**Lima remains the last-resort fallback exactly as 0021 concluded**, unchanged by this experiment: proven, slower to provision per session (33-74 s against microsandbox's and `apple/container`'s sub-second warm starts), and non-OCI-native, so ADR-0014's "the image is the guest" property does not apply to it.

## Portability cost, stated explicitly (per the acceptance criteria)

Adopting **microsandbox**: the launcher, guest-image handling, and egress/secret configuration all carry over unchanged to a Linux host (KVM) or Windows host (Windows Hypervisor Platform), per microsandbox's own documented platform support - not independently verified on those platforms in this session, since the dev host is macOS. This is the scenario 0021 flagged as worth a stated preference, and this experiment gives it a concrete tool to point at rather than a hypothetical.

Adopting **`apple/container`** instead: nothing here carries over. A self-hosted Linux runner or a Windows agent host would need a wholly different launcher (there is no `apple/container` outside Apple silicon macOS), a different guest-image pipeline for whatever that platform's equivalent turns out to be, and the egress/secret layer this repo would already have had to build for `apple/container` on macOS would need to be rebuilt again for that second tool, rather than reused.

## ADR-0013's open consequence

ADR-0013 recorded **"the tool is not chosen yet"** as a consequence, pointing at this issue.
That consequence is resolved: the deciding fact (docker-in-guest) is proven for all three candidates, and the tie is broken as above.
ADR-0013 should be amended to name microsandbox, with the disk-backed `/var/lib/docker` volume as a stated launch requirement, `apple/container` (with its two added capabilities) as the documented fallback, and Lima as the last resort - superseding the "not chosen yet" line rather than leaving it standing.

## Open questions carried forward

- **`apple/container`'s stock default kernel was not tested.** Every `apple/container` result above ran against a kata-containers kernel the operator had already installed as the tool's default before this session began. Whether the tool's own out-of-the-box kernel passes the same capability and storage tests unmodified is unverified.
- ~~**Unprivileged (non-root) `bwrap` inside an msb guest.**~~ **Resolved, see the addendum below.** A direct non-root `bwrap --unshare-all` invocation succeeded cleanly; the Homebrew warning was specific to that install step, not a general limitation.
- **The `msb run --help`-documented `dns` semantic network target could not be made to parse**, in any token combination tried. Worth a minimal reproduction and an upstream report; not load-bearing for the recommendation, since the hostname-only allowlist test above resolved DNS for the allowed target without it.
- **Egress and secrets on `apple/container`** remain unbuilt, exactly as 0021 left them, if the fallback is ever exercised.
- **Everything ADR-0013 already deferred and this issue did not touch**: where egress enforcement ultimately lives relative to issue #19's in-guest firewall script, whether Claude Code consumes Workload Identity Federation, and whether the agent runtime image stays in this repo.

## Addendum: running Claude Code itself inside the microsandbox guest

A follow-up session went one level up the stack: not just proving `dockerd` runs inside microsandbox, but proving Claude Code itself - the thing the agent runtime exists to isolate - runs inside it, authenticates, and executes tool calls, both as root and as a non-root user.

**Non-root `bwrap` works.**
A direct `su vscode -c 'bwrap --ro-bind / / --dev /dev --unshare-all --die-with-parent echo bwrap-ok-as-vscode'` succeeded cleanly, with no `unprivileged_userns_clone` sysctl even present to restrict it.
This resolves the open question above: whatever caused Homebrew's own bwrap self-test to warn during the earlier real-image build was specific to that install step, not a general limitation of unprivileged user namespaces in an msb guest.

**Headless auth via `--secret`, confirmed against the live API.**
`claude setup-token` (a long-lived-token flow built for exactly this case) run on the host, its output exported as `CLAUDE_CODE_OAUTH_TOKEN` in the host shell via `read -rs` (never a literal command-line argument, so it never touches shell history), then the guest launched with `--secret "CLAUDE_CODE_OAUTH_TOKEN@api.anthropic.com"`.
`claude -p "..."` inside the guest - as both root and the non-root `vscode` user - returned a real, correct model response.
`claude auth status` reported `authMethod: oauth_token`, tied to the operator's actual Pro subscription rather than separate API billing.
The guest's own environment variable held only the literal placeholder string (`$MSB_CLAUDE_CODE_OAUTH_TOKEN`), never the real token, the same behavior already verified with a dummy secret earlier in this document.

**The interactive TUI needs a real login, and env-var auth does not extend to it.**
`claude` (no `-p`) still prompted for login even with `CLAUDE_CODE_OAUTH_TOKEN` set and headless calls already succeeding.
This reads as intentional product design rather than a bug: token/API-key env vars authenticate headless/programmatic invocation, and the interactive TUI is built to always require a real session for a human at the keyboard.
For an autonomous agent runtime this is the right split anyway - the actual invocation shape is headless (`-p`, or SDK-style), not an attended TUI.

**Getting the interactive OAuth flow to work at all took two false leads before the real cause turned up.**
The first attempts failed with `Invalid OAuth Request... Invalid code_challenge_method: missing`.
The first hypothesis (this document's own, tried and set aside) was a stale client version - the guest's apt-installed Claude Code (2.1.211-2.1.212) was several versions behind the host's self-updated native install (2.1.220) - so the guest was upgraded via `npm install -g @anthropic-ai/claude-code`, and the stale apt package removed to avoid PATH ambiguity between the two.
That upgrade did not fix the error.
The real cause, found by the operator: `msb exec -t`'s terminal rendering wrapped the long authorization URL across multiple lines, and a naive copy-paste (or an editor autocorrecting line endings) corrupted it, dropping the `code_challenge_method` parameter.
Manually reassembling the URL before pasting it into the browser worked immediately, on both the npm-installed 2.1.220 build and, in a later retest, the original unmodified apt-installed 2.1.211 build - confirming version was never the actual issue.
Worth recording plainly so a future session does not repeat the version-upgrade detour: **widen the terminal before triggering an OAuth login through any PTY-relayed exec session**, and treat a mangled `redirect_uri`/`code_challenge_method` error as a copy-paste artifact first, a client-version problem second.

**Two legitimate credential patterns for two different use shapes, not one right answer.**

- **Headless/autonomous** (the architecture ADR-0013 actually describes): mint a token once via `claude setup-token` on the host, inject it fresh into each disposable guest via `--secret`, never persist it in guest storage. Matches the disposable-VM model exactly.
- **Interactive/attended** (a human driving a live session, explicitly chosen here for convenience over the stricter default): persist real, browser-completed OAuth credentials in a named `kind=dir` volume mounted into the guest, so a fresh sandbox does not need to repeat the login flow. This is a deliberate, informed departure from ADR-0013's "no persistent writable state" preference, not an oversight - and it has a real, stated cost: a `kind=dir` volume is a plain host directory (confirmed via `msb volume inspect`, at `~/.microsandbox/volumes/<name>/`), shared into the guest over virtiofs, so the resulting credential sits as an ordinary, readable file on the host's own filesystem for as long as the volume exists - a materially different exposure than Docker Desktop's own VM disk or macOS Keychain.

**Claude Code's own state is split across a directory and a sibling file, and mounting only the directory silently loses the rest.**
Persisting `~/.claude/` (credentials, backups, cache, sessions) alone was not sufficient: `~/.claude.json`, a separate top-level file holding broader account/config state, lives outside that directory and was silently recreated empty on every sandbox `--replace`, since it sits on the guest's own ephemeral disk rather than the mounted volume.
Claude Code detected this correctly rather than failing silently - it reported the file missing or corrupted and pointed at its own backup under `.claude/backups/`, which had persisted (since that path is inside the mounted directory).
Restoring from that backup and adding a second, explicit `--mount-file` for `~/.claude.json` (backed by a plain file in the same host directory as the volume) made credentials survive a full `--replace` cycle cleanly.
The general lesson, beyond Claude Code specifically: **never assume a tool's persistent state is a single directory** - check for sibling dotfiles before wiring up a persistence volume for anything.

**A `kind=dir` volume can be attached to more than one running guest at once - unlike `kind=disk` - confirmed directly rather than assumed, in the later session that wired this into `scripts/launch-agent-runtime` as `--persist-claude-auth`.**
Two sandboxes were launched with the same named `kind=dir` volume mounted while both were still running: one wrote a file, the second read it back and appended its own write, and neither launch errored the way a second `kind=disk` attachment does ("already attached with an incompatible disk mode", `scripts/launch-agent-runtime`'s own `DOCKER_DATA_VOLUME` comment).
This is what makes sharing one `--persist-claude-auth` credential volume across multiple sessions - even concurrently, not just sequentially - safe: the single-attachment exclusivity that forces `DOCKER_DATA_VOLUME` to be scoped per session is a `disk`-kind property, not a property of msb's named volumes generally.

**Sandboxes stay running until stopped, by this image's own design, not msb's.**
This experiment's draft image's `ENTRYPOINT` starts `dockerd` and then `exec`s into `"$@"`, falling back to `sleep infinity` when no command is given - a deliberate choice so a sandbox could be launched once (`-d`) and attached to repeatedly (`msb exec`) across a long testing session.
Two idle guests were left running for some time as a direct result before this was noticed.
The real `-agent` image should keep the entrypoint (it is what guarantees `dockerd` is ready before the agent's own commands run) but drop the `sleep infinity` fallback: launched as `msb run --replace --name <session> agent-image -- claude -p "task"`, the entrypoint still starts `dockerd`, then hands off directly to the actual task, and the VM's lifetime ends exactly when the task does - a true one-shot, disposable-per-session run with no lingering resource use and no manual stop required.

## Prototype code

Not committed, per this issue's own instructions. The draft `-agent` Containerfile, entrypoint script, and Lima template used for the main experiment lived in a scratch directory for the session and were discarded; every guest, sandbox, and locally loaded image created during that testing was removed at the end of the session.
The addendum above reused the same draft image for a follow-up exploration; its sandboxes (`claude-msb`, `claude-msb-apt`, `claude-session`) and the two named volumes it created (`docker-data`, `claude-creds`, the latter having held a real, live OAuth credential) were removed at the end of that session, same as the main experiment.
