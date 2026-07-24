# The dotfiles bootstrap updates rather than initialises, and forces

ADR-0007 decided that the image ships `/usr/local/bin/dotfiles-bootstrap` and that every consumer calls it, but not what the script runs.
The obvious content, and the command the spec used throughout, is `chezmoi init --apply`.
That command is wrong for the job in two separate ways, both of which fail silently.

The script branches on whether a source directory already exists, uses `chezmoi update --apply` when it does, and passes `--force` on both paths.

## The measurement

Against a controlled upstream repository, on `debian:trixie-slim` with no TTY:

| state                                   | command                  | result                                                        |
| --------------------------------------- | ------------------------ | ------------------------------------------------------------- |
| cold                                    | `init --apply`           | applied, exit 0                                               |
| upstream moved to a new commit          | `init --apply`           | **file left at the old version, exit 0**                      |
| upstream moved to a new commit          | `update --apply`         | applied, exit 0                                               |
| upstream moved, and `$HOME` had drifted | `update --apply`         | `changed since chezmoi last wrote it?` then TTY error, exit 1 |
| upstream moved, and `$HOME` had drifted | `update --apply --force` | applied, exit 0                                               |

Row two is the more dangerous of the two failures.
`chezmoi init --apply` does not pull on an existing source directory, so a `postStartCommand` running it would report success on every container start while never picking up a single dotfiles change.

Row four is the failure ADR-0005 already documents, reached from a new direction.
There the cause was a parent image that pre-seeded `~/.zshrc`; here it is a durable `$HOME` volume that drifted after the fact.
The symptom is identical, including the exit code, and it wedges permanently: once a managed file differs from what chezmoi last wrote, every subsequent start fails at the same point and the user silently keeps stale configuration.

Drift is not hypothetical.
`uv`'s own installer appends `. "$HOME/.local/bin/env"` to `~/.zshrc` unless told not to, which is exactly the second writer that `dotfiles` ADR-0006 forbids, and any tool a developer installs later can do the same.

## Considered options

Omitting `--force`, so that a developer's in-container edits survive, was the alternative.
Rejected because the two failure modes are not symmetric.
A lost scratch edit is immediate, visible, and recoverable from the source repository; a wedged bootstrap is an exit code in a log nobody reads, and its symptom is configuration that is quietly months out of date.
`dotfiles` ADR-0005 already requires configuration to be applied afresh on every start precisely so that a durable volume cannot accumulate stale state, and without `--force` that requirement is stated but not delivered.

## Consequences

- Edits to a chezmoi-managed file inside a container do not survive a restart. The source of truth is the dotfiles repository, and the container is cattle.
- With no dotfiles repository configured, the script is a no-op and exits 0. The image must be usable by a developer who has no dotfiles at all (ADR-0010).
- The repository URL comes from the environment rather than being baked in. A shared base image cannot carry one person's dotfiles, per ADR-0001.
- A warm container works offline: with the source directory already cloned, the bootstrap exits 0 with no network. Only a cold first run needs to reach the remote.
- Tests must cover the update path against a fixture repository, not only a cold `init` against a personal one. A suite that only tests the cold path passes while row two is broken.
