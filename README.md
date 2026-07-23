# container-base

Shared container base images, published to `ghcr.io/afrossard/container-base`.

Two kinds of image, tagged `{version}-{variant}`:

- **Dev image** (`1.4.2-dev`) - one image, every language toolchain, plus the dev layer: zsh, Homebrew, chezmoi, starship. What a devcontainer builds on.
- **Runtime base** (`1.4.2-base-prod`, `1.4.2-python-prod`) - minimal, one language runtime, no dev layer. What a deployable artifact builds on.

There is no `python-dev`. The dev image carries every language, so there is nothing to choose between.

No language runtime is baked: `uv` resolves Python and `mise` resolves everything else, from the version each project declares.

Pin a version and let Renovate bump it.

See [`CONTEXT.md`](./CONTEXT.md) for the glossary and [`docs/adr/`](./docs/adr/) for why it's shaped this way.
