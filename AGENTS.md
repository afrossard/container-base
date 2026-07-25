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
The remaining tools every consumer previously installed by hand are wired in (issue #7): `gh`, `vim` and `bubblewrap` install via apt from Debian's own repository.
`dive` has no Debian package and rides the same `brew install` as `starship`, so it only resolves in a login shell.
Claude Code installs from its official signed apt repository (`stable` channel), with the downloaded key's fingerprint checked against Anthropic's published fingerprint before the repository is trusted.
None of the explicitly excluded single-repo tools (`kubectl`, `k9s`, `helm`, `flux`, `talosctl`, `talhelper`, `sops`, `age`, `yq`, `gptfdisk`, `xorriso`, `gemini-cli`) are installed.
This repo now has its own workspace devcontainer (issue #8): `.devcontainer/devcontainer.json` builds `FROM` the published dev image, pinned in `.devcontainer/Containerfile` at `0.0.3-dev` (cut fresh for this issue, since the previously-published `0.0.2-dev` predated issues #4-#7 and lacked `dotfiles-bootstrap` entirely).
`dotfiles-bootstrap` runs from `postStartCommand`, chained onto the `git config --global --add safe.directory` line every `docker-outside-of-docker` consumer needs (ADR-0007); `dotfiles.repository` stays unset, so `DOTFILES_REPO` only reaches the container if a developer's own shell environment sets it, passed through via `remoteEnv`'s `${localEnv:DOTFILES_REPO}`.
Node, needed only for this repo's own `npm` tooling, resolves via a committed `.mise.toml` (`mise trust && mise install`) rather than a devcontainer feature, consistent with ADR-0006's "mise owns every language" rule - the dev image already carries `mise` system-wide.
`postCreateCommand` and `postStartCommand` are `.devcontainer/post-create` and `.devcontainer/post-start`, plain executable scripts rather than inline command strings, styled like `images/dev/dotfiles-bootstrap`: no extension, `#!/bin/sh` with `set -eu`.
The `docker-outside-of-docker` feature needs `"moby": false` on this Debian trixie base; its default `moby: true` path installs `moby-cli`, which trixie's apt repositories don't carry.
`waitFor` is set to `postStartCommand`, since its own default (`updateContentCommand`, a step this repo doesn't define) lets VS Code open the first integrated terminal before `dotfiles-bootstrap` finishes cloning and applying - that terminal sources `.zshrc` before it exists and stays bare for its lifetime, while a terminal opened after the bootstrap completes is fine. `customizations.vscode.extensions` matches what every other migrated devcontainer already carries.
Building and testing the dev image from inside this workspace devcontainer works (`npm run build:dev`, `npm run test:dev`) for the great majority of the suite, verified end to end; a handful of `test/dev/dotfiles-bootstrap.bats` cases and one `mise install` case in `test/dev/dev.bats` are unreliable specifically when nested this way, because `docker-outside-of-docker` drives the _host_ daemon, so any `docker run -v` a test constructs from a container-local tmp path doesn't resolve on the host, and spawning containers this way adds real overhead.
CI, which runs the suite unnested, is unaffected and remains the authoritative signal.

## Known consumers pending migration

These repos currently build FROM upstream images directly and hand-roll the setup this repo now owns. Once the dev image is published, migrate each devcontainer to `FROM ghcr.io/afrossard/container-base:<version>-dev`:

- **`default-vscode-project`** - `Containerfile` (FROM `python:3.14-slim-trixie`) and `.devcontainer/Containerfile` (FROM `mcr.microsoft.com/devcontainers/python:3-trixie`, hand-rolled Homebrew bootstrap to drop once the dev image covers it).
- **`homelab-kube`, `homelab-etl`, `homelab-fun`, `actual-budget-transformer`** - the four sibling repos named in dotfiles ADR-0001 as the source of the devcontainer drift this repo exists to fix.

Every migration must delete `UV_PYTHON_DOWNLOADS=0` from `devcontainer.json` (ADR-0006). All five set it, and on this base it prevents `uv` from finding any Python.
Every migration should also expect `docker-outside-of-docker`'s default options to fail on this Debian trixie base - see the `"moby": false` note above.

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
