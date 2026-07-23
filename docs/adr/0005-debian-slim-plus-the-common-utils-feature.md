# Debian slim plus the common-utils feature, not the devcontainers base image

Every consumer devcontainer today builds on `mcr.microsoft.com/devcontainers/base` or its `python` sibling, so inheriting from it was the obvious path.
It is disqualified by measurement: that image ships its own `~/.zshrc` (4018 bytes of oh-my-zsh), `~/.zprofile`, `~/.oh-my-zsh` and `~/.bashrc` for both `vscode` and `root`, and `dotfiles` ADR-0006 says `~/.zshrc` has exactly one writer.
We build on `debian:trixie-slim` and apply the `common-utils` devcontainer feature with its shell customization switched off.

## The measurement

Run against the real `dotfiles` repo with no TTY, which is the condition every container start actually has:

| parent                                        | result                                                         |
| --------------------------------------------- | -------------------------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:trixie` | `.zshrc already exists?` then exit 1, nothing applied          |
| `debian:trixie-slim` + `common-utils`         | exit 0, fully applied, `~/.ssh` at 700, `~/.ssh/config` at 600 |

chezmoi's `lessInteractive` (`dotfiles` ADR-0003) prompts on any target it did not write, finds no TTY, and fails.
The failure is silent in the sense that matters: the container starts, and the user simply has none of their configuration.

A second instance of the same trap was found and is why the chezmoi binary is installed system-wide.
`dotfiles`' generated `install.sh` installs chezmoi to `~/.local/bin` when it is not already on `PATH`, which creates `~/.local`, which chezmoi then prompts about, which fails for want of a TTY.
With chezmoi already on `PATH` the installer short-circuits and never touches `$HOME`, so the VS Code `dotfiles.repository` path succeeds unmodified.

## Considered options

Inheriting from `devcontainers/base` and deleting its `$HOME` was the alternative, and it is only four `rm` lines.
Rejected because it pays 354 MB to acquire an opinion we then discard, and because a parent bump can silently reintroduce a file that breaks every container's dotfiles again.

Hand-rolling the whole base on slim was the first recommendation here and it was wrong.
The objection that answered it: we would then own `common-utils`' 45-package list forever, including the entries nobody remembers the reason for (`libkrb5-3`, `libgssapi-krb5-2`, `libicu*`, `liblttng-ust*`, `locales`, `manpages`).
Using the feature rather than copying it is the established mechanism, and Features are part of the Development Containers Specification rather than merely a popular convention.

What we would actually have been reimplementing is smaller than it looks, which is worth recording so the question is not reopened from memory.
Of `common-utils`' 648 lines, roughly 200 target RedHat and Alpine, which ADR-0003 already rules out, and roughly 110 are the oh-my-zsh and rc-file seeding that breaks us.
The genuinely valuable part is the package list and about 40 lines of user and sudo creation.

## Consequences

- The image is built by `@devcontainers/cli`, not by plain `docker build`, so `devcontainer.json` is as load-bearing as the Containerfile and CI needs Node. Multi-arch was verified through it: `--platform linux/amd64,linux/arm64` produces both.
- The feature is pinned to `installOhMyZsh: false`, `installOhMyZshConfig: false`, `installZsh: true`, `configureZshAsDefaultShell: true`, `username: vscode`, `userUid: 1000`, `userGid: 1000`. The zsh options are not cosmetic: `configureZshAsDefaultShell` is the `chsh` that `dotfiles` ADR-0004 requires, and it comes free.
- Three gaps the feature does not cover, each measured: `LANG` is unset and must be set to `C.UTF-8`, which `devcontainers/base` does in its own Dockerfile rather than via the feature; `bubblewrap` is absent despite appearing in the package list, and Claude sandbox mode needs it; `vim` is absent, and four consumer repos install it by hand.
- The `docker-outside-of-docker` feature, which every consumer uses, was verified to work on this base and to leave `~/.zshrc` absent.
- A test must assert that `$HOME` contains no chezmoi-managed file after build. This is the one failure that presents as a working container with missing configuration rather than as an error.
