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
`{version}-{variant}`, where variant is `dev` or `{language variant}-prod`.
For example `1.4.2-dev`, `1.4.2-base-prod`, `1.4.2-python-prod`.

**Consumer**:
A repo whose devcontainer or production Containerfile builds FROM one of these images.

**Dotfiles bootstrap**:
Applying the user's chezmoi-managed configuration to a container after it starts.
This repo publishes the tools that make it possible and never carries the configuration itself, which belongs to `dotfiles`.
