# The dev image declares no entrypoint

`dotfiles` ADR-0005 says that for containers no platform launches, "the image installs the chezmoi binary at build time and declares an entrypoint that runs `chezmoi init --apply` at start".
Read literally that would have the dev image set an `ENTRYPOINT`.
It does not.
It installs chezmoi system-wide and ships `/usr/local/bin/dotfiles-bootstrap`, and leaves `ENTRYPOINT` to the consumer.

Two things make the literal reading unworkable.
The `docker-outside-of-docker` feature, which every consumer devcontainer uses, installs `/usr/local/share/docker-init.sh` and claims the entrypoint for itself.
And where the `dotfiles.repository` user setting is enabled, the bootstrap would run twice.

## Every consumer calls the script, and the platform setting stays off

`dotfiles` ADR-0005 makes `dotfiles.repository` the mechanism for anything VS Code launches, so that "no sibling repo needs to change".
We do not use it, and the reason is migration order rather than taste.

That setting is `scope: machine`, verified against the installed Dev Containers extension 0.466.0, and VS Code ignores machine-scoped keys in a workspace `.vscode/settings.json`.
It cannot be set per repo.
Setting it therefore turns the bootstrap on for **every** devcontainer on the machine at once, including the ones not yet migrated - and those fail.
Measured against `mcr.microsoft.com/devcontainers/python:3-trixie`, the base of all five unmigrated devcontainers: `chezmoi init --apply` exits 1 on its pre-seeded oh-my-zsh `~/.zshrc`, exactly as ADR-0005 records for the `base` variant.
Enabling the setting would be a flag day that breaks five repos to fix one.

So every consumer, devcontainer or not, calls `dotfiles-bootstrap` explicitly.
A repo adopts the new image and its bootstrap line in the same change, and the repos behind it are untouched.

## Consequences

- Migration is per repo and reversible, with no estate-wide switch to throw.
- A devcontainer calls `dotfiles-bootstrap` from `postStartCommand`, not `postCreateCommand`, because `dotfiles` ADR-0005 requires config to be applied afresh on every start so that a mounted durable volume cannot accumulate stale config. Every consumer already has a `postStartCommand` for `git config --global --add safe.directory`, so it chains onto an existing line.
- A container no platform launches, such as `actual-budget-transformer`'s `claude` compose service, calls the same script from its own entrypoint. One mechanism serves both, which is why no `ENTRYPOINT` is needed to serve either.
- Nothing in the estate starts a container that silently reaches GitHub. The network fetch happens where a consumer asked for it.
- Adopting `dotfiles.repository` later remains open, and becomes attractive once every repo is migrated, since it would let each consumer drop its bootstrap line. It belongs in `dotfiles`' tracked `home/vscode-settings.json` (that repo's ADR-0007 already delivers VS Code user settings), not in any repo here. Deferred until the last consumer migrates.
