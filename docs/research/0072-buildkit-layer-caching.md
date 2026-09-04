# BuildKit layer caching for the image builds

Research for [issue #72](https://github.com/afrossard/container-base/issues/72), which asks whether to wire `--cache-from`/`--cache-to` into `build:dev`/`build:agent`/`publish:dev`/`publish:agent` or explicitly stay with a full rebuild every time.

## What this settles

**Recommendation: stay as-is. Do not add layer caching to any of the four builds.**

The case for caching is a wall-clock and Actions-minutes argument, and for this repo one side of that is already zero.
This repo is public, so GitHub Actions minutes are unmetered and free: every run sampled below reports `billable.total_ms: 0`.
A GHCR registry cache is likewise free to store and serve for a public package.
So caching cannot save money here - it can only save latency, and it can only do that in two narrow situations, one of which ([ADR-0018](../adr/0018-a-merge-cuts-the-release-and-publishes-both-variants.md)'s occasional identical republish) is a cost that ADR already weighed and accepted on purpose.

Against that thin, latency-only upside sits a real cost: full-rebuild-every-time is a correctness property for a base image other repos build on, not an incidental inefficiency.
The dev image resolves at least six independent unpinned upstreams on every build (four `apt-get update` transactions, a Homebrew `HEAD` installer, `chezmoi`'s `get.chezmoi.io` script, plus `common-utils`' `upgradePackages`), none of which has a lockfile.
Today each release captures those at their current, security-patched state.
A layer cache freezes them until something above them in the Containerfile changes, and nothing in the pipeline - no lockfile, no SBOM diff - would surface that a `0.5.0-dev` had shipped an apt set built at `0.3.0`'s date.

The issue was filed 26 days before this research and its investigation points 3 and 5 rest on repo state that [ADR-0018](../adr/0018-a-merge-cuts-the-release-and-publishes-both-variants.md) has since changed.
`.github/scripts/changed-since-last-tag.sh` and the skip-if-unchanged rule **no longer exist** (deleted in [#86](https://github.com/afrossard/container-base/pull/86)); `publish-dev-image.yml`/`publish-agent-image.yml` have collapsed into one `release.yml`.
Point 5's "do caching and the skip-unchanged check fight each other" is therefore moot - there is no skip-unchanged check to fight - but the underlying question is still answered below.

## Method

No real image build ran for this research.
This host has 4 CPUs and ~3.8 GB RAM and no reliable buildx, and issue #72 itself anticipated that, so the evidence base is the same shape as the issue's own (which grepped a CI log for `CACHED`):

- The workflow files under `.github/workflows/` (`dev-image.yml`, `agent-image.yml`, `release.yml`) and the composite `.github/actions/setup/action.yml`.
- Real GitHub Actions run logs and per-step timings, pulled via `gh api repos/afrossard/container-base/actions/runs/<id>/jobs` and `.../timing`, for PR builds and for the last three releases that actually published (`0.3.1`, `0.4.0`, `0.4.1`).
- `package.json`'s `build:*`/`publish:*` scripts, `images/dev/Containerfile`, `images/agent/Containerfile`, both `devcontainer.json` files, `images/dev/mise/config.toml`, and `.github/scripts/tag-agent-base.sh`.
- ADRs [0003](../adr/0003-two-axis-tag-matrix.md), [0004](../adr/0004-one-dev-image-and-an-asymmetric-tag-scheme.md), [0006](../adr/0006-language-managers-not-baked-runtimes.md), [0008](../adr/0008-mise-installs-system-wide.md), [0014](../adr/0014-the-agent-runtime-is-a-published-image-variant.md), [0018](../adr/0018-a-merge-cuts-the-release-and-publishes-both-variants.md), [0020](../adr/0020-the-dev-image-bakes-a-default-node-via-mise.md); `CONTEXT.md`; `CONTRIBUTING.md`; `docs/agents/gotchas.md`.
- The bundled `@devcontainers/cli` 0.89.0: `devcontainer build --help`, and its compiled source (`dist/spec-node/devContainersSpecCLI.js`) for how it passes `--cache-from`/`--cache-to` and `BUILDKIT_INLINE_CACHE` through to buildx.

Every number below that was read off a real run is stated as measured.
Everything else - what a cache hit would save, whether a backend caches both platforms - is marked **confidence: low** or **medium** and says why it could not be measured here.

## What the four builds actually do today

`package.json`:

| script          | command shape                                                                                 |
| --------------- | --------------------------------------------------------------------------------------------- |
| `build:dev`     | `devcontainer build --config images/dev/devcontainer.json --frozen-lockfile --image-name …`   |
| `build:agent`   | `devcontainer build --config images/agent/devcontainer.json --frozen-lockfile --image-name …` |
| `publish:dev`   | `build:dev` + `--platform linux/amd64,linux/arm64 --push`                                     |
| `publish:agent` | `build:agent` + `--platform linux/amd64,linux/arm64 --push`                                   |

None passes `--cache-from`, `--cache-to`, or `--no-cache`.
Neither `devcontainer.json` sets `build.cacheFrom`.
The only `cache:` anywhere in CI is `setup-node`'s npm cache in the composite setup action, unrelated to Docker layers.

**PR path (`dev-image.yml`, `agent-image.yml`).**
Both trigger on `pull_request` touching `images/dev/**` (and `agent-image.yml` also `images/agent/**`), `package.json`, `package-lock.json`, the workflow file, or `.github/actions/setup/**`.
`dev-image.yml` runs `build:dev` then `test:dev`.
`agent-image.yml` runs `build:dev`, then `tag:agent-base` (retags the just-built dev image as the version-pinned base `images/agent/Containerfile` pins, per ADR-0018), then `build:agent`, then `test:agent`.
Neither runs `docker/setup-buildx-action`; the plain docker driver builds single-arch and loads locally.

**Release path (`release.yml`, `push` to `main`).**
`release-please` maintains a release PR; merging it sets `release_created`, which gates `publish-dev` then `publish-agent` (serial, dev first so agent builds on the dev image published at the same version).
Both publish jobs run `setup-qemu-action` + `setup-buildx-action` (so the `docker-container` driver, multi-arch capable), `login-action`, then `publish:*` and a `verify:*` bats check.
ADR-0018: **every release publishes both variants unconditionally**, even if that variant's own directory did not change since the last release.

## Point 1 - time and cost savings

### Measured build times

PR build, `dev image` job, run `33841526793` (per-step `timing` API):

| step                                 | duration                                |
| ------------------------------------ | --------------------------------------- |
| `./.github/actions/setup` (`npm ci`) | **5 min 4 s** (npm cache miss this run) |
| `npm run build:dev`                  | **1 min 13 s**                          |
| `npm run test:dev`                   | 16 s                                    |
| whole job                            | 6 min 39 s                              |

PR build, `agent image` job, run `33841526722`, same commit:

| step                                 | duration            |
| ------------------------------------ | ------------------- |
| `./.github/actions/setup` (`npm ci`) | 6 s (npm cache hit) |
| `npm run build:dev`                  | **1 min 10 s**      |
| `npm run tag:agent-base`             | <1 s                |
| `npm run build:agent`                | **20 s**            |
| `npm run test:agent`                 | 21 s                |
| whole job                            | ~2 min              |

Multi-arch publish, last three real releases (`publish:*` step only, from the `jobs` API):

| release                     | `publish:dev` (amd64+arm64, QEMU, push) | `publish:agent` | whole `release.yml` run |
| --------------------------- | --------------------------------------- | --------------- | ----------------------- |
| `0.3.1` (run `33322586540`) | **7 min 39 s**                          | 4 min 16 s      | ~13 min                 |
| `0.4.0` (run `33383652430`) | **11 min 45 s**                         | 4 min 10 s      | ~17 min                 |
| `0.4.1` (run `33669504719`) | **11 min 51 s**                         | 4 min 3 s       | ~17 min                 |

So: the cold dev image build is **~70-75 s single-arch** and **~8-12 min multi-arch** (the arm64 QEMU emulation is roughly 8-10x the native cost and dominates the release run).
The agent image adds only `tini` + an entrypoint on top of the dev image: **~20 s single-arch, ~4 min multi-arch**.

### Cost

**GitHub Actions minutes: free, and not a variable here.**
The repo is public (`gh api repos/afrossard/container-base` → `"visibility": "public"`).
`GET .../runs/<id>/timing` returns `"billable": {"UBUNTU": {"total_ms": 0, …}}` for every run sampled - PR and release alike.
Public repositories get unlimited standard-runner minutes at no charge, so the dollar cost of every build above is **$0**, and caching cannot reduce $0.

**GHCR storage for a registry cache: also free.**
A `type=registry` cache image in a public GHCR package incurs no storage or egress billing for this account.
Confidence: medium - GitHub does not meter storage/bandwidth for public packages per its published billing docs; not independently invoiced-checked here.

**So the only currency caching can save is wall-clock latency**, plus a courtesy/carbon argument for not re-running ~10 min of QEMU emulation when the inputs are byte-identical.
Nobody is currently blocked on either: PR image CI is ~2-7 min (and the 5-min outlier is `npm ci`, not the image - see below), and release-please already decouples "merge the change" from "wait for publish," so a 17-min release run blocks no author.

### Where a cache would and would not hit, given the Containerfile

`images/dev/Containerfile` instruction order (the layers a cache is keyed on):

1. `FROM debian:trixie-slim` - tag, not digest
2. `COPY --from=ghcr.io/astral-sh/uv:0.12.9` - Renovate-pinned
3. `COPY mise/config.toml` - Node major pin (`24`), Renovate-tracked (ADR-0020)
4. `RUN apt-get update … && … mise && … mise install` - unpinned apt (ca-certificates, curl, extrepo, git, sudo, zsh, mise); network-heavy
5. `RUN` sudoers/zshenv edits
6. `RUN` Homebrew installer from `HEAD` + `brew install dive starship` - unpinned; network-heavy
7. `RUN curl get.chezmoi.io | sh` - unpinned
8. `COPY dotfiles-bootstrap` + `chmod`
9. `RUN apt-get update … bubblewrap gh gnupg vim` - unpinned
10. `RUN` add Claude Code apt repo + `apt-get install claude-code` - unpinned, `stable` channel
11. `USER vscode`

BuildKit invalidates the changed layer and everything below it.
Crossed against what actually triggers a build:

| trigger                                                                            | first busted layer  | cache value                                                                                                                                                                                                                         |
| ---------------------------------------------------------------------------------- | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `uv` bump (`fix(deps)`, Renovate)                                                  | 2                   | ~none - near-total rebuild                                                                                                                                                                                                          |
| Node major bump (Renovate, ADR-0020)                                               | 3                   | trivial - near-total rebuild                                                                                                                                                                                                        |
| `debian:trixie-slim` digest move (Renovate)                                        | 1                   | none - total rebuild                                                                                                                                                                                                                |
| `common-utils` feature bump                                                        | early wrapper layer | ~none (confidence: medium - the CLI generates a wrapper Dockerfile per feature set; a feature-version change alters it early)                                                                                                       |
| Containerfile edit adding/altering a trailing package (layer 9-10)                 | 9                   | **large** - layers 4/6/7 (the network minutes) restore                                                                                                                                                                              |
| `dotfiles-bootstrap` script edit (layer 8)                                         | 8                   | **large** - 1-7 restore                                                                                                                                                                                                             |
| `package.json` / `package-lock.json` change with no Containerfile effect           | none                | **total hit** - today this rebuilds cold for a byte-identical image (confidence: medium - a `@devcontainers/cli` version bump in the lockfile _can_ change the generated wrapper and so the image; a `prettier`/`bats` bump cannot) |
| ADR-0018 unconditional republish (this variant's dir unchanged since last release) | none                | **total hit** - ~10 min of QEMU emulation reproduces an identical image                                                                                                                                                             |

The pattern: the version pins that trigger most image builds sit at the **top** of the Containerfile, so pin-bump builds get almost nothing from a cache.
The real wins are concentrated in (a) builds triggered by changes that do not alter image content or only alter the last one or two layers, and (b) ADR-0018 identical republishes.

**Estimated saving if caching were adopted** (confidence: low - not measured on this repo; extrapolated from the layer analysis and the measured cold times):

- PR `build:dev` on a full-hit trigger: from ~72 s to ~15-30 s (cache resolve + export still cost something). On a pin-bump trigger: negligible.
- `publish:dev` on an identical republish: from ~8-12 min to ~1-2 min (multi-arch manifest assembly + push, no layer work).
- `publish:dev` on a trailing-layer change: perhaps ~11 min to ~4-6 min. On a top-of-file pin bump: negligible.

### The real PR-time variable is `npm ci`, not the image

Incidental finding, flagged for the status file per issue #72's editing-scope note, not fixed here.
The `./.github/actions/setup` step ran in **6 s** (cache hit) in one PR job and **5 min 4 s** (cache miss) in another on the same commit.
A 5-minute `npm ci` for five dev-tool packages (`@devcontainers/cli`, `bats`, `husky`, `lint-staged`, `prettier`) is an outlier worth its own look (npm cache key stability, or registry latency).
It swamps any Docker-layer saving that caching could offer on the PR path, and it is a cheaper win.

### Two more incidental findings

- **The dev image is built cold twice per qualifying PR.** `dev-image.yml` and `agent-image.yml` both run `build:dev` from scratch, in parallel jobs, with no artifact or cache shared between them. A cache backend _could_ let the second reuse the first, but only if the jobs were serialized or a registry cache populated by one fed the other - extra coupling, for a ~70 s saving on a job that is not on anyone's critical path.
- **`package.json`/`package-lock.json` in the PR path filter** triggers a full rebuild of both images for changes that usually cannot affect image content (a `prettier` bump). Tightening the filter is a smaller, cache-free improvement.

## Point 2 - cache backend options and tradeoffs

The `@devcontainers/cli` 0.89.0 wrapper (verified in its compiled source):

- `--cache-from` is a single `string` flag. `devcontainer.json`'s `build.cacheFrom` accepts a **string or an array**, so multiple sources are configurable there even though the CLI flag takes one.
- `--cache-to` is passed straight to `docker buildx build` for the Dockerfile build path (this repo's path). It is rejected only for the docker-compose path (`"--cache-to not supported."`), which does not apply here.
- **When `--cache-to` is _not_ set, the CLI injects `--build-arg BUILDKIT_INLINE_CACHE=1`.** So every build today already asks BuildKit to embed inline cache metadata; a pushed image may already carry a usable `mode=min` cache manifest. Confidence: medium - inline cache is only actually written by exporters that support it (registry/`--push`), and this was not verified against a real GHCR manifest.
- `type=gha` and `type=registry` cache export require the `docker-container` buildx driver. The publish jobs have it (`setup-buildx-action`); **the PR jobs do not** - they would each need `setup-qemu` + `setup-buildx` added to export anything beyond inline cache.

### Option A - `--cache-from` the previously published tag (inline cache)

`devcontainer build --cache-from ghcr.io/afrossard/container-base:<previous-version>-dev` (and `-agent` for the agent build).

- **Pro:** no new backend, no `actions/cache` step, no second push target, no 10 GB budget to share. The CLI already sets `BUILDKIT_INLINE_CACHE=1`, so the published images likely already carry the metadata this would consume.
- **Pro:** helps exactly the identical-republish case (ADR-0018) and trailing-layer changes.
- **Con:** only helps `publish:*` - a PR has no "previous published tag" for its own in-flight content, and the single-arch PR build cannot consume a registry-side inline cache without the `docker-container` driver anyway.
- **Con:** inline cache is `mode=min` (final-image layers only). Adequate here - these are effectively single-stage Dockerfiles - but it silently caches less than `mode=max`.
- **Con (multi-arch):** the previous tag's manifest list holds both arch manifests, so both _can_ seed, but which "previous version" to reference must be computed (the last released version, which release-please knows) and passed in. Confidence: medium - buildx multi-platform `--cache-from` against an inline-cache image is documented to work per-platform; not measured here.

### Option B - GitHub Actions cache (`type=gha`)

`--cache-to type=gha,mode=max --cache-from type=gha`.

- **Pro:** helps PR builds too - the one place a same-content rebuild is common (a second push to an open PR).
- **Pro:** `mode=max` caches intermediate layers, so trailing-layer edits hit more.
- **Con:** the ~10 GB GitHub Actions cache is **repo-wide and shared** - across `dev`, `agent`, both platforms, and `setup-node`'s npm cache. A multi-arch `mode=max` dev-image cache is easily 1-3 GB per platform; two variants times two arches plus npm can thrash the budget, and GitHub evicts LRU with no notice, so hit rate degrades silently under load.
- **Con:** requires adding `setup-qemu` + `setup-buildx` to `dev-image.yml` and `agent-image.yml` - two more workflows carrying buildx setup, against ADR-0018's "it stayed at one workflow and one config file" framing.
- **Con:** `type=gha` cache entries expire after 7 days of no access; a slow release week starts cold anyway.

### Option C - registry cache in GHCR (`type=registry`)

`--cache-to type=registry,ref=ghcr.io/afrossard/container-base:buildcache-dev,mode=max --cache-from type=registry,ref=…`.

- **Pro:** no size cap, `mode=max`, survives longer than 7 days, and is the cleanest multi-arch story - one cache ref holds all layers for all built platforms.
- **Pro:** free to store/serve for a public package (confidence: medium, as above).
- **Con:** a second `--cache-to` push on every build (extra upload time - seconds to a couple of minutes for a `mode=max` multi-arch cache).
- **Con:** a `buildcache-*` tag (or tags) now lives in the GHCR package next to the real version tags, needs its own retention/GC thought, and shows up in anything that lists the package's tags.
- **Con:** still needs buildx setup added to the PR workflows if PR builds are to use it.

### Summary

|                     | helps PR builds   | helps publish | new infra                  | multi-arch clean                | maintenance surface                  |
| ------------------- | ----------------- | ------------- | -------------------------- | ------------------------------- | ------------------------------------ |
| A prev-tag / inline | no                | yes           | none                       | per-platform, medium confidence | lowest                               |
| B `type=gha`        | yes               | yes           | buildx in 2 more workflows | yes (`mode=max`)                | shared 10 GB budget, silent eviction |
| C `type=registry`   | with buildx added | yes           | a `buildcache` tag + GC    | yes, best                       | second push per build + tag hygiene  |

## Point 3 - reproducibility tension

**Judgment: for this repo, the tradeoff is not acceptable on the `publish:*` path, and not worth it on the `build:*` path.**

`images/dev/Containerfile` resolves these unpinned upstreams on every build, none with a lockfile:

- four `apt-get update` + `apt-get install` transactions (base tooling + `mise`; `bubblewrap gh gnupg vim`; `claude-code`), taking whatever versions the Debian trixie and Anthropic `stable` repos serve at build time;
- `common-utils` with `"upgradePackages": true`, i.e. an `apt-get upgrade` inside the feature;
- the Homebrew installer fetched from `HEAD`, then `brew install dive starship` against current formulae;
- `chezmoi` from `get.chezmoi.io`, latest.

The Containerfile's own comments show this is deliberate: _"apt installs don't auto-update, correct for a versioned base image"_ next to the Claude Code install.
Each published `X-dev` is meant to be a point-in-time capture, and full-rebuild-every-time is what makes that true without any lockfile machinery.
For an image whose entire purpose is to be the trusted base other repos build their devcontainers and CI on (ADR-0001, ADR-0004, `CONTEXT.md` "shipped dependency"), that property is load-bearing.

A layer cache breaks it in the direction that is hardest to notice.
Under Option A/C on `publish:dev`, a Containerfile edit to layer 9 keeps layers 4/6/7 frozen at whenever they last rebuilt - which, across a run of pin bumps that all invalidate from the top, might be recent, but across a run of trailing-layer edits could be many releases and weeks stale.
`0.5.0-dev` could then ship an apt/Homebrew set from `0.3.0`'s build date, and nothing in the pipeline - no lockfile diff, no SBOM, no `verify:*` bats check (those assert behaviour, not versions) - would say so.

The one place caching does **not** hurt reproducibility is the ADR-0018 identical republish: same version, same inputs, so a cached rebuild and a cold rebuild should produce the same image, and ADR-0018 already treats that identical republish as acceptable.
But that is also the case with the least at stake - it is by definition not shipping anything new - so "caching is safe there" is not much of an argument for adopting it.

## Point 4 - multi-arch specifics

The publish builds pass `--platform linux/amd64,linux/arm64` to a single `devcontainer build`, which is one `docker buildx build` invocation that builds both platforms (arm64 under QEMU).

- **`type=gha` / `type=registry` with `mode=max`:** BuildKit exports cache blobs keyed by layer digest for **every platform it built**, not just the native one, because both platforms pass through the same build graph in that one invocation. So an unchanged QEMU-emulated `RUN` restores from cache on the next build without re-emulating - which is precisely the expensive part (the arm64 half is ~8-10x the amd64 half, per the measured release times). Confidence: medium - this is documented buildx behaviour for a single multi-platform invocation with a cache exporter; not measured on this repo.
- **`--cache-from` a previous multi-arch tag (inline cache):** the previous tag is a manifest list containing both arch manifests, so buildx can pull per-platform layer cache for both. Inline cache is `mode=min`, so only final-image layers seed - adequate for these single-stage files. Confidence: medium.
- **What would cache only the native platform:** splitting into per-platform build jobs that each cache separately, or a backend/driver that only stored the driver-native result. Neither is how this repo builds, so it is not a risk with the current single-invocation shape - but it would become one if the publish were ever restructured into a matrix over platforms.

So no chosen backend caches "only amd64" with the current build shape; the caveat is that this depends on keeping the single multi-platform invocation.

## Point 5 - interaction with change detection and ADR-0004

Issue #72 asks whether caching would fight or duplicate `changed-since-last-tag.sh` / the skip-unchanged-variant check from ADR-0004.

**That check no longer exists.**
[ADR-0018](../adr/0018-a-merge-cuts-the-release-and-publishes-both-variants.md) deleted `.github/scripts/changed-since-last-tag.sh` and the skip-if-unchanged rule ([#86](https://github.com/afrossard/container-base/pull/86)); ADR-0004's "a version tag no longer guarantees every variant was published" caveat is retired.
Every release now publishes both variants unconditionally.
So there is nothing on that axis left to conflict with.

On the conceptual question the issue was pointing at: caching and change detection are indeed different axes.

- Caching asks _"was this exact layer built before, anywhere?"_ and reuses the result.
- ADR-0004's old check asked _"did this variant's own directory change since the last tag?"_ and skipped the whole build if not.

They would not have duplicated each other's win: the old check saved a whole build only when a directory was untouched; a cache saves _parts_ of a build that runs regardless. If both had existed, they would have composed - the check skips the no-change case entirely, the cache speeds the changed case.

The current related mechanism is `.github/scripts/tag-agent-base.sh` plus the PR cascade (ADR-0018): `agent-image.yml` builds the dev image, retags it locally as the pinned base, then builds the agent image on it, because a release PR's bumped `BASE_VERSION` has no published `-dev` tag until merge.
A cache would not fight this either - it operates one level down, on the layers inside each of those two builds - but it does interact with it: the local retag means the agent build's `FROM` digest changes on every PR, so an agent-image layer cache keyed on that base would miss its `FROM`-dependent layers every PR anyway. Another reason the agent build (already ~20 s single-arch) is not where caching would pay off.

## Recommendation

**Stay as-is. Do not add `--cache-from`/`--cache-to` to `build:dev`, `build:agent`, `publish:dev`, or `publish:agent`.**

Reasoning:

1. **The cost side is already zero.** Public repo, unmetered Actions minutes (`billable.total_ms: 0` on every sampled run), free GHCR storage. Caching cannot save money; it can only save latency.
2. **Nobody is blocked on the latency.** PR image CI is ~2 min when `npm ci` hits cache; the 5-min outlier is `npm ci` itself, which caching Docker layers does nothing for. Releases run ~13-17 min but release-please decouples authoring from publishing, so no human waits on them.
3. **The wins are narrow and mostly land on a case ADR-0018 already accepted.** Because the version pins that trigger most image builds sit at the top of the Containerfile, pin-bump builds get almost nothing from a cache. The clean win is the identical republish - which ADR-0018 already weighed and called "the price of a tag meaning one thing again."
4. **The cost is a real base-image property.** Full-rebuild-every-time re-resolves six-plus unpinned, lockfile-free upstreams on every build, so each release captures current security state. A cache freezes them with nothing in the pipeline to flag the drift. Trading that away to speed up a build that costs $0 and blocks nobody is a bad trade for an image other repos trust as their base.
5. **Every backend adds maintenance surface** - a shared 10 GB budget with silent eviction (B), a `buildcache` tag needing GC and buildx added to two more workflows (B/C), or a "which previous version" computation and `mode=min` caveats (A) - to a pipeline ADR-0018 deliberately kept at one workflow and one config file.

**If latency ever does become a real constraint** (self-hosted runners with metered minutes, a release cadence where the ~10 min emulated build genuinely blocks someone), the narrowest acceptable form is **Option A**: `--cache-from` the last released `-dev`/`-agent` tag on `publish:*` only, relying on the inline cache the CLI already embeds, paired with a scheduled `--no-cache` rebuild (monthly `workflow_dispatch` or cron) so upstream drift cannot accumulate unbounded. Do **not** cache `build:*` - the PR builds are cheap, and adding buildx + a cache backend there is surface for a sub-minute saving.

The genuine long-term fix for the "one-line bump rebuilds everything" friction the issue describes is not caching but **pinning the apt/Homebrew/chezmoi sets** so a rebuild is deterministic and a bump is a visible diff - a larger change, out of scope here, worth its own issue if the friction is felt.

## No follow-up implementation issue

Issue #72's acceptance criteria open a follow-up implementation issue only _"if adoption is recommended."_
Adoption is not recommended, so no implementation issue is filed.

The incidental findings above (dev image built cold twice per PR; `npm ci` 6 s vs 5 min variance; `package.json` path filter triggering no-op rebuilds) are noted here and in the task status file for triage; none is a caching change and none is fixed in this doc, per the issue's editing scope.
