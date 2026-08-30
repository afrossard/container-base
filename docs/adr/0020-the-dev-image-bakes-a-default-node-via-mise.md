# The dev image bakes a default Node via mise

ADR-0006 bakes no language runtime and deliberately gives mise no global config, so every version comes from a project pin.
Preparing to run agent distros in the agent runtime (issue #100) surfaced tooling that needs Node before any project pin exists: npm-global helper tools, hooks, and installers invoked from directories that pin nothing.
Without a default, every fresh guest and every unpinned devcontainer pays a full Node download at session start, a cost a disposable runtime multiplies by every restart.

The dev image therefore runs `mise install node@lts` at build time and ships a system-level default pin in `/etc/mise/config.toml`, so bare `node` resolves everywhere while any project pin still layers over it and wins.
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
- The baked default stales between rebuilds; the pin should be Renovate-visible (issue #102).
