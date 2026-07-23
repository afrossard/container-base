# This repo holds shared container images only

Every new project's devcontainer and production Containerfile duplicated the same OS/shell setup and drifted — the same problem dotfiles' ADR-0001 (`0001-dotfiles-repo-holds-config-only.md`) already carved out of that repo, naming a shared devcontainer base image as the fix and giving it its own repo.

`default-vscode-project`, the template used to start new projects, was proposed as the home for that base image instead. Rejected: a repo's scope is bounded by its name, and that repo is a Python-specific project template (`pyproject.toml`, `uv`, a `my_default_project` entrypoint), not a base image. A non-Python project seeded from it would have to inherit or strip Python-specific tooling to reach the shared OS/shell layer underneath.

## Consequences

- Language-specific tooling (Python via `uv`, and future languages) lives here as an independent layer per language, not baked into a Python-flavored default template.
- `default-vscode-project` and sibling repos (`homelab-kube`, `homelab-etl`, `homelab-fun`, `actual-budget-transformer`) become consumers: their own Containerfiles build `FROM ghcr.io/afrossard/container-base:<tag>` instead of an upstream OS image. Migrating them is separate, per-repo work, not part of standing this repo up.
