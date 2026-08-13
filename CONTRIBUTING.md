# Contributing

## Commit messages: Conventional Commits

Every commit that lands on `main` must follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
Releases are cut automatically by release-please (ADR-0018), and the commit type is what computes the version bump, so this is load-bearing, not cosmetic.

This repo squash-merges pull requests, so **the PR title becomes the commit message** - write the PR title in the same format.

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
