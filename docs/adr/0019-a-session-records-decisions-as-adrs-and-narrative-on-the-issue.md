# A session records decisions as ADRs and narrative on the issue

AGENTS.md's `## Status` section grew to roughly 130 lines of session-by-session narrative before this ADR, because every session that resolved something followed the precedent of appending a paragraph rather than reaching for the tools already meant for this.
Most of that narrative also duplicated a decision `docs/adr/` already owned - issue #34's finding, for one, was independently amended into ADR-0015's own consequences.
AGENTS.md loads on every turn of every session, so an unbounded, duplicated log is the most expensive place a session's output could land.

A session that resolves a decision or a non-obvious finding worth keeping records it in one of two places, never a third.
A resolved decision or convention becomes an ADR - `/domain-modeling` already does this "lazily when terms or decisions actually get resolved," `docs/agents/domain.md` just never said a session should actually reach for it.
The narrative of what happened and what was verified goes as a comment on the issue before closing it, `docs/agents/issue-tracker.md`'s own documented "Resolve" step.
AGENTS.md itself never grows a running log again.

## Considered options

- **Keep the Status section, accept the cost.** Rejected outright - it is the problem this ADR fixes: unbounded growth, and duplication with the ADRs that already record the same decisions properly.
- **Move the log out of AGENTS.md into a separate always-appended file**, reached by a pointer instead of loaded every turn. Rejected: it removes the context-load cost but not the actual failure - an unbounded log still duplicates ADRs and still needs a reader to reconstruct history from prose instead of from the record GitHub already keeps.

## Consequences

- **No single file narrates "how did we get here" anymore.** Reconstructing a decision's history means reading the ADR plus the closed issue that produced it, not one running file - which is also the more accurate record, since the issue is where the actual back-and-forth happened.
- **Classifying output correctly is now the session's judgment call.** This skill's own three-part ADR test (hard to reverse, surprising without context, a real trade-off) decides "ADR" versus "issue comment, nothing more" - getting it wrong either under-records (silently repeats old mistakes) or over-records (an ADR for something that never needed one).
- **This ADR is forward-looking only.** It doesn't retroactively rewrite the Status section's history, which already lives in AGENTS.md's git history and in the closed issues it summarized.
