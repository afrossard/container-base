# AGENTS.md

## Status

No Containerfile or CI yet as of 2026-07-23 — only the domain docs (`CONTEXT.md`, `docs/adr/`) exist so far.

## Known consumers pending migration

These repos currently build FROM upstream images directly and hand-roll the setup this repo now owns. Once `python-dev`/`python-prod` (or the relevant tags) are published, migrate each to `FROM ghcr.io/afrossard/container-base:<tag>`:

- **`default-vscode-project`** — `Containerfile` (FROM `python:3.14-slim-trixie`) and `.devcontainer/Containerfile` (FROM `mcr.microsoft.com/devcontainers/python:3-trixie`, hand-rolled Homebrew/chezmoi bootstrap to drop once `python-dev` covers it).
- **`homelab-kube`, `homelab-etl`, `homelab-fun`, `actual-budget-transformer`** — the four sibling repos named in dotfiles ADR-0001 as the source of the devcontainer drift this repo exists to fix.

## Agent skills

### Issue tracker

Issues live as GitHub issues in `afrossard/container-base`, driven by the `gh` CLI.
See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, each label string equal to its name.
See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root.
See `docs/agents/domain.md`.
