# The agent runtime carries the operator's dotfiles

ADR-0002 puts the shell and dotfiles layer in the dev image only, and ADR-0010 keeps configuration out of the image entirely - the image ships `dotfiles-bootstrap` and never the configuration it applies.
Both are about what an **image** carries, and neither answers what an **agent session** should run.

The agent runtime runs `dotfiles-bootstrap` on every session.
An agent working in a repo is subject to the same conventions a human is, and the operator's conventions live in a globally-applied `AGENTS.md` that the repo's own `AGENTS.md` does not restate: no em dashes, never self-attribute as a commit co-author, one sentence per line in Markdown, prefer an established tool over a hand-rolled one, git hooks reject rather than auto-fix.
An agent without them produces output that violates them every session, and the operator hand-corrects the same class of defect every time - the friction that makes an attended workflow not worth running.

This is a deliberate trade of reproducibility for convention compliance, which is why it is recorded rather than done quietly.

## Considered options

- **Repo-only: the guest gets the clone and nothing else.** The cleanest reading of ADR-0002 and ADR-0010, and the only option where a session's behaviour depends solely on committed state. Rejected because the conventions that matter are not committed to this repo and are not going to be - they are the operator's, and they apply across every repo.
- **A narrow copy of just the agent instruction file.** Rejected under the repo's own standing preference for established tools over hand-rolled ones: `dotfiles-bootstrap` already exists in the image, exists for exactly this, and is idempotent by ADR-0009's cold-init versus warm-update split. Hand-rolling a second, weaker mechanism beside it would be the worse choice.

## Consequences

- **Session behaviour is no longer reproducible from committed state alone.** A session's conventions come from whatever is on the operator's `dotfiles` `main` that day. Acceptable for the attended shape, where a human is present and the dotfiles are their own; a genuine hole for the headless shape, which should revisit this rather than inherit it.
- **The bootstrap must run on every boot, not once.** A long-lived runtime (ADR-0021) would otherwise pin every session in it to whatever `dotfiles` state its first boot captured, so `agent-bringup` re-runs `dotfiles-bootstrap` on every attach. The original reason was narrower and is now retired with its cause: under `--persist-claude-auth` (ADR-0022), `~/.claude/CLAUDE.md` symlinked from the persistent volume to an ephemeral-disk copy of `../AGENTS.md`, so a boot that skipped the bootstrap left Claude Code reading a dangling symlink rather than failing loudly.
- **The trust surface widens by one repository.** The agent's instructions now come from `dotfiles` as well as from the repo it is working in, so compromising `dotfiles` compromises every agent session.
- **`dotfiles` must stay public, or the credential model must change.** The session's token is scoped to one repository (ADR-0015) and could not clone a private `dotfiles`.
- **Claude Code's own sandbox setting is committed to this repo as well as carried in dotfiles**, and the redundancy is deliberate. Project settings take precedence over user settings, so the dotfiles copy is inert here - but it means the guest's configuration has one source that cannot fail even if the bootstrap does, which the dangling-symlink case above showed was a real failure mode rather than a hypothetical one.
