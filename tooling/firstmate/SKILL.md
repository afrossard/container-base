---
name: provision-firstmate
description: Bring a freshly reset agent runtime up to a working firstmate + no-mistakes captain session by applying and verifying this repo's fixed tooling recipe. Use on a fresh runtime after `launch-agent-runtime --reset`.
---

<!-- model-guard: skip-prose-scan - this file documents the opus/fable policy in prose -->

You are provisioning a fresh agent runtime (ADR-0021).
The runtime's workspace is this repo, `container-base`, so the recipe is already on disk at `~/git/container-base/tooling/firstmate/`.
Your job is to reach a working captain session by **applying the fixed files in that directory and verifying each step**, not by writing new policy.

## Drift protocol - read first

Upstream firstmate and no-mistakes move.
A config location, an installer name, a schema key, or a repo URL in this recipe may no longer match reality.
When a step's verification fails because something upstream moved:

1. **Stop.** Do not improvise a replacement policy and do not carry on.
2. Copy the recipe file **as written** into the new location if the location is all that moved.
3. Open a pull request against `container-base` that edits `tooling/firstmate/<file>` (or this `SKILL.md`) to match the new reality, quoting the upstream evidence - the changelog entry, the renamed script, the new schema doc.
4. Continue only once the copy is in place; leave the recipe edit for review.

Never resolve drift by selecting a barred model tier (opus, fable).

## Step 1 - backends present

- `git --version`, `gh --version`, `node --version` all resolve.
  Node comes from mise (ADR-0020); if it is absent, `mise install` in a directory with a Node pin, or accept the first-run download.
- `gh auth status` reports a login for `github.com`.
  If not, run `gh auth login` and complete it interactively (ADR-0022: credentials are entered inside the runtime, once per reset).
- The docker daemon answers `docker info`.
  `agent-bringup` starts it; if it is down, run `agent-bringup` again.

Verify: all four commands succeed.
On drift: none expected here; escalate if a backend cannot be installed.

## Step 2 - clone firstmate

```sh
git clone https://github.com/kunchenguid/firstmate ~/git/firstmate
export FM_HOME=~/git/firstmate
```

Add `export FM_HOME=~/git/firstmate` to `~/.zshrc.d/firstmate.zsh` (create the directory if absent) so later sessions inherit it.
This runtime's dotfiles are chezmoi-managed with `--force`, reapplied by `agent-bringup` on every attach, not just a fresh reset; a raw append to `~/.zshrc` itself is silently lost on the next attach.
`~/.zshrc.d/*.zsh` is the existing devcontainer drop-in extension point that chezmoi does not manage.
`~/git` is the runtime's own clone convention (`ensure-workspace`/`ensure-tooling`, issue #172), matching the host's `~/git/<repo>` layout - not a bare `~/<repo>`.

Verify: `~/git/firstmate/AGENTS.md` and `~/git/firstmate/bin/` exist.
On drift (repo renamed or moved): find the current URL, clone it, and propose the URL edit to this file.

## Step 3 - install the tool family via firstmate's own consent flow

Firstmate installs its tool family (herdr, treehouse, the axi npm globals) through its own consent-gated bootstrap.
Run it and answer the prompts:

```sh
cd ~/git/firstmate && ./bin/fm-bootstrap.sh
```

Backend: this runtime uses `FM_BACKEND=herdr` (issue #100), installed by `bin/fm-install-herdr.sh`; `tmux` is the fallback if herdr muddies the session.
Export `FM_BACKEND=herdr` in `~/.zshrc.d/firstmate.zsh` (see Step 2 on why not `~/.zshrc` directly).

Then apply the version policy from `tooling/README.md`.
The consent flow is still what installs each tool - never bypass the consent gate - but where it pins a version behind Homebrew's latest, `brew upgrade` that tool to the latest and re-run firstmate's own check.
Verify the latest against firstmate's stated contract: the published protocol floor where firstmate publishes one, observed behaviour where it does not.
Fall back to firstmate's pinned installer only for a tool whose floating latest fails that check.

Verify: each tool in the family resolves on `PATH` and reports a version at or above firstmate's floor.
On drift (bootstrap script renamed, a tool dropped or added): locate the equivalent, note it, propose the recipe edit.

## Step 4 - apply the fixed configuration

Copy each file from `~/git/container-base/tooling/firstmate/` into place, then confirm firstmate or no-mistakes actually reads it.
`<project>` is the managed project clone firstmate makes under `$FM_HOME/projects/`; for this runtime that is `container-base`.

| Copy from            | To                                              | Verify it is read by                                                        |
| -------------------- | ----------------------------------------------- | --------------------------------------------------------------------------- |
| `crew-dispatch.json` | `$FM_HOME/config/crew-dispatch.json`            | a dry-run crew or scout spawn shows harness `claude`, model `sonnet`        |
| `captain.md`         | `$FM_HOME/data/captain.md`                      | firstmate's session-start digest lists the captain preferences file         |
| `no-mistakes.yaml`   | `$FM_HOME/projects/<project>/.no-mistakes.yaml` | `no-mistakes` reports gate mode `no-mistakes` and gate-agent model `sonnet` |
| `captain.sh`         | sourced from `~/.zshrc.d/firstmate.zsh`         | a fresh shell has `type captain`                                            |

For `captain.sh`, add `source ~/git/container-base/tooling/firstmate/captain.sh` to `~/.zshrc.d/firstmate.zsh` (the same drop-in used for `FM_HOME` and `FM_BACKEND` in Steps 2-3; create `~/.zshrc.d/` if absent) and open a new shell.
Do not append to `~/.zshrc` directly - see Step 2 on why it does not survive.

Verify: every row's "verify it is read by" check passes.
On drift (a config path or schema key changed): copy the file unmodified into the location firstmate now reads, then propose the schema edit to `tooling/firstmate/<file>` with the upstream evidence.
Do not hand-edit the applied copy to add policy.

## Step 5 - run the model guard

```sh
no_mistakes_configs=()
while IFS= read -r -d '' f; do
  no_mistakes_configs+=("$f")
done < <(find "$FM_HOME/projects" -maxdepth 2 -name .no-mistakes.yaml -print0 2>/dev/null)

~/git/container-base/tooling/firstmate/model-guard \
  ~/git/container-base/tooling/firstmate \
  "$FM_HOME/config" \
  "$FM_HOME/data/captain.md" \
  "${no_mistakes_configs[@]}"
```

Scan the recipe itself plus the exact locations this recipe applies into - not all of `$FM_HOME`, and not all of `$FM_HOME/data` either.
`$FM_HOME` is firstmate's own source checkout (ADR-0021), so a bare `model-guard "$FM_HOME"` also sweeps firstmate's tracked tests and docs, which legitimately construct or discuss barred-tier strings (`model: opus` fixtures, policy prose) without opting out via `model-guard: skip-prose-scan`.
`$FM_HOME/data` itself is not purely fixed config either: alongside the applied `captain.md`, it accumulates per-task artifact directories (crew/scout report output, named after the task) that just as legitimately discuss the barred-tier policy in prose - observed directly with a code-review report analyzing this very guard's regex.
Scanning the whole directory makes Step 5 permanently non-zero for reasons that have nothing to do with a real selection; scan the applied file itself, `$FM_HOME/data/captain.md`, not its parent.
Use `find` rather than a bare glob for the `.no-mistakes.yaml` lookup: an unmatched glob is a hard error under `zsh`'s default `nomatch`, and no project may be registered yet on a fresh runtime.
Collect `find`'s results into an array via a `-print0`/`read -d ''` loop rather than an unquoted `$(find ...)` substitution: word-splitting an unquoted substitution breaks any project directory name containing a space into multiple nonexistent paths, which `model-guard`'s own root-existence check then silently skips.

It must exit 0.
If it flags a selection, fix that selection to `sonnet` - never to a barred tier - and re-run until clean.

Verify: exit 0.
On drift (the guard flags a file already in scope that this recipe does not manage): that file is a new model-carrying location - add it to the recipe and to the `On drift` list here, do not silence the guard.
On drift (a new applied-config location appears under `$FM_HOME` outside `config/`, `data/captain.md`, and a project's `.no-mistakes.yaml`): this narrower scan misses it silently, unlike a full-tree scan - add the new location to the command above the same way.
Re-run this check after any later change to fleet configuration; it is the standing assertion that nothing has regressed onto a barred tier (issue #143 story 19).

## Step 6 - bring up the captain

```sh
captain
```

Verify: the session starts, its model line shows `sonnet`, firstmate greets as the first mate, and `/bearings` returns a fleet digest.
On drift (the captain no longer starts with a bare `claude` in the firstmate clone): find the current launch command, update `captain.sh` to wrap it with `--model` still pinned, and propose that edit.

## Step 7 - report

Report back:

- each tool installed and its resolved version,
- each verification in steps 1-6 and its result,
- any recipe edits you are proposing for drift, with links to the PRs.
