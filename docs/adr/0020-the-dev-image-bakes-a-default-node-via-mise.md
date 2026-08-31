# The dev image bakes a default Node via mise

ADR-0006 bakes no language runtime and deliberately gives mise no global config, so every version comes from a project pin.
Preparing to run agent distros in the agent runtime (issue #100) surfaced tooling that needs Node before any project pin exists: npm-global helper tools, hooks, and installers invoked from directories that pin nothing.
Without a default, every fresh guest and every unpinned devcontainer pays a full Node download at session start, a cost a disposable runtime multiplies by every restart.

The dev image therefore installs a default Node at build time - `mise install` with no arguments, driven by a system-level default pin it ships in `/etc/mise/config.toml` - so bare `node` resolves everywhere while any project pin still layers over it and wins.
The agent image inherits this by building FROM the dev image; runtime bases are untouched.
mise remains the runtime's owner, so this amends the manager model rather than abandoning it.
The clause it amends is ADR-0008's: that ADR deliberately left `MISE_GLOBAL_CONFIG_FILE` unset so there would be no fallback version, citing ADR-0006's no-baked-runtime rule as the reason.
A system-level default pin is exactly that fallback, accepted here on purpose.
`MISE_GLOBAL_CONFIG_FILE` stays unset; the pin ships as mise's system config instead, and project pins still layer over it and win, which was verified against mise itself (via `MISE_SYSTEM_CONFIG_FILE`) before deciding, not assumed.

## Considered options

- **Per-session `mise use -g node@lts` in-guest.** Keeps ADR-0006 pure, but re-downloads the runtime on every VM restart, which is exactly the friction that prompted the decision.
- **Baking Node outside mise** (apt, nodesource). Rejected: the manager stays the owner, so a project pin keeps winning by the same mechanism it always did.
- **Agent image only.** Rejected: the need - tooling that runs before any project pin - exists in devcontainers too, and one dev-image change covers the agent variant for free.

## Consequences

- Every dev-image consumer pays the size of one Node LTS; consumers that pin their own version still download theirs, and for them the baked default is dead weight.
- This is the first baked runtime anywhere in the tag matrix, so the "no baked runtimes" shorthand for ADR-0006 is no longer literally true; the accurate statement is "the manager owns every runtime, and exactly one manager-owned default is baked".
- The baked default would stale between rebuilds, so the pin is Renovate-visible (issue #102): see the implementation note below on why it is a concrete major rather than the `lts` alias.

## Implementation notes (issue #102)

The pin ships as a real mise-format file, `images/dev/mise/config.toml`, copied verbatim to `/etc/mise/config.toml` in the build.
It is kept as a file, not an inline heredoc, so it sits at a path Renovate's mise manager scans.

The pinned value is a concrete Node Active LTS major (`node = "24"`), not the `lts` alias the decision above assumed.
Renovate's Node versioning rejects `lts` as an invalid version and would never bump it, so a `lts` pin would silently stale - the exact failure the Renovate-visibility consequence exists to prevent.
A concrete major is bumpable, and Renovate's Node versioning is LTS-aware: it treats a not-yet-LTS or odd-numbered major as unstable and, with the default `ignoreUnstable`, proposes a bump only when the next line reaches Active LTS.
So the pin still tracks LTS, just one merged Renovate PR at a time rather than silently at each rebuild.

`mise install` is run with no arguments rather than `mise install node@lts`, so the version resolves from the shipped system config alone - one source of truth, and a build-time check that the `/etc/mise/config.toml` path is honored (only the `MISE_SYSTEM_CONFIG_FILE` env override was tested during the grilling session).
