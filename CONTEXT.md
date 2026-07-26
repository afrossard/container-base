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

**Reference profile**:
This repo's own `.devcontainer/devcontainer.json`, maintained as the dev image's first consumer and the dogfooding test for it.
It is a recipe for reproducing a dev environment a trusted human works in, not a security boundary; the controls that contain an autonomous agent live in the agent runtime instead (ADR-0013).
_Avoid_: hardened image - what hardening a consumer wants is launch-time configuration it composes, not a separate published image (ADR-0011).

**Agent runtime**:
The disposable virtual machine an autonomous agent executes inside and cannot leave, holding one repo and its own docker daemon and nothing else.
One exists per agent session, and the repo is its boundary (ADR-0013).
_Avoid_: agent sandbox, agent container - the first is the agent CLI's own in-process confinement (mechanism 7 of the issue #16 survey), a layer inside the runtime; the second denies the hypervisor boundary that is the whole point.

**Agent image**:
The published `{version}-agent` image (`images/agent/`): the dev image plus a docker daemon of its own and an entrypoint that starts it before handing off to the launcher's command, no dev layer added.
It is the artifact a per-container-VM tool boots directly as a VM guest (ADR-0014); the running guest is the agent runtime, not this image.
_Avoid_: agent runtime - that names the running VM this image becomes once launched, not the artifact GHCR holds.

**Launcher**:
`scripts/launch-agent-runtime`, the host-side script that boots the agent image as a microsandbox guest: a disk-backed volume for `/var/lib/docker` (msb's default nests overlayfs on overlayfs, which fails a real build), `--secret` credential injection, and a repo-derived session name that reuses (replaces) its own prior sandbox.
The image itself still has no default command; the launcher supplies its own - an interactive shell with a real tty - when none is given, so a bare invocation behaves like `docker run -it` rather than erroring.
It also composes everything a session needs that the image deliberately does not carry: the workspace clone, the `dotfiles-bootstrap` run that applies the operator's conventions (ADR-0016), and the repository-scoped credential the session pushes with (ADR-0015).
`scripts/cleanup-agent-sessions` removes stopped sessions and their volumes.
Both are host-side tooling, not container images - a narrow, documented exception to this repo's image-only scope (ADR-0001, ADR-0014).

**Agent session**:
One unit of autonomous agent work, bounded by the lifetime of the agent runtime it runs in.
Disposing of the runtime ends the session and everything it accumulated, apart from what was pushed to the remote.

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
