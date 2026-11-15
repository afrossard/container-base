# Known consumers pending migration

These repos currently build FROM upstream images directly and hand-roll the setup this repo now owns.
Once the dev image is published, migrate each devcontainer to `FROM ghcr.io/afrossard/container-base:<version>-dev`:

- **`default-vscode-project`** - `Containerfile` (FROM `python:3.14-slim-trixie`) and `.devcontainer/Containerfile` (FROM `mcr.microsoft.com/devcontainers/python:3-trixie`, hand-rolled Homebrew bootstrap to drop once the dev image covers it).
- **`homelab-etl`, `homelab-fun`, `actual-budget-transformer`** - three of the four sibling repos named in dotfiles ADR-0001 as the source of the devcontainer drift this repo exists to fix; the fourth, `homelab-kube`, migrated in afrossard/homelab-kube#48.

Every migration must delete `UV_PYTHON_DOWNLOADS=0` from `devcontainer.json` (ADR-0006).
All five set it, and on this base it prevents `uv` from finding any Python.

Every migration should also expect `docker-outside-of-docker`'s default options to fail on this Debian trixie base: pass `"moby": false` in the feature's options.
Its default `moby: true` path installs `moby-cli`, which trixie's apt repositories don't carry.

Every migration should drop what the dev image now ships to consumers through its `devcontainer.metadata` label (ADR-0029): `mise trust` and `mise install` in `postCreateCommand`, `safe.directory` and `dotfiles-bootstrap` in `postStartCommand`, `remoteEnv.DOTFILES_REPO`, `waitFor`, and the shared VS Code extensions.
Keep only the repo's own extra steps, such as `npm ci`; they run after the image's.
This applies only from the first release that ships the label, so drop them in the same change as the bump to that release.

Every migration that uses `docker-outside-of-docker` should call `docker-prune-credsstore` from its own `postStartCommand` and drop any hand-rolled copy of it (issue #205).
Opened from a macOS host, the container's `~/.docker/config.json` carries `"credsStore": "desktop"`, whose helper the container lacks, so every `docker pull` fails until the key is removed.
`actual-budget-transformer` carries such a copy in its `.devcontainer/post-start`.
