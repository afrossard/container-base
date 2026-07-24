# mise installs system-wide, and sudo is what forces it

ADR-0006 puts `mise` in shims mode so that non-interactive shells resolve tools.
Left at its defaults `mise` is a per-user tool: `mise doctor` reports `shims: ~/.local/share/mise/shims`, and that directory does not exist until the user first runs `mise`.
We move the data directory to `/usr/local/share/mise`, give it to `vscode`, and prepend the shims directory to sudo's `secure_path`.

The forcing constraint is `sudo`.
Debian sets `Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"` and sudo replaces `PATH` with that string wholesale.
`secure_path` is static and cannot expand `$HOME`, so a per-user shims directory is unreachable from `sudo` by construction.

## The measurement

Measured on `debian:trixie-slim`, with `mise` from its apt repository and a project pinning `node = "24"`:

| wiring                                  | `node` in `zsh -lc`                  | `sudo node`         | `vscode` installs a tool |
| --------------------------------------- | ------------------------------------ | ------------------- | ------------------------ |
| defaults (per-user shims)               | `v24.18.0`                           | `command not found` | yes                      |
| `MISE_DATA_DIR` only, left root-owned   | shim found, then `No version is set` | `command not found` | `Permission denied`      |
| `MISE_DATA_DIR` + chown + `secure_path` | `v24.18.0`                           | `v24.18.0`          | yes                      |

The middle row is the trap worth recording.
Moving the data directory on its own does not fix the `sudo` problem, it only changes which error you get, and it introduces a new one by making the directory unwritable to the user who needs it.
All three pieces are load-bearing: the data directory moves the files, the chown makes them usable, and `secure_path` is the only one of the three that `sudo` actually reads.

## `MISE_GLOBAL_CONFIG_FILE` is deliberately not set

A first draft of this decision also redirected mise's global config to `/etc/mise/config.toml`.
That was wrong, and the correction is worth keeping because the same reasoning will otherwise be repeated.

Version pinning is per project, not global.
With a system-wide data directory and no global config at all, a project pinning `node = "24"` gets `v24.18.0`, a second project pinning `node = "22"` gets `v22.23.1`, both resolve through the same shared `installs/` directory, and no `~/.config/mise` is created.
Outside any project the shim reports `No version is set for shim: node`.

That error is the correct behaviour, not a gap.
ADR-0006 says the image bakes no runtime, so there is deliberately no fallback version, and a global config file is precisely a baked fallback.

## Considered options

The per-user default was the first recommendation and was rejected on the `sudo` argument above.
The counter-argument that it is a single-user container is true but does not survive contact with `sudo`, which resets `PATH` regardless of how many users exist.

## Consequences

- Two projects on the same toolchain version share one copy on disk, because `installs/` is now shared rather than per-user.
- The shims directory is a fixed, known path, which is what makes a `/etc/profile.d` entry for non-zsh shells worth adding. It would have been awkward while the path contained `$HOME`.
- `~/.cache/mise` and `~/.local/state/mise` still appear in `$HOME` at runtime. Verified harmless: `chezmoi init --apply` exits 0 with both present.
- The `secure_path` edit is an unusual thing to find in an image and looks unrelated to `mise`. It is the reason this ADR exists.
