# container-base

Shared container base images, published to `ghcr.io/afrossard/container-base`.

Each image is tagged `{language variant}-{build variant}`:

- **Language variant**: `base` (no language), `python`, and more as they're added.
- **Build variant**: `dev` (zsh, Homebrew, chezmoi, shell completions) or `prod` (just the OS and the language runtime).

See [`CONTEXT.md`](./CONTEXT.md) for the glossary and [`docs/adr/`](./docs/adr/) for why it's shaped this way.
