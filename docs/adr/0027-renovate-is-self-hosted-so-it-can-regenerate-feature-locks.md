# Renovate is self-hosted so it can regenerate feature locks

Renovate's `devcontainer` manager did not scan `images/*/devcontainer.json`, so the devcontainer feature pins the images ship were never offered as updates (issue #226).
Extending its file patterns is not enough.
The manager never touches `devcontainer-lock.json`, so a bump that changes only `devcontainer.json` fails `--frozen-lockfile` with `Lockfile does not match.`
A major-only pin such as `common-utils:2` also hides every release within that major, even though the lock holds an exact version.

**Decision: Renovate runs from this repo's own workflow, and regenerates each lock with `devcontainer upgrade`.**
`.github/workflows/renovate.yml` runs the official `renovatebot/github-action` on a schedule, configured by `.github/renovate-global.json`.
Feature pins name a full version, so Renovate sees every release.
A `postUpgradeTasks` entry runs the generator that owns the lock, and the lock lands in the same commit as the pin.

## Considered options

- **Stay on the Mend-hosted app and use `postUpgradeTasks`.** Rejected: the app's `allowedCommands` are only `^git add --all$`, `^git reset$` and `^pwd$`.
- **Stay on the app and have a workflow on `renovate/**` push the regenerated lock.** Rejected: each Renovate rebase drops that commit, the bot must be listed in `gitIgnoredAuthors`, and CI runs red before it runs green.
- **Have a regex manager edit the lock directly.** Rejected: the lock is generated, so it should come from its generator.

## Consequences

- The workflow needs a `RENOVATE_TOKEN` secret, because pushes made with `GITHUB_TOKEN` do not trigger CI on the PRs Renovate opens.
- Only one Renovate may run against this repo, so the Mend app must be turned off for it when this lands.
- PRs and the Dependency Dashboard belong to the token's user, so PRs and the dashboard issue left by the app are not adopted and need closing.
- A ticked dashboard checkbox takes effect on the next scheduled run, or on a manual `workflow_dispatch`, because nothing delivers the app's webhook any more.
- Devcontainer features join the pinned set, which ADR-0024 limited to the platform and the language runtimes. They could never float: `--frozen-lockfile` builds already held each one at the exact version in its lock, and this makes that pin visible.
- With full-version pins, every upstream feature release that changes `images/**` computes a release of ours. For features this accepts the release cascade ADR-0024 removed for uv, because the alternative is dropping the locks.
- The default Renovate image has `node` but no `npm`, so the task declares `installTools` and the global config sets `binarySource` to `install`.
