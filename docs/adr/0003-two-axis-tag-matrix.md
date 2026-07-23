# Every language-variant × build-variant combination is published independently

> **Status: partly superseded by ADR-0004.**
> The tag matrix and the language axis for `dev` are superseded; there is now one dev image and no `{language}-dev` tag.
> The GHCR choice and the Debian-family constraint below still stand, though ADR-0006 revisits what keeps Homebrew there.

Images are tagged `{language variant}-{build variant}`: `base-dev`, `base-prod`, `python-dev`, `python-prod`, and so on as languages are added. `base-dev` and `base-prod` are published in their own right rather than kept as internal Containerfile stages, so a project that needs the shell/dotfiles layer or a lean OS image but no specific language — `homelab-provisioner-toolbox` is the known case — can pull them directly instead of waiting for a language variant that happens to fit.

Images build on Debian slim (trixie), matching the OS family this template repo and its devcontainer already pin, and publish to GHCR (`ghcr.io/afrossard/container-base`) alongside the repo itself, with no separate registry account to manage.

## Consequences

- Adding a language means adding one `-dev`/`-prod` pair off the existing `base-dev`/`base-prod` stages, not a new axis.
- Homebrew requires glibc, which rules out Alpine; the OS choice stays Debian-family for as long as Homebrew is part of the dev layer.
