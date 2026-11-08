# Changelog

## [5.0.1](https://github.com/afrossard/container-base/compare/5.0.0...5.0.1) (2026-11-08)


### Bug Fixes

* **agent:** filter the /proc/modules grep noise from bringup ([#244](https://github.com/afrossard/container-base/issues/244)) ([b60b171](https://github.com/afrossard/container-base/commit/b60b171619cf206dc2dcd1e2f91723bcd48b946f)), closes [#233](https://github.com/afrossard/container-base/issues/233)

## [5.0.0](https://github.com/afrossard/container-base/compare/4.0.4...5.0.0) (2026-11-02)


### ⚠ BREAKING CHANGES

* **dev:** /bin/uv, /bin/uvx, /usr/bin/gh and /usr/local/bin/chezmoi are replaced by mise shims under /usr/local/share/mise/shims; Homebrew no longer carries starship or dive; uv is no longer pinned and floats to its newest release at build time. A consumer hardcoding one of those paths, or relying on the image's uv version, must update.
* **agent:** an existing agent runtime keeps its docker volume at /var/lib/docker, so it must be reset (`launch-agent-runtime --reset`) before it can use an image from this release; until then every docker run and build inside it fails.

### Features

* **deps:** update node.js to v26 ([#221](https://github.com/afrossard/container-base/issues/221)) ([41828f0](https://github.com/afrossard/container-base/commit/41828f0901aa63dbda46667b55ee38fa2fb1229c))
* **dev:** bake mise's zsh completions into the dev image ([#235](https://github.com/afrossard/container-base/issues/235)) ([4518c76](https://github.com/afrossard/container-base/commit/4518c76a10ef4b14d8605c70eb73765b8448c334))
* **dev:** declare Claude Code's apt repository in the shipped mise config ([#232](https://github.com/afrossard/container-base/issues/232)) ([8b85c44](https://github.com/afrossard/container-base/commit/8b85c4483f8ac5f0b2429b1347d5eea667fe37ea))
* **dev:** pin the platform and Node, float the tools, upgrade in place with mise bootstrap ([#230](https://github.com/afrossard/container-base/issues/230)) ([757ec70](https://github.com/afrossard/container-base/commit/757ec70b74f67a5a8637b8f7625efbdd8c5c08a2))
* **launcher:** allow one LAN service through the egress policy with --allow-url ([#236](https://github.com/afrossard/container-base/issues/236)) ([d7e2f9a](https://github.com/afrossard/container-base/commit/d7e2f9a41e8bfaa3cb6f73ac224f89f109c82f5d)), closes [#234](https://github.com/afrossard/container-base/issues/234)


### Bug Fixes

* **agent:** pick the nested dockerd iptables backend at boot ([#224](https://github.com/afrossard/container-base/issues/224)) ([d07abfc](https://github.com/afrossard/container-base/commit/d07abfc10d6046dbb5bf2267415fa24834daa4bc))
* **deps:** update ghcr.io/astral-sh/uv docker tag to v0.13.6 ([#216](https://github.com/afrossard/container-base/issues/216)) ([6beba1b](https://github.com/afrossard/container-base/commit/6beba1b78cf571f32bcc24768a94f84cd272483b))
* **dev:** install libatomic1 so Node 26 runs ([#228](https://github.com/afrossard/container-base/issues/228)) ([74b03da](https://github.com/afrossard/container-base/commit/74b03da355a59c44815e6dde628d6687e2eff3fb)), closes [#223](https://github.com/afrossard/container-base/issues/223)

## [4.0.4](https://github.com/afrossard/container-base/compare/4.0.3...4.0.4) (2026-10-10)


### Bug Fixes

* **dev:** put brew and uv zsh completions on fpath ([#211](https://github.com/afrossard/container-base/issues/211)) ([054b44e](https://github.com/afrossard/container-base/commit/054b44e0b639502435d111e2d73a847ced05e9bd))

## [4.0.3](https://github.com/afrossard/container-base/compare/4.0.2...4.0.3) (2026-10-10)


### Bug Fixes

* **dev:** ship docker-prune-credsstore for macOS-host docker configs ([#208](https://github.com/afrossard/container-base/issues/208)) ([e1bb213](https://github.com/afrossard/container-base/commit/e1bb2134b38f6535607fd00490b0c9058bb4863a))

## [4.0.2](https://github.com/afrossard/container-base/compare/4.0.1...4.0.2) (2026-10-10)


### Bug Fixes

* **deps:** update ghcr.io/astral-sh/uv docker tag to v0.13.0 ([#200](https://github.com/afrossard/container-base/issues/200)) ([8a7d381](https://github.com/afrossard/container-base/commit/8a7d381f55d9c66a6b6ea9a187d11f012dfae29c))

## [4.0.1](https://github.com/afrossard/container-base/compare/4.0.0...4.0.1) (2026-10-03)


### Bug Fixes

* **deps:** update ghcr.io/astral-sh/uv docker tag to v0.12.22 ([#194](https://github.com/afrossard/container-base/issues/194)) ([cde523c](https://github.com/afrossard/container-base/commit/cde523cb31ad98325855510ee1e3ba5eea64d6b5))

## [4.0.0](https://github.com/afrossard/container-base/compare/3.0.0...4.0.0) (2026-09-21)


### ⚠ BREAKING CHANGES

* **launcher:** rename --on-secret-violation to --secret-violation-action ([#190](https://github.com/afrossard/container-base/issues/190))

### Bug Fixes

* **launcher:** rename --on-secret-violation to --secret-violation-action ([#190](https://github.com/afrossard/container-base/issues/190)) ([7393ba1](https://github.com/afrossard/container-base/commit/7393ba1afb3077c41f1051facb107969c2d0476a))

## [3.0.0](https://github.com/afrossard/container-base/compare/2.1.2...3.0.0) (2026-09-21)


### ⚠ BREAKING CHANGES

* the workspace clone moves from /home/vscode/<repo> to /home/vscode/git/<repo>. Existing runtimes keep the old path until their next --reset; nothing migrates it in place.

### Features

* make the tooling repo a boot input and move the workspace under ~/git ([#188](https://github.com/afrossard/container-base/issues/188)) ([78ad350](https://github.com/afrossard/container-base/commit/78ad35081504bf39b40fb5de7ac713bf64f1e4d6))


### Bug Fixes

* **tooling:** point firstmate .zshrc edits at the devcontainer drop-in ([#183](https://github.com/afrossard/container-base/issues/183)) ([bad88a7](https://github.com/afrossard/container-base/commit/bad88a7874d4b780322fc8960a4109b8263d28e2))

## [2.1.2](https://github.com/afrossard/container-base/compare/2.1.1...2.1.2) (2026-09-20)


### Bug Fixes

* **deps:** update ghcr.io/astral-sh/uv docker tag to v0.12.16 ([#177](https://github.com/afrossard/container-base/issues/177)) ([e19639c](https://github.com/afrossard/container-base/commit/e19639ca754a6fde658aba4c8b3f3ea44c3faaae))
* **deps:** update ghcr.io/astral-sh/uv docker tag to v0.12.17 ([#180](https://github.com/afrossard/container-base/issues/180)) ([71a999b](https://github.com/afrossard/container-base/commit/71a999ba15ece7e4d3f80c13405d5da62ff7da59))

## [2.1.1](https://github.com/afrossard/container-base/compare/2.1.0...2.1.1) (2026-09-16)


### Bug Fixes

* **deps:** update ghcr.io/astral-sh/uv docker tag to v0.12.13 ([#162](https://github.com/afrossard/container-base/issues/162)) ([47bc2d5](https://github.com/afrossard/container-base/commit/47bc2d56f90409ecedd9865e4a8b82c196b32b12))
* **deps:** update ghcr.io/astral-sh/uv docker tag to v0.12.15 ([#164](https://github.com/afrossard/container-base/issues/164)) ([463d648](https://github.com/afrossard/container-base/commit/463d648a07f8891eccd24e9d0da8948d892ece76))

## [2.1.0](https://github.com/afrossard/container-base/compare/2.0.0...2.1.0) (2026-09-10)


### Features

* firstmate tooling recipe provisions a fresh runtime ([#158](https://github.com/afrossard/container-base/issues/158)) ([2db5702](https://github.com/afrossard/container-base/commit/2db5702208db55a2da6989870a577156461c71a5))

## [2.0.0](https://github.com/afrossard/container-base/compare/1.0.0...2.0.0) (2026-09-10)


### ⚠ BREAKING CHANGES

* reset on demand, and cleanup stops garbage-collecting pets ([#154](https://github.com/afrossard/container-base/issues/154))

### Features

* reset on demand, and cleanup stops garbage-collecting pets ([#154](https://github.com/afrossard/container-base/issues/154)) ([1cad744](https://github.com/afrossard/container-base/commit/1cad744723d528f472088b650e1d34ccf73caac3))


### Bug Fixes

* **deps:** update ghcr.io/astral-sh/uv docker tag to v0.12.12 ([#155](https://github.com/afrossard/container-base/issues/155)) ([3c3f97c](https://github.com/afrossard/container-base/commit/3c3f97cc46f53b5594e41345d0a68af58f34c741))

## [1.0.0](https://github.com/afrossard/container-base/compare/0.4.2...1.0.0) (2026-09-08)


### ⚠ BREAKING CHANGES

* launch-agent-runtime no longer accepts `--github-token`, `--persist-claude-auth` / `--no-persist-claude-auth`, or `--force`. Authenticate `gh` and `git` inside the runtime; the Claude Code login now persists on the runtime's own disk across stop/start with no flag or volume (ADR-0022). A bare launch never destroys a runtime, so `--force` had nothing left to skip; it returns with `--reset` (issue #146). The generic `--secret` / `--on-secret-violation` passthrough is unchanged.

### Features

* a bare launch resumes the agent runtime; retire launch-time credential flags ([#151](https://github.com/afrossard/container-base/issues/151)) ([58241a6](https://github.com/afrossard/container-base/commit/58241a650617b526208bba8d276896c52b319326))

## [0.4.2](https://github.com/afrossard/container-base/compare/0.4.1...0.4.2) (2026-09-05)


### Bug Fixes

* **deps:** update ghcr.io/astral-sh/uv docker tag to v0.12.10 ([#138](https://github.com/afrossard/container-base/issues/138)) ([55220f9](https://github.com/afrossard/container-base/commit/55220f9762cc125b088b75b912aa9787fbed8dac))

## [0.4.1](https://github.com/afrossard/container-base/compare/0.4.0...0.4.1) (2026-09-02)


### Bug Fixes

* **deps:** update ghcr.io/astral-sh/uv docker tag to v0.12.9 ([#124](https://github.com/afrossard/container-base/issues/124)) ([002d63f](https://github.com/afrossard/container-base/commit/002d63f765a509a20828614c67781839358d52be))

## [0.4.0](https://github.com/afrossard/container-base/compare/0.3.1...0.4.0) (2026-08-31)


### Features

* bake a default Node into the dev image via mise ([#120](https://github.com/afrossard/container-base/issues/120)) ([46c2d43](https://github.com/afrossard/container-base/commit/46c2d43b42557605dd189fd6ce25620b7e00fc79))

## [0.3.1](https://github.com/afrossard/container-base/compare/0.3.0...0.3.1) (2026-08-30)


### Bug Fixes

* **deps:** update ghcr.io/astral-sh/uv docker tag to v0.12.7 ([#112](https://github.com/afrossard/container-base/issues/112)) ([b41c1ef](https://github.com/afrossard/container-base/commit/b41c1ef240ab0495580fa50dd68afa715f744484))
* launcher and cleanup no longer need jq on the host ([#111](https://github.com/afrossard/container-base/issues/111)) ([4c2fae1](https://github.com/afrossard/container-base/commit/4c2fae1aee5f949156e9328ac4683eacb7728cf5))

## [0.3.0](https://github.com/afrossard/container-base/compare/0.2.0...0.3.0) (2026-08-16)


### Features

* lint PR titles against Conventional Commits ([#96](https://github.com/afrossard/container-base/issues/96)) ([5690935](https://github.com/afrossard/container-base/commit/5690935aafdc7e29a35acf9924037c107be6ca59))
* release-please cuts releases and publishes both variants ([#86](https://github.com/afrossard/container-base/issues/86)) ([561e3a0](https://github.com/afrossard/container-base/commit/561e3a09c4483985128310b5d3dc08e05170a17b))


### Bug Fixes

* **deps:** update ghcr.io/astral-sh/uv docker tag to v0.12.5 ([de87066](https://github.com/afrossard/container-base/commit/de8706601b1dff08068bbe0e66b147c5525aa48b))
* reword msb secret placeholder out of two committed files ([#88](https://github.com/afrossard/container-base/issues/88)) ([bd59805](https://github.com/afrossard/container-base/commit/bd5980590a5bd3e4cd6cd677a8feaa6e59cdb704))
* shipped-dependency Renovate bumps release, everything else stays chore ([#98](https://github.com/afrossard/container-base/issues/98)) ([b95f2ae](https://github.com/afrossard/container-base/commit/b95f2ae1857352ba444c22c7b163a550ebe1ded3))

## [0.2.0](https://github.com/afrossard/container-base/compare/0.1.0...0.2.0) (2026-08-16)


### Features

* lint PR titles against Conventional Commits ([#96](https://github.com/afrossard/container-base/issues/96)) ([5690935](https://github.com/afrossard/container-base/commit/5690935aafdc7e29a35acf9924037c107be6ca59))


### Bug Fixes

* **deps:** update ghcr.io/astral-sh/uv docker tag to v0.12.5 ([de87066](https://github.com/afrossard/container-base/commit/de8706601b1dff08068bbe0e66b147c5525aa48b))
* shipped-dependency Renovate bumps release, everything else stays chore ([#98](https://github.com/afrossard/container-base/issues/98)) ([b95f2ae](https://github.com/afrossard/container-base/commit/b95f2ae1857352ba444c22c7b163a550ebe1ded3))

## [0.1.0](https://github.com/afrossard/container-base/compare/0.0.9...0.1.0) (2026-08-15)


### Features

* release-please cuts releases and publishes both variants ([#86](https://github.com/afrossard/container-base/issues/86)) ([561e3a0](https://github.com/afrossard/container-base/commit/561e3a09c4483985128310b5d3dc08e05170a17b))


### Bug Fixes

* reword msb secret placeholder out of two committed files ([#88](https://github.com/afrossard/container-base/issues/88)) ([bd59805](https://github.com/afrossard/container-base/commit/bd5980590a5bd3e4cd6cd677a8feaa6e59cdb704))
