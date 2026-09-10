# The agent runtime is long-lived and reset on demand

ADR-0013 made the agent runtime disposable: one VM per unit of work, destroyed when the work ends.
The firstmate tryout (issue #100) exposed what that costs a workflow stack that is built to accumulate: tooling, model-policy configuration, captain preferences, and learned memory all died with every launch, and firstmate's own "restart-proof" design assumes disk survival the disposable model refused to grant.
The launcher was the only thing enforcing disposability - it ran `msb run --replace` unconditionally - while microsandbox itself keeps a stopped sandbox's filesystem intact across `msb stop`/`msb start`, verified by direct experiment in this session rather than assumed.

**Decision: the agent runtime is a pet, managed like a devcontainer.**
A bare `launch-agent-runtime` attaches to the repo's existing runtime, resumes it if stopped, and creates one only if none exists.
Destruction happens only through an explicit, confirmed reset flag, and a reset kills everything: runtime tooling, configuration, firstmate's learned memory, and unpushed work alike - ADR-0015's leave-as-a-pushed-branch discipline is the protection for work that matters.
Re-provisioning after a reset is owned by tooling recipes under `tooling/`: fixed, reviewable configuration files applied by a provisioning skill rather than a fixed script, so an agent adapts to upstream drift (renamed repos, moved config locations, version-pin lag - all observed in #100) instead of crashing into it.
The runtime stays repo-scoped, one per repo by default, with parallel runtimes still available through explicit naming.

## Considered options

- **Disposable runtime plus enumerated persistent volumes.** Doctrinally cleanest, but tool state spans at least three filesystem roots (the Homebrew cellar, the mise data dir, `~/.local`), so the mount list grows without bound and every missed sibling path silently loses state - the exact lesson `docs/research/0022-vm-tool-experiment-results.md` recorded about `~/.claude.json`.
- **Baking the workflow stack into the `-agent` image.** Rejected on the glossary's own clause: runtime tooling is never baked because its update cadence outruns image releases. Firstmate's pinned installers already lag Homebrew for every tool in the family, baking would add a third, slower cadence, two of the tools install by `curl | sh` and would become shipped dependencies Renovate cannot see, and every `-agent` consumer would carry one operator's stack.
- **A personal firstmate fork carrying config and provisioning.** Rejected as too heavy for a handful of config files; the same files live in `tooling/` here instead, a documented scope exception like the launcher.

## Consequences

- **A runtime only picks up a newer published image at reset.** Image freshness and runtime longevity now trade off explicitly, and the operator owns the hygiene of long-lived runtimes; `cleanup-agent-sessions` no longer treats a bare invocation as "sweep every stopped sandbox for this repo" - it lists by default and removes only what an explicit `--name` or `--all` selects, because a stopped pet is a normal parked state, not litter.
- **A resume restores the machine and its disk, nothing more.** `msb start` re-runs neither the image entrypoint, nor the OCI command, nor any registered boot script - verified on issue #144, correcting this ADR's originally published claim that resuming boots the runtime again (only filesystem survival had actually been tested). Convergence is therefore owned by one idempotent bring-up script carried by the agent image: start the docker daemon if it is down, run the dotfiles bootstrap, ensure the workspace clone. The entrypoint runs it on first boot and the launcher ensures it runs on every attach, staying agnostic of its logic - the devcontainer post-start shape. Baking this script does not touch the never-bake rule, which is about runtime tooling; this is image infrastructure, the entrypoint's sibling.
- **The launch-time credential machinery loses its purpose** - retired separately in ADR-0022.
- **ADR-0013 is amended, not overturned.** Its boundary reasoning stands unchanged: the hypervisor still contains the agent, the repo is still the boundary, and nothing is shared with the host checkout. What this ADR revises is its consequence "the reusable part is a prebuilt image, not a provisioning script and not a persistent data volume" - the runtime's own disk is now the persistent state, accepted knowingly because per-launch freshness, not containment, is what it spends.
- **The glossary's "session tooling" is renamed "runtime tooling"**, and "agent session" decouples from the runtime lifecycle entirely: a session is one agent's engagement, and a runtime hosts many.
- **Verified: filesystem survival across `msb stop`/`msb start`**, that `docker-init.sh` is safely re-runnable, and that `--env` values set at `msb run` reach later `msb exec` sessions (all on issue #144). Survival across a host reboot is expected (the state is on disk) but not yet observed; it is a manual check recorded on the implementation issue rather than a blocker.
