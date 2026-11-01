# Pin the platform and runtimes, float the tools

Keeping a long-lived agent runtime or devcontainer current had become toil.
In place it took `sudo apt upgrade` and `brew upgrade`, two commands with different privilege models.
Across releases it was worse: a Renovate bump of uv's `COPY --from` pin cut an image release, which opened a PR in the Homebrew tap, which needed a `brew upgrade` on the host, which needed a `msb reset` to reach the runtime (ADR-0021: "a runtime only picks up a newer published image at reset").
uv was the only tool driving that cascade; claude-code, gh, starship and dive already floated at build time, and mise and chezmoi floated too, unnoticed.

**Decision: only the platform and the language runtimes are pinned; every tool and language manager floats, and one mise command brings all of them current in place.**

- **Pinned**: the `debian:trixie-slim` release and the default Node major (ADR-0020). Renovate bumps them and they change only through an image release.
- **Floating**: everything else. No version is declared in this repo; the image carries whatever its install source offered at build time, as a floor, and every build also runs a full Debian upgrade so the base layer is current trixie.
- **One declaration**: the shipped mise system config, `/etc/mise/config.toml`, lists the Node pin, every floating mise tool under `[tools]`, every floating apt package under `[bootstrap.packages]`, and a `bootstrap` task running `apt-get full-upgrade`. The build installs from it with `mise bootstrap --yes`; the Containerfile keeps only the package sources (the mise extrepo, Anthropic's apt repo and its key check, the Homebrew installer).
- **One upgrade command**: `mise bootstrap --upgrade`, run by hand. It is never run automatically on attach or start, because bringup is fast, idempotent convergence (ADR-0021) and an upgrade is neither.

Which installer a floating tool gets turns on whether its own release cadence matters:

| Installer                     | Tools                                       | Why                                                                         |
| ----------------------------- | ------------------------------------------- | --------------------------------------------------------------------------- |
| mise tool (upstream binaries) | uv, gh, chezmoi, starship, dive             | Upstream cadence matters; Debian's `gh` lags far behind.                    |
| apt, vendor repo              | claude-code                                 | Anthropic's signed `stable` channel, already the vendor's newest stable.    |
| apt, Debian                   | mise, vim, bubblewrap, git, curl, zsh, sudo | System plumbing; Debian's version is fine, and mise cannot install itself.  |
| Homebrew                      | nothing declared                            | Kept installed for the operator's own ad-hoc use and Mac parity (ADR-0006). |

The mise shims directory goes on the image's `ENV PATH`, ahead of the system directories.
Before this, shims were wired only through `/etc/zsh/zshenv` and `/etc/profile.d` (ADR-0008), and measured on the dev image `command -v node` returned nothing under `sh -c` and `bash -c`.
That was a latent bug for Node and would have broken every tool moved to mise: `dotfiles-bootstrap` is `#!/bin/sh` and calls chezmoi, and a consumer's `RUN uv sync` runs under `/bin/sh -c`.
The zshenv and profile.d lines stay, since Debian's `/etc/profile` rewrites `PATH` for login shells.

## Verified before deciding

All run in the locally built dev image (or bare `debian:trixie-slim` with mise from extrepo), as `vscode`, with passwordless sudo and no TTY:

- `mise bootstrap --upgrade --yes` upgraded a mise tool seeded at an old version (uv 0.8.0 to 0.13.6) into the shared `MISE_DATA_DIR`, still owned by `vscode`, so ADR-0008's layout holds. It ran declared apt packages through `sudo apt-get install --only-upgrade` and declared brew formulae through brew. Exit 0, no prompts.
- That apt step upgrades only the declared names, not their dependencies or the base layer - the reason the `bootstrap` task exists. A `[tasks.bootstrap]` defined in the system config ran from a directory with no project config.
- The Node pin held: mise reported `node 24.22.2 → 26.13.0` as available but outside the configured range, and left it.
- chezmoi as a mise tool, with the shims on `PATH`: `dotfiles-bootstrap` under `sh` exited 0 cold and warm and applied the dotfiles; `sudo` resolved the shim through `secure_path`.
- mise installs claude-code (`aqua:anthropics/claude-code`) and brew formulae, but not Homebrew itself: its built-in brew manager created the prefix and poured a bottle with no `brew` binary afterwards.

## Considered options

- **Pin everything, batch Renovate weekly.** Fewer cascades, but still one per week, and still a reset to receive them; it treats the symptom.
- **Pin the managers too (mise, chezmoi).** Pinning mise is like pinning npm or uv - it is the tool, not the runtime - and the dev image's CI tests its wiring on every build anyway.
- **claude-code from mise.** About a week fresher (2.1.316 against the stable channel's 2.1.309 on the day of the decision), with no sudo, but verified only by a sha256 checksum rather than Anthropic's signing key. Rejected: the upgrade command handles sudo anyway, so the only gain is freshness, and the binary runs agents as root inside the runtime.
- **Not baking floating tools at all, installing them at first boot.** Always fresh, but every new runtime and devcontainer would need the network and pay the install time before it worked.
- **A faster-moving distribution (Wolfi, Fedora).** Under this rule the distribution supplies only libc and base libraries, and the build-time full upgrade picks up Debian's security fixes. Wolfi is not a family the common-utils feature targets (ADR-0005), and Fedora's roughly 13-month lifecycle forces a yearly major bump.
- **`unattended-upgrades` or upgrading on attach.** Removes the toil but makes the environment change underneath the operator, and an offline attach would fail.
- **A hand-rolled `upgrade-floating` script.** The fallback if `mise bootstrap` had failed its test; it did not, and mise's own command is the established tool.

## How the operator stays current

| Where                                | Command                                             | What it does                                                                                |
| ------------------------------------ | --------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| inside a devcontainer or runtime     | `mise bootstrap --upgrade`                          | every floating mise tool, every declared apt package, then a full Debian upgrade            |
| same, for formulae installed by hand | `brew upgrade`                                      | the operator's own Homebrew formulae; the image declares none                               |
| host, only to take a newer image     | `brew upgrade`, then `launch-agent-runtime --reset` | the launcher's image pin; optional, since the runtime's tools already stay current in place |

Nothing upgrades in place unattended.
Unattended are only Renovate PRs for the pinned set, the newest floating versions every image build picks up as a side effect, and mise pruning the versions it replaced.
claude-code does not self-update: apt installs don't.

## Consequences

- **A breaking release.** `/bin/uv`, `/bin/uvx`, `/usr/bin/gh` and `/usr/local/bin/chezmoi` are replaced by mise shims, Homebrew no longer carries `starship` or `dive`, and uv floats. A consumer hardcoding a path or relying on the image's uv version breaks.
- **Image releases stop being something to chase.** A new image matters only for the pinned set and for a fresher floor; a long-lived runtime gets everything else from the upgrade command.
- **Two builds from the same commit can differ.** That is the price of floating, accepted because CI tests every build.
- **The floor goes stale between merges.** There is no scheduled rebuild; a fresh environment from an old image is one command away from current. Revisit if stale-floor starts become a real annoyance.
- **Glossary**: _pinned_ and _floating_ are defined there.
