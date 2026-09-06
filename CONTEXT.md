# Context

Glossary for this repo, which publishes shared container base images consumed by other repos' devcontainers and production Containerfiles.

## Language

**Dev image**:
The single image carrying every language toolchain together with the dev layer.
Exactly one exists, whatever languages a consumer uses.
_Avoid_: devcontainer image, base-dev - the first conflates the image with one kind of consumer, since a dev image can be used by something that is not a devcontainer; the second implies a language axis the dev image does not have.

**Runtime base**:
A minimal image carrying one language runtime and no dev layer, built on to produce a deployable artifact.
One exists per language variant.
_Avoid_: production image - a runtime base is not always literally a production deployment, and the distinction that matters is the absence of the dev layer.

**Dev layer**:
The tooling that makes an image habitable by a person or an agent: zsh, Homebrew, chezmoi, starship.
It is what the dev image has and every runtime base lacks.
_Avoid_: shell layer, dotfiles layer - both name a part for the whole.

**Language variant**:
Which language runtime a runtime base carries: `base` for none, or a specific language such as `python`.
It qualifies runtime bases only.
The dev image carries every language and therefore has no variant.

**Language manager**:
The tool that owns a language's runtime and resolves which version a project gets.
No language runtime is carried at a fixed version; a manager fetches what a project asks for.

**Image tag**:
`{version}-{variant}`, where variant is `dev`, `agent`, or `{language variant}-prod`.
For example `1.4.2-dev`, `1.4.2-agent`, `1.4.2-base-prod`, `1.4.2-python-prod`.

**Consumer**:
A repo whose devcontainer or production Containerfile builds FROM one of these images.

**Shipped dependency**:
A third-party artifact baked into a published image, so bumping it changes what consumers pull.
Dependencies that serve only this repo's own build or CI are not shipped dependencies, and their bumps change nothing consumers observe.
_Avoid_: runtime dependency - nothing here runs at consumer runtime; the distinction is what ships, not what runs.

**Host prerequisite**:
A tool the operator installs on their own machine so this repo's host-side scripts run: `msb` and `git`, and nothing else.
Not a shipped dependency: no image carries it and no `npm ci` supplies it.
The bar is higher than for a dev image tool, since it is a manual install on a machine this repo cannot clean up.
_Avoid_: host dependency - "dependency" reads as something a tool resolves for you, and this is the opposite.

**Reference profile**:
This repo's own `.devcontainer/devcontainer.json`, maintained as the dev image's first consumer and the dogfooding test for it.
It is a recipe for reproducing a dev environment a trusted human works in, not a security boundary; the controls that contain an autonomous agent live in the agent runtime instead (ADR-0013).
_Avoid_: hardened image - what hardening a consumer wants is launch-time configuration it composes, not a separate published image (ADR-0011).

**Agent runtime**:
The long-lived virtual machine an autonomous agent executes inside and cannot leave, holding one repo and its own docker daemon and nothing else.
One exists per repo and hosts many agent sessions over its life; the repo is its boundary, stopping it merely pauses it, and only a reset ends it (ADR-0013, ADR-0021).
_Avoid_: agent sandbox, agent container - the first is the agent CLI's own in-process confinement (mechanism 7 of the issue #16 survey), a layer inside the runtime; the second denies the hypervisor boundary that is the whole point.

**Reset**:
Deliberately destroying an agent runtime and everything it accumulated: tooling, configuration, memory, and unpushed work alike (ADR-0021).
It is always an explicit, confirmed act, never a launch's default behaviour.

**Agent image**:
The published `{version}-agent` image (`images/agent/`): the dev image plus a docker daemon of its own and an entrypoint that starts it before handing off to the launcher's command, no dev layer added.
It is the artifact a per-container-VM tool boots directly as a VM guest (ADR-0014); the running guest is the agent runtime, not this image.
_Avoid_: agent runtime - that names the running VM this image becomes once launched, not the artifact GHCR holds.

**Launcher**:
`scripts/launch-agent-runtime`, the host-side script that owns the agent runtime's lifecycle: by default it attaches to the repo's existing runtime, resuming it if stopped and creating it only if absent, and it resets one only on an explicit, confirmed flag (ADR-0021).
It composes what the image deliberately does not carry: the disk-backed `/var/lib/docker` volume (msb's default nests overlayfs on overlayfs, which fails a real build), the workspace clone, and the `dotfiles-bootstrap` run (ADR-0016).
When given no command it supplies an interactive shell with a real tty, so a bare invocation behaves like opening a devcontainer.
`scripts/cleanup-agent-sessions` removes only what it is explicitly told to - under ADR-0021 a stopped runtime is a normal state, not litter.
Both are host-side tooling, not images - a narrow, documented exception to this repo's image-only scope (ADR-0001, ADR-0014).

**Agent session**:
One agent's continuous engagement, wherever it runs: on the host, inside an agent runtime, or spawned by another agent.
Its lifetime is uncorrelated with any runtime's - a runtime hosts many sessions, concurrent and successive, over its life (ADR-0021).

**Runtime tooling**:
The tools installed inside an agent runtime for its workflows, at the runtime's cadence rather than the image's.
It is never baked, because its update cadence outruns image releases; the image carries only what is stable across runtimes, and a reset removes it until a tooling recipe reapplies it.
_Avoid_: session tooling - the former name, from when tooling died with a session (ADR-0021); agent tooling - too easily read as the tooling that runs the agent (the image, the launcher).

**Tooling recipe**:
The versioned configuration files and provisioning skill that make a freshly created agent runtime ready for one workflow stack, applied by an agent rather than a fixed script so upstream drift is adapted to instead of crashed into.
`tooling/` holds them, a documented exception to this repo's image-only scope, like the launcher (ADR-0001, ADR-0021).

**Workspace**:
The clone of one repo an agent session works in, made inside the agent runtime at launch and destroyed with it.
It enters as a full clone and leaves as a pushed branch, sharing nothing with the operator's own checkout (ADR-0015).
_Avoid_: checkout, mount - the first names the human's copy on the host, the second names a mechanism this repo rejected because a writable shared path is a channel out of the runtime.

**Isolation substrate**:
The hypervisor the agent runtime runs as a virtual machine on - the boundary that actually contains an escape.
Every control inside the runtime is defence-in-depth rather than the boundary, because the agent holds root and the docker socket there by design (ADR-0013).
_Avoid_: sandbox - that names the agent CLI's own syscall/filesystem confinement (bubblewrap, seccomp, Seatbelt), a different layer running inside the runtime, not the boundary underneath it.

**Dotfiles bootstrap**:
Applying the user's chezmoi-managed configuration to a container after it starts.
This repo publishes the tools that make it possible and never carries the configuration itself, which belongs to `dotfiles`.
