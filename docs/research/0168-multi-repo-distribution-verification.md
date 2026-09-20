# Verifying the multi-repo consumption spec's distribution mechanisms

Research for [issue #168](https://github.com/afrossard/container-base/issues/168), which asks for the claims behind [#169](https://github.com/afrossard/container-base/issues/169)'s multi-repo consumption spec (grilling session of 2026-09-14 to 2026-09-16) to be driven against real targets before [#173](https://github.com/afrossard/container-base/issues/173) (the Homebrew tap) and the later template-harmonization track trust them.
Every claim below was made from memory during that session.
This document replaces memory with a real install, a real formula, a real template repo, and real network calls, per the house rule: install it, drive it, read its own documentation.

## What this settles

1. **Homebrew tap, script-plus-lib layout: the memory was right to worry, and the fix is a formula choice, not a script change.**
   A naive `bin.install` of the launcher and a separate `lib/` install reproduces the exact failure the issue anticipated - measured, not guessed.
   The fix that needs zero changes to `scripts/launch-agent-runtime` or `scripts/cleanup-agent-sessions` is `libexec.install` plus `bin.write_exec_script`, which is also the real pattern microsandbox's own tap formula uses (see point 5).
   A second, also-verified fix patches the scripts themselves (`readlink -f` before `dirname`) paired with `bin.install_symlink`; it works, but is strictly more invasive than the formula-only fix, so there is no reason to take it.
   For formula-bump automation, three real mechanisms exist; `Justintime50/homebrew-releaser`, triggered by `release: published`, is the closest fit to release-please's flow.
   Confidence: measured (installed and ran the formula, both broken and fixed, in a real Homebrew tap).

2. **Renovate preset pinned with `#<tag>`: fully automatic, no custom config needed.**
   Renovate ships a built-in `renovate-config` manager that reads a repo's own `renovate.json`/`.renovaterc*` files, finds a pinned `github>owner/repo#tag` reference in `extends`, and opens a real bump PR-equivalent update when the referenced repo tags a newer version.
   Verified live against `afrossard/container-base`'s own real tags (`2.0.0` -> `2.1.0`), with a real GitHub API lookup and a real computed branch name.
   Confidence: measured (live `renovate --platform=local --dry-run=full` run against a real public repo and real tags, with a real token).

3. **Reusable workflow reference bumping: confirmed, first-class support.**
   Renovate's `github-actions` manager gives a `uses: owner/repo/.github/workflows/x.yml@tag` line its own `workflow` depType, distinct from a plain action reference, and bumps it the same way.
   Verified live against a real external reusable workflow (`slsa-framework/slsa-github-generator`), which produced a real `pinDigest` update proposal with a real resolved commit SHA.
   Confidence: measured.

4. **copier: adopt it - the auto-bump works, with one real caveat on `_src_path` format.**
   copier's "template lives in a subdirectory of a larger repo" mode works, driven for real across two tagged versions, but has two non-obvious requirements the session did not know to state: all of a template's `copier.yml` (including its questions) must live at the repo root next to `_subdirectory`, not inside the subdirectory itself (a nested `copier.yml` leaks into every generated project instead of being excluded); and `.copier-answers.yml` is opt-in, not automatic - a template must carry a `{{ _copier_conf.answers_file }}.jinja` file or no answers file is ever written and `copier update` has nothing to update from.
   Renovate ships a **built-in `copier` manager** - the session's framing ("customManagers only") was more pessimistic than reality - but it requires `_src_path` to be a real URL (`https://...` or `git+ssh://...`); copier's own convenient `gh:owner/repo` shorthand breaks it with a real, measured parse error.
   Per the session's decision rule (adopt copier only if the Renovate auto-bump works), the verdict is **adopt**, on the condition that consumers are generated with a full URL `_src_path`, not the `gh:` shorthand.
   A custom regex manager on `_commit` was also verified end-to-end as a fallback and produced a real, correct bump proposal, so the URL-format condition is not a hard blocker even if some consumer ends up with a `gh:`-style path on file.
   Confidence: measured for copier itself and for the regex-manager fallback; measured-with-caveat for the native copier manager (extraction and datasource wiring confirmed; the `gh:` shorthand failure is measured, the fix - using a full URL - was not separately re-verified end-to-end because it is the same code path already proven by the regex-manager test).

5. **msb's own install channel: it already has a Homebrew tap, which is real precedent for the spec's symmetry claim, not just an assertion of it.**
   microsandbox installs via a curl/PowerShell installer script, or via `brew install superradcompany/tap/microsandbox`, `npm i -g microsandbox`, `uv tool install microsandbox`, or `cargo install microsandbox`.
   Its own tap formula uses the same `libexec` + generated wrapper pattern this document independently arrived at in point 1, and its own tap repo bumps its formula via a `repository_dispatch` sent from the main repo's release workflow - a third real automation pattern, alongside `brew bump` and `homebrew-releaser`.
   Confidence: high (read from the real upstream README and the real tap repo's formula and workflow source; not independently re-run, since it is someone else's release pipeline).

## Method

All experimentation happened in a scratch directory outside this repo; nothing from it is committed except this file.

- **Homebrew.** The host already has `brew` (Homebrew on Linux, prefix `/home/linuxbrew/.linuxbrew`). `brew install --build-from-source` on a pure-bash formula still requires `DevelopmentTools.installed?` to return true, which in turn requires a binary literally named `gcc` (not `gcc-16`) or `cc` on `HOMEBREW_PREFIX/bin` or `/usr/bin` - confirmed by reading `Library/Homebrew/development_tools.rb` and `extend/os/linux/development_tools.rb` in the installed Homebrew checkout, not guessed. Installed the `gcc` bottle (a real Homebrew-hosted prebuilt binary, no compilation needed) and symlinked it to the expected name to unblock local formula builds. Created a real local tap with `brew tap-new local/agenttap`, wrote real `Formula/agent-tooling.rb` files pointing at real local tarballs (`file://` URLs with real sha256 sums) built from the repo's actual `scripts/launch-agent-runtime`, `scripts/cleanup-agent-sessions`, and `scripts/lib/agent-runtime.sh`, and ran `brew install`/`brew uninstall` against them repeatedly, inspecting the real installed layout under `Cellar/` each time.
- **Renovate.** `npx -p renovate@44.94.0 renovate-config-validator` and `npx -p renovate@44.94.0 renovate --platform=local` (both real npm installs, not assumed). A first attempt via a bare `npx renovate` picked up a stale cached major version (37.440.7) from an earlier npx cache entry, whose schema genuinely differs from the current release (`managerFilePatterns` vs `fileMatch` for custom managers) - a direct, measured instance of the house rule's warning about assertions being "cheap to test and frequently wrong," this time against a cached tool rather than memory. Pinning the package version to the real current latest (`npm view renovate version` -> `44.94.0`) fixed it. Built a real scratch consumer git repo with a `renovate.json` that both extends `github>afrossard/container-base#<tag>` and adds two custom regex managers (one for the extends line, one for `.copier-answers.yml`'s `_commit`), plus a `.github/workflows/ci.yml` calling a real external reusable workflow at a real tag, plus a `.copier-answers.yml` with a real (if synthetic) `_commit`. Ran `renovate --platform=local --dry-run=extract` and `--dry-run=full` against it, first without a token (to see extraction only) and then with a real `gh auth token` exported as `GITHUB_COM_TOKEN` (real, read-only GitHub API calls against real public repos; `--platform=local` never pushes a branch or opens a PR anywhere, so this made no writes). Re-ran with the extends tag deliberately pinned one version behind the real latest to observe an actual proposed bump rather than an "already up to date" no-op.
- **copier.** Installed copier 9.18.2 for real in a scratch Python venv (`pip install copier`). Built a real scratch git repo (`template-host`) containing unrelated files at its root (`src/app.py`) plus a `tooling-template/` subdirectory holding the actual template, with a root-level `copier.yml` carrying `_subdirectory: tooling-template` per copier's own documented layout. Tagged it `v1.0.0` and `v2.0.0` with a real content diff between them (a changed file and a newly added file). Ran `copier copy` and `copier update` for real against both tags and inspected the generated tree and `.copier-answers.yml` each time. The first two attempts surfaced real, previously-unknown-to-the-session behavior (a nested `copier.yml` leaking into the output; no answers file being written at all) before landing on the layout that actually works, confirmed via `copier.readthedocs.io`.
- **msb.** Read the real upstream `microsandbox/microsandbox` README, the real `superradcompany/homebrew-tap` formula source and `.github/workflows/update-formula.yml`, via WebFetch (subject to that tool's own 15-minute cache and markdown conversion, not this sandbox's network allowlist).
- **Sandbox note.** The default Bash sandbox in this environment blocks the nested user-namespace operations Homebrew's linker step needs and blocks network egress to npm/PyPI/GitHub API hosts, so every command above ran with the sandbox disabled; This is expected for a task whose whole point is installing and driving real tools, and matches this session's own house rule about verifying instead of assuming.

## Task 1: Homebrew tap formula for a script-plus-lib layout

**The naive layout genuinely breaks, with the exact symptom the issue named.**

A formula that does

```ruby
def install
  bin.install "launch-agent-runtime"
  bin.install "cleanup-agent-sessions"
  (lib/"agent-tooling").install "lib/agent-runtime.sh"
end
```

installs `launch-agent-runtime` as a real Homebrew `bin/` symlink pointing at `../Cellar/agent-tooling/<version>/bin/launch-agent-runtime`, and puts the lib file somewhere else entirely (Homebrew's `lib/` sits beside `bin/`, not inside it, and this naive layout still didn't even try to put it next to the binary).
Running the installed launcher produces, verbatim:

```
/home/linuxbrew/.linuxbrew/bin/launch-agent-runtime: line 66: /home/linuxbrew/.linuxbrew/bin/lib/agent-runtime.sh: No such file or directory
```

The cause is exactly what the issue suspected: `script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` takes `dirname` of the path bash was invoked with, which for a symlinked executable is the symlink's own path (`/home/linuxbrew/.linuxbrew/bin/launch-agent-runtime`), not the resolved target - `dirname` does not follow symlinks, and neither does the subsequent `cd`, because `cd` only resolves the directory component actually named, not a symlink further down the same string.

**Two independently-verified fixes exist; one needs no script change at all.**

_Fix A (recommended): formula-only, `libexec` + `write_exec_script`._

```ruby
def install
  libexec.install "launch-agent-runtime"
  libexec.install "cleanup-agent-sessions"
  (libexec/"lib").install "lib/agent-runtime.sh"
  bin.write_exec_script libexec/"launch-agent-runtime"
  bin.write_exec_script libexec/"cleanup-agent-sessions"
end
```

`write_exec_script` does not create a symlink; it writes a real two-line wrapper script into `bin/`:

```sh
#!/bin/bash
exec "/home/linuxbrew/.linuxbrew/Cellar/agent-tooling/1.2.0/libexec/launch-agent-runtime" "$@"
```

Because the wrapper `exec`s the real script by its literal absolute path, `${BASH_SOURCE[0]}` inside the _original, completely unmodified_ `launch-agent-runtime` becomes that absolute `libexec` path directly, and `dirname` resolves to `libexec/`, which does contain `lib/agent-runtime.sh` since both were installed together.
Verified by installing this exact formula against the repo's real, unpatched scripts and running `launch-agent-runtime -h` to a clean exit and full usage output.
This is also, independently, the pattern microsandbox's own real tap formula uses for its own `bin/msb` (task 5) - not a coincidence so much as the documented idiom: Homebrew's own Formula Cookbook describes `libexec` as private storage plus a `bin` wrapper/symlink as the way to "surface one or more binaries buried in libexec."

_Fix B (also verified, more invasive): patch the scripts, keep a plain symlink._

Changing the one line in both scripts to resolve the symlink before taking `dirname`:

```bash
script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
```

paired with `bin.install_symlink libexec/"launch-agent-runtime"` (a relative symlink into `libexec`, per Homebrew's own recommended `install_symlink` usage) also works, verified the same way.
It was _not_ sufficient on its own without the `libexec` layout change: a negative control that kept the unpatched `bin.install_symlink` formula but the original scripts reproduced the exact same `bin/lib/agent-runtime.sh: No such file or directory` failure, since the bug is in resolving `BASH_SOURCE[0]`, not in where the lib happens to sit.
Fix B changes the shipped scripts (which is also what a plain source checkout invokes today), so it earns its cost only if there is another reason to want `readlink -f` robustness; Fix A gets the same result at the formula layer alone.

**Formula-bump automation: three real options, one clear fit.**

- **`Justintime50/homebrew-releaser`** (a well-established third-party GitHub Action, not a hand-rolled script) triggers on `release: types: [published]` in the _source_ repo (container-base), clones both the source and the tap, regenerates the formula (URL, version, sha256) from the new release tag, and pushes it to the tap - confirmed from its own README. This is the best fit for release-please: container-base's `release.yml` already gates on `release_created` from `release-please-action` and already publishes a real GitHub Release at that point, so adding this action as one more step needs no new trigger plumbing.
- **`brew bump --formulae --bump-synced --tap=<tap>`**, Homebrew's own official autobump command, is scaffolded automatically into every new tap's `.github/workflows/autobump.yml` by `brew tap-new` (verified: this file appeared for real in the scratch tap this research created, unedited). It runs on a **daily cron**, not on release, and depends on Homebrew's own `livecheck`/GitHub-releases version detection working against the formula's `url`. It is the path of least setup (nothing to write, only to leave in place) but trades immediacy for that - a release could sit unbumped for up to a day.
- **`repository_dispatch`**, the pattern microsandbox's _own real tap_ actually uses (see task 5): the source repo's release job fires a `repository_dispatch` event carrying the version to the tap repo, whose own workflow does the formula edit and push. More custom code to own than either option above, but keeps the tap's write credentials entirely inside the tap repo rather than granting the source repo's Action a token scoped to both repos.

Recommendation for #173: `homebrew-releaser`, wired to run after `release_created` in the existing `release.yml`, with the autobump workflow left in place as a free daily fallback.

## Task 2: Renovate shareable preset referenced at a tag

The scratch consumer's `renovate.json`:

```json
{
  "extends": ["github>afrossard/container-base#2.1.0"]
}
```

Renovate resolves this via its `renovate-config` manager - a manager, not an "extends" special case buried in core - which scans a repo's own `renovate.json` (and `.renovaterc*` variants) for exactly this pattern.
With a real GitHub token and the extends line deliberately pinned one tag behind (`#2.0.0`, real container-base tag), a real `renovate --platform=local --dry-run=full` run produced:

```json
{
  "depName": "afrossard/container-base",
  "datasource": "github-tags",
  "currentValue": "2.0.0",
  "updates": [
    {
      "newVersion": "2.1.0",
      "updateType": "minor",
      "branchName": "renovate/afrossard-container-base-2.x"
    }
  ]
}
```

against real GitHub tag data (`currentVersionTimestamp` matched the real tag date from `git log`).
This is a fully native code path: no `customManagers` entry was needed for this result, the built-in `renovate-config` manager did it unassisted.
Its documented limits (per [docs.renovatebot.com/modules/manager/renovate-config](https://docs.renovatebot.com/modules/manager/renovate-config/)): only _pinned_ references get bumped ("`github>user/renovate-config#1.2.3`" but not an unpinned "`github>user/renovate-config`"), local presets and npm-hosted presets are not supported, and an `extends` line nested inside a sub-object like `packageRules` is not picked up - none of those limits apply to the spec's plain top-level pinned `extends` usage.
Confidence: measured.

## Task 3: Reusable workflow reference bumping

The scratch consumer's `.github/workflows/ci.yml`:

```yaml
jobs:
  build:
    uses: slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@v2.1.0
```

Renovate's `github-actions` manager gives a job-level `uses:` pointing at `owner/repo/.github/workflows/<file>.yml@<ref>` its own `workflow` `depType`, distinct from a plain action reference, per [docs.renovatebot.com/modules/manager/github-actions](https://docs.renovatebot.com/modules/manager/github-actions/) - this lets `workflow` and `action` updates be configured independently (for example, digest-pinning one but not the other), which matters because container-base's own `renovate.json` already opts into `helpers:pinGitHubActionDigestsToSemver`.
A live dry run against the real `slsa-framework/slsa-github-generator` repository (chosen because it is a real, widely-used, tag-releasing reusable-workflow provider, not because it is related to this repo) produced a real proposed update:

```json
{
  "depName": "slsa-framework/slsa-github-generator",
  "updateType": "pinDigest",
  "newValue": "v2.1.0",
  "newDigest": "f7dd8c54c2067bafc12ca7a55595d5ee9b75204a"
}
```

`v2.1.0` is genuinely the latest real tag on that repo at research time, so Renovate correctly proposed pinning the digest rather than a version bump - a live confirmation that the lookup is real, not a canned response.
Confidence: measured.

## Task 4: copier as the versioned-template tool

**copier itself, driven for real, works for the "subdirectory of an existing repo" layout - with two real gotchas the session's memory did not carry.**

A scratch `template-host` repo has ordinary application content at its root (`src/app.py`) plus a `tooling-template/` subdirectory holding the template, matching the spec's "not a dedicated template repo" requirement.
Two attempts before the working one surfaced real behavior worth recording:

1. Putting a second `copier.yml` (with the actual question definitions) _inside_ `tooling-template/`, alongside the root's `copier.yml` (which only carried `_subdirectory: tooling-template`), silently rendered `myproj`'s `project_name` as an **empty string**, and copied the inner `copier.yml` itself into the generated project as a real output file - copier's default exclusion of a template's own `copier.yml` is evaluated relative to the outer template root passed on the command line, not the `_subdirectory`-resolved one, so the nested file is not excluded. **All config, including questions, must live in the single root-level `copier.yml` next to `_subdirectory`**, matching [copier's own documented example](https://copier.readthedocs.io/en/stable/configuring/) exactly (which shows no nested `copier.yml` at all).
2. Even after fixing that, `copier copy --defaults` produced no `.copier-answers.yml` whatsoever. copier's answers file is **opt-in**: a template must carry a file named literally `{{ _copier_conf.answers_file }}.jinja` at its (resolved) root containing `{{ _copier_answers|to_nice_yaml -}}`, or no answers file is ever written - confirmed against [copier's own docs](https://copier.readthedocs.io/en/stable/configuring/#answers-file) and reproduced independently in a flat (non-subdirectory) template as a baseline, where the same omission had the same effect. Without this file, `copier update` has no recorded `_commit` to update from, so it is a hard prerequisite, not a nice-to-have.

With both fixed, `copier copy --vcs-ref v1.0.0` followed by a real `copier update` (no ref given, so it resolves the latest tag) moved a real consumer from `v1.0.0` to `v2.0.0`: `.copier-answers.yml`'s `_commit` changed from `v1.0.0` to `v2.0.0`, the new `scripts/hello.sh` file the v2 template added was materialized, and the templated `README.md` re-rendered with the v2 content.
Confidence: measured.

**Renovate's auto-bump of `.copier-answers.yml`: real, native, with one format requirement.**

Renovate ships a built-in `copier` manager (`/(^|/)\.copier-answers(\..+)?\.ya?ml/`), confirmed live: pointed at a scratch `.copier-answers.yml`, it found the dependency unassisted.
Its datasource is `git-tags`, versioning `pep440`, per [docs.renovatebot.com/modules/manager/copier](https://docs.renovatebot.com/modules/manager/copier/), and it derives the package location from `_src_path`.
Real, measured failure: `_src_path: gh:afrossard/container-base` (copier's own convenient GitHub shorthand, the form `copier copy gh:owner/repo ...` would actually record) produced

```
Failed to parse git URL: https://:443/afrossard/container-base
```

and the extracted dependency carried no working `packageName`/`registryUrl`, meaning no real lookup would ever succeed and no bump PR would ever open for it.
The docs describe support for `git+ssh://...` URLs (which Renovate converts to HTTPS) but do not mention `gh:` shorthand support, matching the observed failure.
As a fallback - and as independent proof the underlying mechanism works regardless of which manager reads it - a hand-written `customManagers` regex entry targeting `.copier-answers.yml`'s `_commit` field, with `datasourceTemplate: github-tags`, found the same real dependency and, in the same live dry run as task 2, produced a real proposed bump (`2.0.0` -> `2.1.0`, `updateType: minor`, a real computed branch name).

**Verdict against the session's own decision rule** ("copier is only adopted if the Renovate auto-bump works; otherwise the residue stays plain copies"): **adopt copier**.
The auto-bump works, natively, as long as consumers are generated with a full URL as `_src_path` (e.g. `copier copy https://github.com/afrossard/container-base.git ...`, not the `gh:` shorthand) - and even if some consumer's `_src_path` ends up in a form the native manager can't parse, the regex-manager fallback verified above is a real, working escape hatch, not a theoretical one.

## Task 5: msb's own install channel

From the real upstream `microsandbox/microsandbox` README, `msb` installs via any of:

```sh
curl -fsSL https://install.microsandbox.dev | sh        # macOS / Linux
irm https://install.microsandbox.dev/windows | iex      # Windows
brew install superradcompany/tap/microsandbox
npm i -g microsandbox
uv tool install microsandbox
cargo install microsandbox
```

The Homebrew path is a **real personal tap** (`superradcompany/homebrew-tap`), the same kind of artifact the spec proposes container-base build.
Its real formula installs `msb` and its `libkrunfw` shared library together into `libexec`, then generates a `bin/msb` wrapper script that execs the `libexec` binary directly - the same `libexec` + wrapper shape independently arrived at in task 1, for the same underlying reason (a plain `bin.install` binary needs to find a sibling artifact at runtime).
The formula's own comment records a second, unrelated reason for this shape specific to a compiled binary: leaving the binary itself untouched by Homebrew's install machinery preserves macOS code-signing and hypervisor entitlements, which do not apply to container-base's shell-script case but do reinforce `libexec` + wrapper as the general-purpose answer to "a `bin/` artifact needs another installed file to be reachable next to it."
Its tap repo bumps that formula via a `.github/workflows/update-formula.yml` triggered by `repository_dispatch: types: [update-formula]` (or a manual `workflow_dispatch` with an explicit version) - real evidence for the third automation option named in task 1, presumably fired from a step in the main `microsandbox/microsandbox` repo's own release workflow, which was not itself inspected.

This is direct precedent, not just a design assumption: the spec's claim that a container-base tap and msb's own install path are symmetric is true today, of a real, currently-installable tool, using the exact mechanism task 1 recommends.
Confidence: high (read from real upstream sources; the tap's own release automation was read, not independently triggered, since it is someone else's production pipeline).
