# Contributing

## Commit messages: Conventional Commits

Every commit that lands on `main` must follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
Releases are cut automatically by release-please (ADR-0018), and the commit type is what computes the version bump, so this is load-bearing, not cosmetic.

This repo squash-merges pull requests, so **the PR title becomes the commit message** - write the PR title in the same format.
That only happens because docs/agents/issue-tracker.md's merge convention passes the PR title explicitly via `--subject`; GitHub's own squash-merge default silently drops it for any single-commit PR.

| Type                                              | Effect on the next release |
| ------------------------------------------------- | -------------------------- |
| `fix:`                                            | patch bump                 |
| `feat:`                                           | minor bump                 |
| `feat!:`, `fix!:`, or a `BREAKING CHANGE:` footer | major bump                 |
| `chore:`, `docs:`, `ci:`, `test:`, `refactor:`    | no release                 |

Examples:

```
fix: hold the docker engine against in-session apt upgrades
feat: add --memory passthrough to launch-agent-runtime
docs: record ADR-0018
```

A scope is optional (`fix(agent): ...`) and this repo does not enforce a scope vocabulary.

## Releases

There is no manual release step.
Merging a release-please PR publishes both image variants at the new version; see ADR-0018 for the full flow.

## Renovate PRs and releases

Renovate opens PRs for third-party dependency bumps; `renovate.json` sets `semanticCommits: "enabled"` and titles them accordingly, but only some of them should release.

A **shipped dependency** (CONTEXT.md) is a third-party artifact baked into a published image - concretely, everything Renovate manages under `images/**`.
Bumping one changes what a consumer pulls, so it computes a release automatically: `fix(deps): ...` for a patch/minor bump, `feat(deps): ...` for a major, as the automated floor.
Everything else Renovate touches - GitHub Actions, npm tooling, the `.devcontainer` dogfood pin - titles as `chore(deps): ...`: no release, correctly, because none of it ships.

Renovate reverts a hand-edited PR title back to its own generated one the next time it touches the branch, so an escalation never happens by editing the PR title.
It happens in the squash commit subject at merge time instead - Renovate can never emit a breaking marker itself (Conventional Commits puts `!` between scope and colon; `semanticCommitType` is only the bare type word).

**Merge procedure**, for a human or an agent asked to review and merge a Renovate PR:

1. Green CI and a `chore(deps)`, or a non-major `fix(deps)`/`feat(deps)`: merge with the generated title, as-is.
2. Green CI and a shipped-dependency (`images/**`) **major**: read the diff and judge whether it's actually breaking for a consumer - a changed default, a removed flag a consumer script relies on - not just "the version number jumped." Not breaking: merge as-is. Breaking: don't merge on the generated title; rewrite the squash commit subject to `fix(deps)!: ...`/`feat(deps)!: ...` (or add a `BREAKING CHANGE:` footer) describing what breaks, via `gh pr merge --subject`.
3. Red or pending CI: leave it open, do nothing further.

**Agent autonomy boundary**: merge `fix`/`feat`/`chore` verdicts on green CI without asking.
A shipped-dependency major judged breaking is a stop-and-present-evidence case, not an autonomous merge, regardless of CI status - present the diff, the reasoning, and the PR link, and wait for the operator.

`/merge-renovate-prs` runs this procedure end to end.
