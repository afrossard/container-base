# The shell/dotfiles layer is dev-only, not published on prod images

dotfiles' ADR-0005 (`0005-ephemeral-targets-bootstrap-themselves.md`) already scopes chezmoi to targets that need a user's config applied: devcontainers, and non-devcontainer agent runtimes such as `actual-budget-transformer`'s `claude` compose service. It does not apply chezmoi to every container. This repo carries that same scoping into the build-variant split: only `dev` images install zsh, `chsh`, Homebrew, chezmoi, and fpath completions; `prod` images are the base stage plus a language runtime and nothing else.

## Consequences

- Deployed workloads get a smaller image with no shell tooling or personal dotfiles baked in, since they never run interactively and never need a user's config.
- A container that needs the dotfiles layer despite being a production deployment — the `claude` service is the known case — builds from a `dev` tag, not a `prod` one. The split tracks whether dotfiles are needed, not whether the container is "production."
