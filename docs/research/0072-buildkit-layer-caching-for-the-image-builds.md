# BuildKit layer caching for the image builds

Research for [issue #72](https://github.com/afrossard/container-base/issues/72).

## What this settles

**Recommendation: stay as-is, with no layer cache wired into any of the four builds.**
Not because caching would not work here - it demonstrably does, and this document contains a working end-to-end demonstration of it against the devcontainer CLI this repo pins - but because on this repo's own measured numbers the win is small, lands unreliably, is paid for in a currency that costs nothing (a public repo's Actions minutes are free), and is bought by giving up the one correctness property a shared base image most needs: that a version tag means every layer was resolved fresh from current upstreams.

Two findings do most of the work, and both are direct observations rather than reasoning from documentation:

1. **Caching is only reachable on builds that already changed something.**
   `changed-since-last-tag.sh` (ADR-0004) already skips the publish entirely when a variant's directory is untouched, and it fired on 3 of the 5 most recent publish jobs, at a cost of 6-16 s each.
   Every publish that actually runs therefore runs _because_ that variant's Containerfile or its adjacent files changed, and on this repo's real tag history those changes land in positions that invalidate the expensive layers anyway.
2. **The expensive layer is the devcontainer feature install, and it sits at the very end of the generated Dockerfile, downstream of everything.**
   Any edit anywhere in the user's Containerfile - including a one-line `entrypoint` change, which is what 3 of the 5 recent `images/agent` changes were - forces it to re-run on both platforms.
   Verified locally with a controlled experiment, not inferred.

The rest of this document is the evidence.

## Method and sources

**Direct observation of this repo's CI.**
Step-level timings pulled from the Actions API (`/actions/runs/{id}/jobs`) and full job logs pulled from `/actions/jobs/{id}/logs`, for:

- 10 successful `dev image` runs (2026-08-01 to 2026-08-08).
- 10 successful `agent image` runs (same window).
- All 4 `publish dev image` and `publish agent image` runs for tags `0.0.6` through `0.0.9`, both the jobs that built and the jobs that skipped.
- Per-BuildKit-step timings read out of the raw logs of run 31256784800 (`dev image`), 31261281651 (`agent image`), 31256928124 (`publish dev image`, tag `0.0.7`) and 31273360480 (`publish agent image`, tag `0.0.9`).

**Local experiments**, run in a scratch directory on this session's own host (Docker Engine 29.7.2, buildx v0.36.1, BuildKit v0.32.2, `linux/amd64` with `qemu-aarch64` binfmt installed for `linux/arm64`), against `@devcontainers/cli@0.88.0` - the exact version `package-lock.json` pins - and a throwaway `registry:2` on `localhost:5000`.
Nothing was pushed to GHCR and no tags were created.
All test containers, images, builders and the scratch registry were removed at the end.

**Source reading.**
`@devcontainers/cli@0.88.0`'s own bundled `dist/spec-node/devContainersSpecCLI.js`, for how cache flags reach buildx.

**Documentation**, fetched directly:

- Docker, [cache storage backends overview](https://docs.docker.com/build/cache/backends/), [inline](https://docs.docker.com/build/cache/backends/inline/), [registry](https://docs.docker.com/build/cache/backends/registry/), [GitHub Actions cache](https://docs.docker.com/build/cache/backends/gha/), [cache management with GitHub Actions](https://docs.docker.com/build/ci/github-actions/cache/).
- GitHub, [dependency caching reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching), [Actions cache REST API](https://docs.github.com/en/rest/actions/cache), [Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions), [Packages billing](https://docs.github.com/en/billing/concepts/product-billing/github-packages).

One local experiment failed and is reported as such below: this session's host sits behind a TLS-intercepting proxy, and `extrepo enable mise` inside a build could not verify its certificate, so the real `images/dev/Containerfile` could not be built locally.
Every local cache experiment therefore ran against a synthetic Containerfile plus a synthetic local devcontainer feature, deliberately shaped to match the real generated `Dockerfile-with-features`, with the real per-layer costs taken from CI logs instead.

## The confirmed starting point: zero cache, everywhere

The issue's premise checks out.
`CACHED` appears zero times, and `--cache-from` zero times, in all ten job logs sampled (both PR workflows, both publish workflows, tags `0.0.6`, `0.0.7` and `0.0.9`).

One thing the issue does not mention, and it matters later: **the devcontainer CLI already passes `--build-arg BUILDKIT_INLINE_CACHE=1` on every single build today.**
Read out of the CLI's own source - `jQ(A){return A?/type\s*=\s*inline/i.test(A):!1}`, used as `jQ(A.buildxCacheTo)||u.push("--build-arg","BUILDKIT_INLINE_CACHE=1")` - the argument is added unconditionally unless `--cache-to type=inline` is explicitly given.
Confirmed present in every real CI invocation, for example the `0.0.7-dev` publish:

```
docker buildx build --platform linux/amd64,linux/arm64 --push --build-arg BUILDKIT_INLINE_CACHE=1 -f .../Dockerfile-with-features -t ghcr.io/afrossard/container-base:0.0.7-dev --target dev_containers_target_stage ...
```

The practical consequence is that **every image this repo has already published carries a usable inline cache**, so `--cache-from <previous tag>` is available today with no other change.
That is confirmed by experiment below, not assumed.

## Measured build times

### Pull request builds

`npm run build:dev`, 10 runs: **63, 64, 67, 67, 68, 71, 73, 74, 84, 105 s** (median ~69 s).
Whole `dev-image` job: 86-131 s.

`npm run build:agent`, 10 runs: **32, 32, 35, 36, 37, 37, 39, 42, 50, 56 s** (median ~38 s).
Whole `agent-image` job: 57-105 s.

Fixed overhead in these jobs is small and not cacheable by BuildKit: set-up 1-3 s, checkout ~1 s, `setup-node` 1-6 s, `npm ci` 1-6 s, and the bats suite 11-24 s (`test:dev`) or 15-31 s (`test:agent`).
Neither PR workflow uses `docker/setup-qemu-action` or `docker/setup-buildx-action`, so they build single-arch on the runner's default `docker` driver.

Per-layer, from the `dev image` run 31256784800 (64 s total):

| Step                                                           | Time   |
| -------------------------------------------------------------- | ------ |
| `FROM debian:trixie-slim` pull                                 | 1.6 s  |
| `COPY --from=ghcr.io/astral-sh/uv:0.12.3`                      | 0.3 s  |
| apt: ca-certificates, curl, extrepo, git, sudo, zsh, then mise | 11.7 s |
| sudoers/zshenv edits                                           | 0.2 s  |
| Homebrew installer plus `brew install dive starship`           | 18.0 s |
| chezmoi                                                        | 1.5 s  |
| apt: bubblewrap, gh, gnupg, vim                                | 4.6 s  |
| Claude Code apt repository plus install                        | 5.4 s  |
| `common-utils` feature install                                 | 14.3 s |
| exporting to image                                             | 3.0 s  |

And from `agent image` run 31261281651 (32 s total):

| Step                                                   | Time   |
| ------------------------------------------------------ | ------ |
| `FROM ghcr.io/afrossard/container-base:0.0.7-dev` pull | 11.6 s |
| apt: tini                                              | 2.7 s  |
| `COPY entrypoint` plus `chmod`                         | 0.1 s  |
| `docker-in-docker` feature install                     | 12.3 s |
| exporting to image                                     | 2.7 s  |

### Publish builds

| Run           | `npm run publish:*` step | Whole publish job |
| ------------- | ------------------------ | ----------------- |
| `0.0.6-dev`   | 676 s                    | 693 s             |
| `0.0.7-dev`   | 686 s                    | 716 s             |
| `0.0.6-agent` | 250 s                    | 274 s             |
| `0.0.8-agent` | 250 s                    | 279 s             |
| `0.0.9-agent` | 254 s                    | 290 s             |

The skipped path, for comparison: the whole `publish dev image` run for tag `0.0.9` took **6 s** end to end, and for `0.0.8` **7 s**.

Fixed overhead in a publish job that does build, taken from `0.0.7-dev`: set-up 3 s, checkout 0 s, `setup-node` 7 s, `npm ci` 3 s, `setup-qemu-action` 5 s, `setup-buildx-action` 3 s, `login-action` 1 s, verify 1 s, post-steps 5 s.
That is **~28 s of 716 s**, so roughly 96 % of a publish job is the build itself.

Per-platform, per-layer, from the `0.0.7-dev` publish:

| Step                            | amd64 (native) | arm64 (QEMU) |
| ------------------------------- | -------------- | ------------ |
| apt base tooling plus mise      | 14.0 s         | **201.3 s**  |
| sudoers/zshenv edits            | 0.1 s          | 0.2 s        |
| Homebrew plus `brew install`    | 23.3 s         | **182.0 s**  |
| chezmoi                         | 1.4 s          | 5.8 s        |
| apt: bubblewrap, gh, gnupg, vim | 5.3 s          | 63.3 s       |
| Claude Code                     | 5.3 s          | 42.9 s       |
| `common-utils` feature          | 11.3 s         | **150.8 s**  |
| **total RUN work**              | **60.7 s**     | **646.3 s**  |

Export and push of both platforms: 33.5 s.
The arm64 chain plus the export accounts for 680 s of the 686 s step, so **QEMU emulation is essentially the entire publish wall clock**, at roughly 10.6x the native cost for the same instructions.

And from the `0.0.9-agent` publish:

| Step                       | amd64  | arm64       |
| -------------------------- | ------ | ----------- |
| `FROM ...:0.0.7-dev` pull  | 10.3 s | 13.9 s      |
| apt: tini                  | 7.2 s  | 38.4 s      |
| `docker-in-docker` feature | 15.4 s | **156.5 s** |

Export and push: 27.9 s.

The published `0.0.7-dev` image is 460 MB compressed on amd64 and 455 MB on arm64, 14 layers each.

## What the cache backends actually do here

### Does `devcontainer build` forward the flags?

Yes, verbatim, for the `build.dockerfile` config shape this repo uses.
From the CLI's own bundled source, the buildx argument vector is assembled as `--cache-to <value>` from `--cache-to`, and one repeated `--cache-from <value>` per `--cache-from`.
The only refusal in the source is `"--cache-to not supported."`, and it is guarded by the `"dockerComposeFile" in config` branch, which does not apply here.

Confirmed by running it.
With `--cache-to type=registry,...` and `--cache-from type=registry,...` both passed, the CLI emitted:

```
docker buildx build --platform linux/amd64,linux/arm64 --push --cache-to type=registry,ref=localhost:5000/cachetest3:buildcache,mode=max --build-arg BUILDKIT_INLINE_CACHE=1 ... --cache-from type=registry,ref=localhost:5000/cachetest3:buildcache ...
```

### `--cache-from` against the previously published tag

**Works today, both platforms, including the devcontainer feature layer.**

Experiment: a synthetic `.devcontainer` with a two-step Containerfile and one local devcontainer feature whose install script sleeps, deliberately matching the real generated `Dockerfile-with-features` shape (the `dev_container_auto_added_stage_label` stage, the `dev_containers_feature_content_normalize` stage, and the `dev_containers_target_stage` with its `RUN --mount=type=bind ... devcontainer-features-install.sh`).
Built `--platform linux/amd64,linux/arm64 --push` cold in 13.2 s, with the feature install taking 6.1 s on amd64 and 6.4 s on arm64.
Then `docker buildx prune -af`, then the identical build with only `--cache-from localhost:5000/cachetest3:v1` added: **16 of 16 build steps `CACHED`, both platforms, 1.06 s total**, and `docker buildx imagetools inspect` on the result confirmed a proper index carrying both `linux/amd64` and `linux/arm64` manifests.

The mechanism is the `BUILDKIT_INLINE_CACHE=1` the CLI already sets.
No `--cache-to`, no second artifact, no new action.
This is the cheapest possible adoption path and it is the one worth measuring against, not the exotic backends.

Its documented limitation is real but does not bite here.
Docker's inline cache page states it "doesn't scale with multi-stage builds as well as the other drivers do", because inline cache is `min` mode: it records only the layers in the final image's lineage.
In the generated devcontainer Dockerfile the expensive layers - the user's Containerfile stage and the feature install in `dev_containers_target_stage` - are all in that lineage, which is why the experiment above hit 16 of 16.
The only layers outside it are the `dev_containers_feature_content_normalize` stage's two steps, measured at 0.0 s and 0.1 s in real CI.

### `type=registry` to GHCR

**Also works, both platforms, through the CLI.**
Same synthetic project, `--cache-to type=registry,ref=...,mode=max`, then a full prune, then `--cache-from type=registry,ref=...`: **16 of 16 steps `CACHED`**.

Worth recording because it answers the multi-arch question the issue raises with a primary artifact rather than a claim.
The exported cache manifest is a single `application/vnd.oci.image.manifest.v1+json` with `"config": {"mediaType": "application/vnd.buildkit.cacheconfig.v0"}`, and its layer list contains **both** platforms' base rootfs blobs side by side (a 30,143,609-byte layer and a 29,780,765-byte layer, the amd64 and arm64 Debian roots).
One cache ref, both platforms.
There is no per-platform cache to manage.

Costs specific to this repo: a second push target on every publish, and a `:buildcache`-style tag living in the same GHCR package as the real version tags.
ADR-0004 makes that package's tag list a deliberately human-readable interface (`1.4.2-dev` next to `1.4.2-agent`, read as "the last version each variant actually changed at"), and dropping a non-version cache tag into it is a genuine, if small, cost against that.
Storage is free: GitHub's Packages billing page states "GitHub Packages usage is free for public packages", and this repository is public.

### `type=gha`

**The worst fit of the three for this repo, for two reasons that are specific to how it is wired.**

First, authentication.
Docker's own `type=gha` page says the backend falls back to `$ACTIONS_CACHE_URL`, `$ACTIONS_RESULTS_URL` and `$ACTIONS_RUNTIME_TOKEN`, that with `docker/build-push-action` "the `url` and `token` parameters are automatically populated", but that when running `docker buildx` manually from inline steps "the variables must be manually exposed", recommending the third-party `crazy-max/ghaction-github-runtime` action.
This repo invokes buildx from a plain `run: npm run publish:dev`, so `type=gha` means adding a third-party action to every image job purely to leak two environment variables into the shell.

Second, and decisively: **ref scoping.**
GitHub's dependency-caching reference states that "Workflow runs can restore caches created in either the current branch or the default branch" and that "Workflow runs cannot restore caches created for child branches or sibling branches".
Neither `dev-image.yml` nor `agent-image.yml` has a `push` trigger at all - both are `pull_request` plus `workflow_dispatch` - so **no run in this repo ever writes an image-build cache on the default branch**, and there is nothing for a PR run to restore.
It would fall to each PR to warm its own cache and then only benefit its own re-runs, since GitHub also documents that a PR-created cache "can only be restored by re-runs of the pull request".
The publish workflows are worse still: they trigger on tag pushes, each tag is its own ref, and the cache REST API documents only `refs/heads/<branch>` and `refs/pull/<number>/merge` as ref forms.
I could not test this, so treat the tag conclusion specifically as documentation-derived inference rather than observation: the branch/PR half is quoted directly, the tag half follows from it.

Size is not the binding constraint here even though the issue flags it.
GitHub documents a 10 GB per-repository limit with eviction of entries "not accessed in over 7 days", and a `mode=max` cache for both variants and both platforms would land in the low single-digit GB.
The scoping problem bites long before the size limit does.

### The driver question, which PR builds cannot dodge

Docker's cache-backends overview states: "The default `docker` driver supports the `inline`, `local`, `registry`, and `gha` cache backends, but only if you have enabled the containerd image store."

The GitHub runner does not have it enabled.
The `docker info` output captured in the `0.0.7-dev` publish log reports `Storage Driver: overlay2` on Docker Engine `28.0.4` with buildx `v0.35.0` and BuildKit `v0.31.2`.
The publish jobs are unaffected, because `docker/setup-buildx-action` gives them a `docker-container` driver.
The PR jobs have no such step, so **adding a cache to a PR build means also adding `docker/setup-buildx-action` to it**, which changes the driver under `--load`.

That change is not free.
On a `docker-container` driver, `--load` has to export the built image as an OCI tarball and stream it into the daemon.
Measured locally against a realistically-sized image (a trivial derived build on top of a local copy of the real 460 MB `0.0.7-dev`), a fully cache-hit build took 6.2 s total, of which **5.6 s was `exporting to oci image format` and `sending tarball`** - pure overhead that today's `docker`-driver PR builds do not pay.
Add the network fetch of the cached layers, for which CI gives a good real number: pulling this same 460 MB image from GHCR on a runner took **10.3-13.9 s** in the `0.0.9-agent` publish.

So a best-case, everything-hits PR `dev` build looks like roughly 12 s of cache fetch plus 6-10 s of load plus ~4 s of buildx setup, against a 63-105 s cold build.
A saving, but of about 40 s on an 86-131 s job, and only in the best case.

I did observe `--cache-from <tag>` and `--cache-to type=registry,mode=max` both working on the default `docker` driver locally, contradicting the plainest reading of that docs sentence - but this host runs Docker 29.7.2 with the containerd image store on (`driver-type: io.containerd.snapshotter.v1`), which is exactly the documented precondition.
It therefore says nothing about the runner, and I am treating the docs as authoritative for the runner's `overlay2` engine.

## Where the cache would actually hit, on this repo's real history

This is the part that decides the recommendation, and it is not visible from general Docker-caching lore at all.

`git diff` across every tag transition from `0.0.1` to `0.0.9`:

- `images/dev` changed in 3 of 8 transitions.
- `images/agent` changed in 5 of 8 transitions.

Taking each real change and asking what a `--cache-from <previous tag>` would have saved:

**`0.0.6` to `0.0.7`, dev: the `uv` bump. Saves nothing.**
The change is `COPY --from=ghcr.io/astral-sh/uv:0.11.32` to `0.12.3`, layer 2 of 10.
Everything downstream rebuilds.
This is the single case the issue itself calls out, and it is the worst-case position.

**`0.0.5` to `0.0.6`, dev: `USER vscode` appended. Saves a lot, but not everything.**
Stage 1 caches completely, which is 495.5 s of arm64 work and 49.4 s of amd64 work.
The `common-utils` feature layer does not, and that is 150.8 s on arm64 - because the devcontainer CLI substitutes the user name _literally into the generated RUN text_ rather than passing it as a build arg.
Read straight out of a generated `Dockerfile-with-features` from a local run:

```
RUN \
echo "_CONTAINER_USER_HOME=$( (command -v getent >/dev/null 2>&1 && getent passwd 'root' || grep -E '^root|^[^:]*:[^:]*:root:' /etc/passwd || true) | cut -d: -f6)" >> ...
```

That `'root'` becomes `'vscode'`, the instruction text changes, and the feature install behind it re-runs.
Estimated saving: roughly 8 minutes of an 11.5 minute publish.

**`0.0.4` to `0.0.5`, `0.0.5` to `0.0.6`, `0.0.8` to `0.0.9`, agent: `entrypoint` only. Saves about 45 s of 254 s.**
`COPY entrypoint` sits after the `apt install tini` layer and before the feature stage, so tini caches (38.4 s arm64 plus 7.2 s amd64) and the `docker-in-docker` install (156.5 s arm64 plus 15.4 s amd64) does not.

Verified rather than reasoned: in the synthetic project, changing only the instruction immediately before the feature stage left exactly one step `CACHED` (the base `FROM`) and re-ran the feature install on both platforms at 6.1 s and 6.4 s.
Changing the _first_ `RUN` instead produced zero `CACHED` steps.

**`0.0.7` to `0.0.8`, agent: `FROM ...:0.0.3-dev` to `...:0.0.7-dev`, plus `USER root`. Saves nothing.**
The base image changed.

Rolled up over the five publish jobs that actually ran in the sampled window, a previous-tag cache would have saved on the order of **9-10 minutes out of ~32 minutes of publish build time**, with 2 of the 5 saving nothing at all and a single run accounting for almost all of it.

The PR side is similar in shape.
Because `dev-image.yml` and `agent-image.yml` also trigger on `package.json` and `package-lock.json`, the reliable full-hit case is a Renovate lockfile bump: run 31254906322 rebuilt the whole dev image for 67 s and run 31254906292 rebuilt the whole agent image for 42 s, both for a `lint-staged` lockfile change that touched no image file.
Those would have hit completely.
But that observation cuts against caching rather than for it: **the PR builds with a full cache hit are exactly the ones no human is waiting on, and the PR builds a human is waiting on are exactly the ones editing the Containerfile, where the cache saves close to nothing.**

## Interaction with `changed-since-last-tag.sh` and ADR-0004

The two mechanisms do not fight, and they do not duplicate each other.
They compose in a way that is bad for caching's business case.

`changed-since-last-tag.sh` answers "did this variant's directory change between the previous tag and this one" and, when the answer is no, skips the build entirely.
That is a 100 % saving on the untouched variant, and it fired on 3 of the 5 most recent publish jobs.
ADR-0004 records it as found in practice rather than designed upfront, after a tag cut for `-agent` force-republished an identical `-dev`.

A layer cache answers a different question - "were these exact instructions run before, anywhere" - and it can only ever apply to the builds the skip check lets through.
Those are, by construction, the builds where something in that variant's directory changed.
The skip check has already harvested every "nothing changed" win, and left the cache only the "something changed" cases, which is where partial invalidation makes it weakest.

There is one small piece of leverage worth recording for any future implementation.
`changed-since-last-tag.sh` already computes the previous tag, with `git describe --tags --abbrev=0 "${current_tag}^"`, so the publish workflows already have in hand the exact ref a `--cache-from ghcr.io/afrossard/container-base:<previous>-<variant>` would need.
No new lookup machinery would be required.

One caveat if that is ever done: the previous _tag_ is not always a tag at which that variant published, precisely because of the skip logic.
`0.0.8-dev` does not exist.
A cache reference to it would simply miss - BuildKit treats an unresolvable `--cache-from` as a miss, not an error - but it would miss silently and often, so a correct implementation would have to walk back to the last tag at which that variant actually changed, which is a slightly different query than the one the script does today.

## The reproducibility tension

This is where the recommendation is actually decided, so it deserves a concrete demonstration rather than a general worry.

**A cached layer is frozen, byte for byte, and this is easy to show.**
The synthetic Containerfile contained `RUN date -u +%s%N > /built-at`, and the synthetic feature wrote `date -u +%s%N > /feature-installed-at`.
After a cold build and a cache-hit rebuild into a different tag, both files were identical to the nanosecond in both images:

```
v1  built-at: 1786220877198351696   feature-installed-at: 1786220883473260064
v2b built-at: 1786220877198351696   feature-installed-at: 1786220883473260064
```

Nothing re-executed.
That is the entire point of a cache, and it is also exactly the risk.

What this repo would be freezing is unusually load-bearing:

- Four separate `apt-get update` chains across the two Containerfiles, covering Debian's own repository, the extrepo-enabled mise repository, and Anthropic's signed Claude Code repository.
- `images/dev/devcontainer.json` sets `"upgradePackages": true` on the `common-utils` feature, so that layer's job includes pulling Debian security updates.
  Caching it means a new version tag can ship without them.
- The Homebrew installer fetched from `raw.githubusercontent.com/Homebrew/install/HEAD/install.sh`, which is by definition a moving target, plus `brew install dive starship`.
- `curl -fsSL get.chezmoi.io | sh`, likewise.
- `claude-code` from the `stable` apt channel, where the Containerfile's own comment reasons that "apt installations don't auto-update, which is correct behaviour for a versioned base image - a rebuild refreshes it".
  A cache is precisely the thing that makes a rebuild stop refreshing it.

Today, a version tag carries an unconditional guarantee: every one of those resolved fresh at build time.
That guarantee is free, and it is currently invisible because nothing has ever violated it.

The counter-argument is honest and worth stating: caching only masks upstream drift for the layers _upstream of the change_, and any edit to an early layer forces the whole chain anyway.
So the exposure is bounded, and a periodic no-cache rebuild would bound it further.
But that counter-argument also concedes the case: the situations where the cache is safe are the situations where it saves the least, and the situations where it saves the most are the ones where the most upstream state has been frozen.

For a repo whose stated scope is "shared container base images" - the pinned floor other repositories build on - trading that guarantee for tag-time wall clock on a free runner is the wrong direction.

## The cost side is genuinely zero

Worth stating plainly because it removes the strongest normal argument for caching.

GitHub's Actions billing page: "GitHub Actions usage is free for self-hosted runners and for public repositories that use standard GitHub-hosted runners."
GitHub's Packages billing page: "GitHub Packages usage is free for public packages."
`afrossard/container-base` is public and uses `ubuntu-latest`.

So there are no Actions minutes to save and no storage to pay for.
The only currency is wall clock, and the only wall clock a human experiences is a PR build at 57-131 s, where the cache is weakest.
Publish builds are fire-and-forget on a tag push; nobody watches an 11-minute `-dev` publish, and the release is not gated behind a person waiting.

## Recommendation

**Stay as-is. Do not wire a layer cache into `build:dev`, `build:agent`, `publish:dev` or `publish:agent`.**

The reasoning, in order of weight:

1. **The savings are real but small, unreliable, and unpurchasable in the cases that matter.**
   9-10 minutes across ~32 minutes of publish build time in the sampled window, concentrated almost entirely in one run, with 2 of 5 saving nothing.
   On the PR side, the full-hit case is a Renovate lockfile bump nobody is waiting for, and the human-waiting case is a Containerfile edit where the cache saves seconds.
2. **The property being traded away is worth more than the time being bought.**
   Four `apt-get update` chains, `upgradePackages: true`, two `curl | sh` installers pinned to `HEAD`, and an apt `stable` channel whose freshness the Containerfile explicitly delegates to "a rebuild refreshes it".
   Full rebuild is currently a free correctness guarantee for a shared base image, and the demonstration above shows exactly how completely a cache freezes those layers.
3. **The cost side is zero.**
   Public repo, standard runners, free Actions minutes, free package storage.
   There is no budget pressure to relieve.
4. **ADR-0004's skip check already took the biggest, safest win**, and by construction leaves the cache only the cases where partial invalidation makes it weakest.
5. **Every backend adds machinery disproportionate to the payoff.**
   `type=gha` needs a third-party action to expose runtime tokens and is ref-scoped in a way this repo's triggers cannot satisfy.
   `type=registry` needs a second push target and a non-version tag inside a package whose tag list ADR-0004 treats as a human-readable interface.
   `--cache-from <previous tag>` is genuinely cheap, but needs a previous-tag walk that is subtly different from the one `changed-since-last-tag.sh` does, and it still buys only the numbers in point 1.
   Adding caching to PR builds additionally forces `docker/setup-buildx-action` onto both PR workflows and pays a measured ~5.6 s `--load` tarball tax plus a ~12 s cache fetch.

**What would change this answer.**
Not more PRs, and not more tags - the shape of the win does not improve with volume.
It would change if publish wall clock became something a person waits on.
ADR-0004 leaves room for per-language runtime bases; at, say, five variants times two platforms via QEMU, tag-time goes from ~16 minutes to the better part of an hour, and at that point the cheapest correct move is `--cache-from` against the previous published tag of the _same variant_, on the publish workflows only, never on PR builds, paired with a scheduled uncached rebuild to keep the freshness guarantee somewhere.
It would also change if the `-dev` image ever grew a genuinely slow, genuinely pinned layer - a compiled toolchain rather than an apt install - since that is the shape a cache is actually good at and this image currently has none.

**Confidence: high on the recommendation, high on the measurements, medium on one detail.**
The measurements and the cache-behaviour experiments are direct observation.
The `type=gha` tag-ref conclusion is documentation-derived inference, quoted for branches and PRs and extrapolated for tags; it is not load-bearing, since the missing default-branch write already disqualifies `type=gha` for PR builds on quoted evidence alone.

**Open questions, recorded rather than resolved.**

- Whether the runner's `overlay2` Docker 28.0.4 would in fact refuse `--cache-from <tag>` on the default `docker` driver.
  Docker's docs say it needs the containerd image store; my local contradiction ran with that store enabled, so it does not settle the runner case.
  Only relevant if the PR-build recommendation is ever revisited.
- The real `images/dev/Containerfile` could not be built locally (TLS-intercepting proxy broke `extrepo enable mise`), so the cache experiments used a synthetic project shaped like the generated `Dockerfile-with-features` rather than the real image.
  The per-layer costs come from CI logs, which is the better source for them anyway, but a cache experiment against the real Containerfile was not performed.
- `type=gha` was not tested at all; it cannot be exercised outside GitHub Actions, and this issue is investigation-only.

## No follow-up implementation issue

Issue #72's third acceptance criterion is conditional on recommending adoption.
This document recommends against, so no implementation issue is filed.

If a future session revisits this after the "what would change this answer" trigger fires, the implementation scope is already written down above: previous-published-tag `--cache-from` on the publish workflows only, a previous-tag walk that skips tags where the variant did not publish, and a scheduled uncached rebuild.
