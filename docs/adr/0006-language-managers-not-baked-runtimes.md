# Language managers, not baked runtimes

The dev image carries every language (ADR-0004), which would mean baking a version of each and making every consumer live with it.
Instead it carries no language runtime at all.
It carries `uv`, which owns the Python interpreter, and `mise`, which owns Node and every language added later.
A project's version comes from that project: `.python-version` and `pyproject.toml` for Python, `.mise.toml` or `.tool-versions` or `.nvmrc` for the rest.

This is what makes ADR-0004's single dev image affordable.
Adding Go or Rust costs nothing, because nothing about them is baked.

## Considered options

`nvm` is disqualified twice: its installer appends to `~/.zshrc`, which `dotfiles` ADR-0006 forbids, and it is a shell function rather than a binary so it has no Linux package.
Volta reached end-of-maintenance in November 2025.
`fnm` is a good Node manager but only a Node manager, and a second language would mean a second tool, which is the drift this repo exists to end.

`mise` is used in **shims** mode rather than `mise activate`.
This is the load-bearing part of the choice.
Shims are wrapper scripts on `PATH`, so they work in non-interactive shells; `activate` hooks the prompt and directory changes, so it does not.
`dotfiles` ADR-0004 already learned this the expensive way: `docker exec -it claude-code zsh -lc claude` is a non-interactive login shell, and a tool that only configures interactive shells leaves `PATH` broken for everything an agent spawns.
Choosing `activate` would reintroduce exactly that bug.

Dropping Homebrew in favour of `mise` was investigated, since `mise` was found to cover 13 of the 14 tools in use across the estate, including the whole `homelab-kube` set.
Rejected: Homebrew is too convenient to drop, and keeping it preserves parity with the Mac, which is what `dotfiles` ADR-0002's path probing exists to paper over.
Measured cost of keeping it: 159 MB, taking the image from 106 MB to 265 MB, still below `devcontainers/base`'s 354 MB before any tools at all.

The two therefore coexist with a rule rather than a boundary war.
`brew install` pins nothing and drifts, which is visible today as bare `node` in `homelab-etl` beside `node@24` in `actual-budget-transformer`; `mise` pins per project in a file.
Version-sensitive tools go to `mise`, ad-hoc convenience tools stay with `brew`.

## Consequences

- **Every consumer must drop `UV_PYTHON_DOWNLOADS=0`.** All five set it today. It was correct only while the parent supplied a system interpreter, and on this base there is none, so leaving it set means `uv` can find no Python at all.
- A cold container fetches its interpreter on first `uv sync` unless the cache is mounted. This is the price of not dictating a version, and it is paid once per container rather than once per estate-wide bump.
- The mise shims directory and Homebrew's `shellenv` both go in `/etc/zsh/zshenv`, not in any file under `$HOME`. This keeps `$HOME` pristine for chezmoi (ADR-0005) and covers non-interactive shells, following the precedent `dotfiles` ADR-0004 set.
- `mise` is not in use in any consumer repo today, so migration teaches a new tool. Accepted, because the alternative was baking versions into the base image and bumping them across the estate by hand.
