# A merge cuts the release, and every release publishes both variants

Issue #75 showed that a change to `images/dev` could not reach the agent runtime in one release: the agent image's base pin moved only via Renovate, one tag late, so `0.0.6-agent` shipped without the non-root user that `0.0.6-dev` carried, and nothing reported the gap.
The root cause was treating `images/agent` as the agent image's only input: `images/dev` is an input too, and the release flow, the change-detection script, and the PR path filter all ignored it.

We decided that merging to `main` cuts the release, with no manual tag: release-please maintains a release PR from Conventional Commits, and merging that PR creates the version, updates every pin, and publishes.
Publishing happens in the same workflow run, in jobs gated on release-please's `release_created` output, dev before agent, so the agent image is always built on the dev image published at that same version.
This works with the default `GITHUB_TOKEN` precisely because the publish jobs do not depend on the pushed tag triggering anything: GitHub suppresses workflow runs for events the `GITHUB_TOKEN` itself triggers (verified against GitHub's own documentation source), which rules out the tag-triggers-publish design rather than merely disfavouring it.

Every release publishes both variants, unconditionally.
`.github/scripts/changed-since-last-tag.sh` and the skip-if-unchanged rule are deleted, which retires ADR-0004's "a version tag no longer guarantees every variant was published at that version" caveat: from this ADR on, `X-dev` and `X-agent` both exist for every `X`, and `X-agent` is built on `X-dev`.
The occasional identical republish this allows is the price of a tag meaning one thing again.

## The pin mechanism

Both committed pins stay versioned, literal, and greppable, but split the version from the variant suffix so release-please's `generic` updater can rewrite them:

```dockerfile
# x-release-please-start-version
ARG BASE_VERSION=0.0.9
# x-release-please-end
FROM ghcr.io/afrossard/container-base:${BASE_VERSION}-dev
```

```bash
version="0.0.9" # x-release-please-version
image="ghcr.io/afrossard/container-base:${version}-agent"
```

The split is forced, not stylistic, and both halves were verified by driving the real tools rather than assumed:

- release-please's version regex treats `-dev`/`-agent` on the same line as a semver prerelease and swallows it, rewriting `0.0.9-dev` to `0.1.0`; with the version on its own line the suffix is untouched.
- Dockerfile syntax rejects an inline `#` comment on a `FROM` line, so the block-marker form is the only one available there anyway.
- The devcontainer CLI (0.88.0) carries an `ARG` default through a build with features applied, with no `build.args` plumbing and nothing passed at build time; the committed default is the only truth.

This is not the build-arg parameterisation issue #75 floated as option A.
No value is injected at build time by CI or anyone else, so the reviewability objection there - the committed file not stating what CI built - does not apply.

## Considered options

**Renovate keeps owning the pins** (the status quo, and issue #75's options B and C) was rejected because it is structurally one release late: Renovate can only bump to a published tag, so the pin always trails by at least one tag and a PR merge.
Tested, not assumed: on an `ARG`-interpolated `FROM`, Renovate's dockerfile manager extracts the dependency but its auto-replace silently writes nothing, so the interaction is worse than late - it is a no-op that looks like automation.
The `renovate.json` custom manager for the launcher pin is removed; release-please owns both pins now.

**Moving `:dev` and `:agent` tags** would have made the pins vanish entirely, but ADR-0004 already rejected moving bases because a pinned build must be able to answer what was shipped, and nothing here weakens that.

**A repo skill instead of CI automation** was the agreed fallback if the workflow grew too complicated.
It stayed at one workflow and one config file, both using documented release-please features, so the fallback was not taken.

## Consequences

- **Conventional Commits become mandatory.** The commit type is what computes the version bump. `CONTRIBUTING.md` records the convention for humans; `AGENTS.md` points to it.
- **The version number is explicitly a build counter with semver semantics**, computed from commit types, not a hand-chosen statement. The repo's nine hand-cut tags were already this in practice.
- **`publish-dev-image.yml` and `publish-agent-image.yml` collapse into one release workflow.** The `on: push: tags` trigger goes away, and with it the cut-a-tag-by-hand republish escape hatch; a `workflow_dispatch` trigger on the release workflow is the replacement lever.
- **PR CI must build the cascade too.** The release PR bumps the pin to a version whose `-dev` tag does not exist until merge, so `agent-image.yml` cannot pull the pinned base; instead it builds the dev image from the same commit, retags it locally as the pinned base, then builds the agent image on it. This also closes the gap where a PR touching only `images/dev` never built the agent image at all - the same missed-input root cause as the release bug, fixed the same way: `images/dev/**` joins `agent-image.yml`'s path filter.
- **release-please owns `CHANGELOG.md`**, which stays auto-generated and never hand-edited.
- **Renovate's remit shrinks to true third-party dependencies** (base images, features, npm dev tooling). Pins that this repo's own release moves are no longer its business.
- **ADR-0004 is amended, not superseded**: the tag scheme, the single GHCR package, and the version-as-prefix arguments all stand; only the skip-if-unchanged consequence is retired.
