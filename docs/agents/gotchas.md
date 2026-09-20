# Operational gotchas

Failure modes specific to working in this repo as an agent, not obvious from the code, that have already recurred at least once.

## `msb doctor` reporting `/dev/kvm` missing isn't proof the host lacks KVM

Claude Code's Bash sandbox filters `/dev/kvm` out of what a sandboxed command sees; rerunning `msb doctor` unsandboxed shows it present and read/write.
Retry unsandboxed before concluding the host can't run `msb`.

## A session's own PAT usually can't push to `.github/workflows/`

GitHub gates any push touching `.github/workflows/` behind a `workflow` PAT scope, which a session's own PAT lacks.
This has blocked an agent session's push twice.
The resolution both times: post the diff to the issue, then have a more-privileged session or a human apply, commit, and push it.

## `npm run test:dev` has real, expected failures when run nested inside this repo's own workspace devcontainer

`test/dev/dotfiles-bootstrap.bats` and one `mise install` case in `test/dev/dev.bats` are unreliable when run from inside this repo's own `.devcontainer` - not a regression.
`docker-outside-of-docker` drives the _host_ daemon, so a `docker run -v` from a container-local tmp path doesn't resolve there.
CI runs the suite unnested and is the authoritative signal; reproduce a failure in CI or a non-nested shell before chasing it.

## A session can't measure the guest through its own sandbox wrapper

A session's shell tool runs inside a seccomp/mount-namespace wrapper, so writes, mounts, ownership, and privilege probes describe that wrapper, not the guest: `/` reads read-only and uid/gid mappings look unmapped.
A session that measures those and draws conclusions reports confident nonsense about the runtime and the published image; this burned a full first pass of #100's findings.
Reads are trustworthy; write and privilege conclusions need the wrapper switched off - the same unsandboxed re-run the `/dev/kvm` gotcha above describes.
You can tell the wrapper is present when a sandboxed check calls `/` read-only or shows uids unmapped and an unsandboxed re-run of the same check disagrees.

## A session's working time is capped by a provider quota window it can't see

Without the quota tooling installed, nothing in the runtime surfaces how much runway is left.
The quota scope is all-models, so switching models shares the same window - changing model buys no extra time.
No fallback provider is authenticated in the guest, so hitting the wall is a hard stop, not a routing decision.
Concurrency is the only burn-rate control available.
The quota tooling and its threshold watcher come from the firstmate tooling recipe (#145), which is not built yet.

## `git push` failing with `could not read Username` means the dotfiles apply deleted the credential helper

`gh auth setup-git` writes `credential.https://github.com.helper` into `~/.config/git/config`, and that file is managed by the operator's `dotfiles`.
`agent-bringup` re-runs `dotfiles-bootstrap` on every attach (ADR-0016), and `chezmoi update --apply --force` rewrites the file, so the helper is gone by the next attach - including a bare re-launch with no intervening stop.
`gh auth status` still reports a login throughout, because `gh`'s token lives in `~/.config/gh/hosts.yml`, which `dotfiles` does not manage.
So "`gh` works" is never evidence that git can push; they are separate credentials that fail independently.
Re-running `gh auth setup-git` buys exactly one session.
The workaround that survives an attach is `GIT_CONFIG_GLOBAL=~/.config/git/config.local gh auth setup-git`, which writes into the untracked file the managed config already includes.
The durable fix is in `dotfiles` (afrossard/dotfiles#18); this repo deliberately carries no credential wiring, because the agent image must stay agnostic of any one forge or agent CLI (ADR-0001).
Check the state with `git config --includes --get credential.https://github.com.helper`: without `--includes`, `git config --global --list` hides included files and reports a false negative.
