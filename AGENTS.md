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

The dev-image skeleton stopped growing after issue #8; subsequent work turned toward hardening it for autonomous agent use, tracked under the still-open umbrella issue #13.
Issue #16's survey of community devcontainer hardening practices (`docs/research/0016-community-agent-hardening-practices.md`) produced ADR-0011 (hardening is composed at launch time, not baked into a second image) and ADR-0012 (the isolation substrate as a fifth tier, later superseded).
Issues #17 (a non-root default user) and #19 (a dormant network-egress firewall script) were scoped from that research but never built: #19 closed unimplemented once #20 - its only planned consumer, a hardened devcontainer profile - was itself closed as superseded by the agent-runtime approach below, and #18 (`DISABLE_AUTOUPDATER`) closed alongside it since its payoff depended on #19's allowlist.
#17 remains open.
Issue #21 re-founded the hardening question on a VM substrate instead: `docs/research/0021-vm-microvm-isolation-for-agent-runtimes.md` and ADR-0013 concluded the agent runtime is a disposable per-repo VM, one per agent session, holding its own docker daemon and nothing else.
Issue #22 then ran `apple/container`, microsandbox, and Lima against a draft `-agent` image on the real dev host (`docs/research/0022-vm-tool-experiment-results.md`) and settled on microsandbox, launched with a disk-backed volume for `/var/lib/docker` (msb's default nests overlayfs on overlayfs, which fails a real multi-layer build).
Issue #23 built on both. `images/agent/Containerfile` (ADR-0014) builds `FROM` the published dev image and installs a docker engine of its own via the community `docker-in-docker` devcontainer feature rather than hand-rolled apt/gpg steps - it already handles cgroup v2 nesting, iptables alternative selection, and moby/docker-ce selection as maintained, Renovate-tracked code, the same mechanism `images/dev` uses for `common-utils`.
Its entrypoint starts dockerd via the feature's own `docker-init.sh` (filtering one line of known-harmless noise that only appears under a microsandbox guest specifically, traced with `sh -x` rather than guessed at), then drops the given command to the non-root `vscode` user via `runuser` - dockerd stays root, the task doesn't, and `devcontainer build` was confirmed by experiment to reset the image's own `USER` to root regardless of `containerUser`/`remoteUser`, so the drop has to happen in the entrypoint.
The image itself keeps ADR-0013's no-default-command rule: a missing command run directly against it is a usage error, not a fallback to a standing process.
`scripts/launch-agent-runtime` launches the published image as a microsandbox guest.
It resolves a session name from the repo (`git remote`, falling back to the toplevel directory, falling back to `$PWD`), reuses an existing sandbox for that repo via a `repo=<name>` label rather than a name-prefix guess, refuses to silently replace one that's still running (offering replace, a genuinely separate new sandbox, or abort), and gives each session its own `<name>-docker-data` volume rather than one shared default, since a disk-kind msb volume can only be attached to one running guest at a time.
With no command given it drops into an interactive `zsh` shell (a real tty, `/etc/zsh/zshenv`'s PATH wiring intact) rather than erroring, matching plain `docker run -it`; an explicit command still runs scripted, with no tty.
`scripts/cleanup-agent-sessions` removes stopped sessions for a repo, or with `--name` one specific session (running too, with `--force`), and their paired volumes, asking for confirmation unless `--force` or `--dry-run`.
Both scripts share `repo_name()`/`usage()` via `scripts/lib/agent-runtime.sh`.
CI (`.github/workflows/agent-image.yml`) builds and tests the `-agent` image the same way `dev-image.yml` does, and both publish workflows now skip a variant's rebuild entirely if its own `images/*` directory didn't change since the previous tag (`.github/scripts/changed-since-last-tag.sh`, ADR-0004), verified on a real tag where neither variant had changed and both correctly skipped.
README.md and CONTEXT.md describe three published variants; `0.0.4-agent` is the first real published `-agent` image.

With the image and the launcher in place, a grilling session settled how the runtime is actually used, producing three ADRs and the issue backlog that implements them.
ADR-0017 records the shape being built first: an attended session, a human at the keyboard driving Claude Code in auto mode inside the guest, with the headless shape ADR-0013 describes as the destination rather than an abandoned option - so the launcher's interactive affordances (persisted credentials, sandbox reuse, replace/abort prompts) are deliberate rather than drift from the disposable-VM model.
It also records why auto mode rather than `--dangerously-skip-permissions`: the VM bounds host damage completely and bounds nothing about the GitHub credential and open network a session is deliberately handed, so the two controls cover disjoint risks.
ADR-0015 settles the workspace question ADR-0013 left provisional - a full clone made inside the guest, work leaving as a pushed branch and a pull request, and a fine-grained token scoped to the one repository the runtime already holds, injected via `--secret` so the guest never holds its real value.
Bind mounts are rejected there with evidence rather than by inheritance: `core.hooksPath` is `.husky/_`, in the working tree, so even a mount excluding `.git` hands over host command execution, and a `git worktree` is worse, since `git rev-parse --git-path hooks` resolves to the main checkout's hooks and the worktree's `.git` holds an absolute host path.
ADR-0016 records that the runtime runs `dotfiles-bootstrap` every session, trading reproducibility for the conventions the operator's global `AGENTS.md` carries and this repo's does not.
A ruleset on `main` (issue #31) is applied and verified by demonstration - a direct push with the repo owner's own credential is rejected, which settles the repository-scoped-token case by implication since a token holds strictly less authority.
#31's own last outstanding criterion (force-push on a feature branch with the repository-scoped PAT) was closed out by #34's live-fire test, below.

Issue #34 settled the transport question by direct experiment rather than assumption: `--secret` substitution survives `git push`'s Basic-auth base64 encoding, because microsandbox does host-scoped TLS interception (the scoped host's certificate is reissued by `CN=microsandbox CA`) rather than a literal byte search-and-replace, so the placeholder is rewritten at the semantic, decoded-credential level regardless of encoding.
ADR-0015's placeholder model holds; no SSH deploy key departure was needed.
`scripts/launch-agent-runtime` gained `--on-secret-violation` passthrough (previously only `--secret` forwarded).
A live-fire test against the real repo with a fine-grained PAT (Contents R/W, Pull requests R/W, Issues R/W, Metadata R) confirmed every acceptance criterion: the guest env holds only the placeholder, the agent can push, force-push, open a PR, comment on an issue, and create an issue, a direct push to `main` is rejected, and the real secret cannot reach an out-of-scope host.
One rough edge surfaced along the way: commenting on an issue requires GitHub's `issues=write` and `pull_requests=write` together (surfaced via the `x-accepted-github-permissions` diagnostic response header), and a freshly-minted token 403'd on it despite both being individually demonstrated as granted, until the token's permissions were re-saved on GitHub's side - root cause unconfirmed, most likely a stale permission-evaluation cache.
Issue #40 tracks a separate finding from the same session: this PAT's `Contents:write`, needed to push at all, is also sufficient to merge its own PRs, so nothing at the token or ruleset level stops the agent from merging without human review - accepted behaviorally for now (the agent is only ever instructed to open a PR and stop) rather than closed at the token-scope level.

Issue #32 wires the workspace itself into the launcher: a `workspace-init` script, registered into the guest with `msb run --script-path` and run as the actual launched command (`workspace-init COMMAND...`), clones the repo (a full clone, no `--depth`, no `--ref`, never a bind mount or `--copy-dir` of the host tree - ADR-0015), `cd`s into it, and `exec`s the given command - so the interactive default and an explicit `COMMAND` compose identically, with neither special-cased. Two risks flagged as unverified going in turned out not to bite, checked directly rather than assumed: `/.msb/scripts` is on `PATH` even under the `runuser`-dropped, non-login `vscode` environment `images/agent/entrypoint` hands off to, and the guest's network is already up by the time the clone runs. The default clone URL comes from `git remote get-url origin` (`repo_url()`, alongside the existing `repo_name()`), overridable with `--clone-url`.

Issues #30, #33, and #35 through #37 carry the remaining implementation.

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
