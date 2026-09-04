# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

This is a **single-context** repo: one `CONTEXT.md` and one `docs/adr/` at the root.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root - the glossary and domain model.
- **`docs/adr/`** - read the ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**.
Don't flag their absence; don't suggest creating them upfront.
The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

`CONTEXT.md` and `docs/adr/` at the root. The ADR filenames are full sentences, so `ls docs/adr/` is the index.

If this repo ever grows into several bounded contexts, the layout becomes a root `CONTEXT-MAP.md` pointing at one `CONTEXT.md` per context, with context-scoped ADRs under `src/<context>/docs/adr/`.
Re-run `/setup-matt-pocock-skills` to switch, or just edit this file.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`.
Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal.
Either you're inventing language the project doesn't use (reconsider), or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0003 (two-axis tag matrix) - but worth reopening because…_

## Record what you resolve

When a session resolves a decision or convention, record it as an ADR through `/domain-modeling` - don't wait to be asked.
When a session resolves a non-obvious finding worth keeping (what happened, what was verified), record it as a comment on the issue before closing it, per `docs/agents/issue-tracker.md`'s "Resolve" step.
Neither ever goes into AGENTS.md itself (ADR-0019).

## Writing AGENTS.md or a docs/agents/ sibling

Load `/writing-for-agents` before creating or substantially editing `AGENTS.md` or any `docs/agents/*.md` sibling.
This doesn't apply to ADRs or `CONTEXT.md`, which follow `/domain-modeling`'s own deliberately terser `ADR-FORMAT.md`/`CONTEXT-FORMAT.md`.
