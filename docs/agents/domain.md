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

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-repo-holds-shared-container-images-only.md
│   ├── 0002-shell-dotfiles-layer-is-dev-only.md
│   ├── 0003-two-axis-tag-matrix.md            ← partly superseded by 0004
│   ├── 0004-one-dev-image-and-an-asymmetric-tag-scheme.md
│   ├── 0005-debian-slim-plus-the-common-utils-feature.md
│   ├── 0006-language-managers-not-baked-runtimes.md
│   └── 0007-the-dev-image-declares-no-entrypoint.md
└── ...
```

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

Load `/writing-for-agents` before creating or substantially editing `AGENTS.md` itself, or any of its `docs/agents/*.md` siblings (`issue-tracker.md`, `triage-labels.md`, `domain.md`, and any later addition).
These are exactly what that skill means by "an AGENTS.md or a doc reached by a pointer," even though its own trigger phrase doesn't yet name the siblings explicitly.
This doesn't apply to ADRs or `CONTEXT.md` - those follow `/domain-modeling`'s own `ADR-FORMAT.md`/`CONTEXT-FORMAT.md` instead, which are deliberately terser.
