# AGENTS.md

Publishes shared container base images (dev, agent, and per-language runtime-base variants) consumed by other repos' devcontainers and production Containerfiles.

## Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root.
Read these before exploring the codebase.
See `docs/agents/domain.md`.

## Issue tracker

Issues live as GitHub issues in `afrossard/container-base`, driven by the `gh` CLI.
See `docs/agents/issue-tracker.md`.

## Triage labels

The five canonical triage roles, each label string equal to its name.
See `docs/agents/triage-labels.md`.

## Commands

- `npm run build:dev` / `npm run test:dev` - build and test the dev image.
- `npm run build:agent` / `npm run test:agent` - build and test the agent image.
- `npm run test:launcher` / `npm run test:scripts` - test the host-side launcher and shared scripts.
- `npm run format:check` - required before every commit.

## Commit messages

Conventional Commits are mandatory - the commit type computes the release version bump (ADR-0018).
See `CONTRIBUTING.md`; since PRs squash-merge, the PR title is what must conform.

## Operational gotchas

Recurring failure modes specific to working in this repo as an agent.
See `docs/agents/gotchas.md`.

## Known consumers pending migration

Repos still hand-rolling the setup this repo now owns.
See `docs/agents/known-consumers.md`.
