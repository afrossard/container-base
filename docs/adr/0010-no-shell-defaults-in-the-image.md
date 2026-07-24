# The image ships no shell defaults, and a developer without dotfiles gets a bare zsh

ADR-0005 switched the `common-utils` feature's oh-my-zsh options off, because `~/.zshrc` has exactly one writer and that writer is chezmoi (`dotfiles` ADR-0006).
It removed a set of shell defaults and put nothing back, which is invisible while the only consumer is the author, whose dotfiles always land.
Framed as a team image consumed by several developers, the question becomes explicit: what does a developer with no dotfiles repository get?

They get a bare zsh, and that is the decision.
The image ships functional wiring only.
`/etc/zsh/zshenv` carries `PATH` for Homebrew and the mise shims, and `LANG` is set; `/etc/zsh/zshrc` is left as Debian ships it, and nothing in the image seeds history, completion, or a prompt.

The `starship` binary ships, but the `starship init zsh` line does not.
A developer without dotfiles therefore has the binary on `PATH` and the default shell prompt.

## Three tiers, and this repo owns the middle one

The distinction that makes this decision coherent, and that a reader will otherwise collapse:

- **Project settings** belong to the consumer repo: `.vscode/settings.json`, `mise.toml`, `.editorconfig`. Committed, versioned with the code, identical for everyone.
- **Image-level defaults** belong here: the `PATH` wiring, `LANG`, `secure_path`, `MISE_DATA_DIR`. They cannot live in a consumer repo, because duplicating them across consumers is the drift this repo exists to remove, and they are not personal.
- **Personal configuration** belongs to the individual's dotfiles repository, applied at start by ADR-0009's bootstrap.

Shell look and feel is the third tier, not the second, which is why the image declines to supply it.
A shared set of team defaults, if one is ever wanted, is a fourth thing and would be its own repository: `container-base` publishes images.

## The mechanism exists and is deliberately unused

Recorded so the option is not rediscovered from scratch, and so the rejection is not mistaken for ignorance of it.

Debian ships `/etc/zsh/zshrc`, and it is sourced **before** `~/.zshrc`.
Measured: with `ORDER` echoes in both files, output is `etc-zshrc` then `home-zshrc`, and a variable set system-wide is overridden by the personal file.
An interactive zsh with no `~/.zshrc` at all starts cleanly, with no `zsh-newuser-install` prompt.

So system-wide defaults with personal configuration layered on top are available, cost nothing in `$HOME`, and would not give `~/.zshrc` a second writer.
If the bare-zsh experience ever becomes a real complaint, that is where the fix goes, and this ADR is superseded rather than worked around.

## Consequences

- `dotfiles-bootstrap` with no repository configured is a no-op that exits 0, and the container is fully usable afterwards. This is a tested path, not an incidental one.
- The test suite bootstraps from a fixture dotfiles repository. Asserting against the author's personal repository would bake one developer's configuration into the definition of a working image.
- The image is not opinionated about shell ergonomics, so a developer who wants them supplies them, in the tier that owns them.
