# Known consumers pending migration

These repos currently build FROM upstream images directly and hand-roll the setup this repo now owns.
Once the dev image is published, migrate each devcontainer to `FROM ghcr.io/afrossard/container-base:<version>-dev`:

- **`default-vscode-project`** - `Containerfile` (FROM `python:3.14-slim-trixie`) and `.devcontainer/Containerfile` (FROM `mcr.microsoft.com/devcontainers/python:3-trixie`, hand-rolled Homebrew bootstrap to drop once the dev image covers it).
- **`homelab-kube`, `homelab-etl`, `homelab-fun`, `actual-budget-transformer`** - the four sibling repos named in dotfiles ADR-0001 as the source of the devcontainer drift this repo exists to fix.

Every migration must delete `UV_PYTHON_DOWNLOADS=0` from `devcontainer.json` (ADR-0006).
All five set it, and on this base it prevents `uv` from finding any Python.

Every migration should also expect `docker-outside-of-docker`'s default options to fail on this Debian trixie base: pass `"moby": false` in the feature's options.
Its default `moby: true` path installs `moby-cli`, which trixie's apt repositories don't carry.
