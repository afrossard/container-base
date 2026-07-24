# AGENTS.md

## Status

`images/dev/` holds the walking skeleton from issue #2: `devcontainer.json` and `Containerfile`, built on `debian:trixie-slim` with the `common-utils` feature pinned via the committed `devcontainer-lock.json`.
CI (`.github/workflows/dev-image.yml`) builds it with `--frozen-lockfile` and runs the bats suite in `test/dev/` on every pull request.
Published multi-arch to GHCR on a git tag (issue #3, `.github/workflows/publish-dev-image.yml`).
`uv` and `mise` are wired in system-wide (issue #4): `uv` via `COPY --from=ghcr.io/astral-sh/uv`, `mise` via its apt repository, `mise`'s data directory moved to `/usr/local/share/mise` and vscode-owned, shims on `PATH` and prepended to sudo's `secure_path`.
Neither installer touches `$HOME`.
Homebrew and starship are wired in system-wide (issue #5): Homebrew's installer runs as root during the build (its own container check needs a faked `/.dockerenv`, since BuildKit `RUN` steps don't set one up), the prefix at `/home/linuxbrew/.linuxbrew` is chowned to the eventual vscode uid/gid, and `brew shellenv`'s output is appended to `/etc/zsh/zshenv`.
`starship` ships on `PATH` with no `starship init` line anywhere, so shell ergonomics stay a personal-dotfiles concern (ADR-0010).
Chezmoi and `dotfiles-bootstrap` are wired in (issue #6): chezmoi installs via `get.chezmoi.io -b /usr/local/bin`, never `~/.local` (ADR-0005), and `/usr/local/bin/dotfiles-bootstrap` branches cold `chezmoi init --apply --force` versus warm `chezmoi update --apply --force` (ADR-0009).
A fixture dotfiles repository under `test/dev/fixtures/dotfiles` backs the bats suite.
The remaining tools (`gh`, `dive`, `vim`, `bubblewrap`, Claude Code) have not landed yet (issues #7 and #8).

## Known consumers pending migration

These repos currently build FROM upstream images directly and hand-roll the setup this repo now owns. Once the dev image is published, migrate each devcontainer to `FROM ghcr.io/afrossard/container-base:<version>-dev`:

- **`default-vscode-project`** - `Containerfile` (FROM `python:3.14-slim-trixie`) and `.devcontainer/Containerfile` (FROM `mcr.microsoft.com/devcontainers/python:3-trixie`, hand-rolled Homebrew bootstrap to drop once the dev image covers it).
- **`homelab-kube`, `homelab-etl`, `homelab-fun`, `actual-budget-transformer`** - the four sibling repos named in dotfiles ADR-0001 as the source of the devcontainer drift this repo exists to fix.
- **`container-base`** - this repo has no devcontainer at all and is the intended first consumer, so the image gets dogfooded before anything else migrates.

Every migration must delete `UV_PYTHON_DOWNLOADS=0` from `devcontainer.json` (ADR-0006). All five set it, and on this base it prevents `uv` from finding any Python.

## Agent skills

### Issue tracker

Issues live as GitHub issues in `afrossard/container-base`, driven by the `gh` CLI.
See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, each label string equal to its name.
See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root.
See `docs/agents/domain.md`.
