# Handoff: issue #40, agent self-merge controls

Session handoff written 2026-08-08, so the analysis below survives the conversation that produced it.

The research findings live in [`0040-agent-self-merge-controls.md`](0040-agent-self-merge-controls.md) and are not repeated here.
This document captures only what that file does **not** know: a follow-up analysis of two options it never evaluated, a correction to a recommendation made during the session, and the state everything was left in.

## Status

[Issue #40](https://github.com/afrossard/container-base/issues/40) is **open and stays open**.

Its three "What to investigate" items are all answered in the research doc:

- Required status checks as a gate: answered, with the caveat that they gate correctness rather than review, and become theatre the moment the token gains `Actions: write`.
- The GitHub App as the actual fix: answered, yes, with the credential broker as the real blocker.
- The narrower fork flow: answered, declined, with a reason rather than a preference.

Its first acceptance criterion, a recorded decision, is **deliberately outstanding**.
The operator chose to defer the decision rather than record one, so no ADR was written.
Do not treat the recommendation below as a decision that was made.

## What this session added beyond the research doc

The question driving it: could a second GitHub user account serve as the agent identity instead of a GitHub App?

### A machine account is permitted, and the gate it buys is real

GitHub's Terms of Service, Section B.3, explicitly allow one free machine account alongside a personal account.
This is a sanctioned pattern, not a grey area.

The gate it buys does **not** come from withholding merge permission, which is impossible.
Repositories owned by a personal account have exactly two permission levels, and GitHub's own documentation states that collaborators cannot be given read-only access and can "create, merge, and close pull requests".
So a machine account still holds merge.

What changes is that the ruleset gate becomes expressible.
Rulesets cannot distinguish tokens, but they can distinguish "approved by someone other than the author".
With a second identity, `required_approving_review_count: 1` stops deadlocking, and the already-verified `bypass_actors: []` with `current_user_can_bypass: "never"` means it holds.

### The machine account's real cost is the token type

A fine-grained PAT cannot be used for this.
Each fine-grained token "is limited to access resources owned by a single user or organization", and GitHub's own known-gaps list names the exact case: "Using fine-grained personal access token to contribute to repositories where the user is an outside or repository collaborator".
This repository is owned by `afrossard` and the machine account would be a collaborator, so the machine account would need a **classic PAT with `repo` scope**, regressing the fine-grained decision made in issue #34.

This is the same known gap the research doc cites when rejecting the fork model.
It is not a fork-specific limitation; it applies to any repository the token's owner does not own.

Second cost: two-factor authentication is mandatory, including for "unattended or shared access accounts ... such as bots and service accounts".
The failure mode is unpleasant because it is silent: on lockout, existing tokens "will continue to function" but the account cannot mint new PATs, so the problem surfaces only on rotation day.

### The org transfer does not fix issue #40, and this corrects a recommendation made mid-session

An organization was recommended during the session and that recommendation was then **withdrawn**.
Recording the correction here because the reasoning is what matters and a future session could otherwise re-derive the same wrong conclusion.

An org changes the repository's _owner_.
It grants no second _identity_.
Since issue #40's fix is entirely a second identity, an org on its own moves nothing.

Its only bearing was making a machine account's token fine-grained rather than classic, by becoming the resource owner.
That benefit disappears entirely on the GitHub App path, because **a GitHub App works on a personal repository with no org and no second account**, and its installation token acts as `<app>[bot]`, which is already a distinct identity.

For completeness, the transfer itself is low risk: issues, pull requests, wiki, stars, watchers, webhooks, secrets, and deploy keys all carry over, and old URLs redirect.
GitHub's transfer documentation is **silent on rulesets**, so if an org is ever revisited for unrelated reasons, verify the ruleset either side of the move rather than assuming it survives.

The other reason to decline it: granular roles, org-level PAT approval policies, and token lifetime policies are team governance features.
With one human they are unused surface.

### The recommendation left on the table, undecided

1. **Now, touching no identities:** the interim controls from the research doc's recommendations, which is a `permissions.deny` entry plus a `PreToolUse` hook plus a bats test for both, a `CODEOWNERS` file, and marking `format` required.
2. **The fix:** the GitHub App, whose only blocker is a host-side credential broker, since the private key must not enter the guest and `msb run --secret` substitutes a fixed value at launch.
3. **In the pocket:** the machine account, as the answer to "I want the approval gate before the broker exists", accepting the classic PAT and the 2FA secret as temporary costs.

## Where the writing was agreed to go

Placement was settled even though the decision was not.
None of this has been created yet.

- **The decision** goes to a new ADR. ADRs here are numbered **sequentially, not by issue**, and the highest is `0017`, so the next is `docs/adr/0018-*.md`. House style is a declarative sentence title; the working proposal was "The merge gate is an identity, not a permission".
- **The evidence** stays in `docs/research/0040-agent-self-merge-controls.md`, which is numbered by issue. The analysis in this handoff should be folded into it rather than becoming a third file.
- **The credential broker** wants its own issue. It is the real work, it outlives issue #40, and it should not be smuggled in as a sub-task.
- **The interim controls** want their own issue or issues. Note that marking `format` required probably belongs to issue #31 instead, since `AGENTS.md` records that `format.yml` was deliberately built without a path filter "so it stays the one check safe to mark required once #31 revisits that".
- **The org question**, if ever revisited, wants its own issue. Changing the repository's owner is a larger frame than issue #40 and should not enter through it.
- **The narrative** goes to `AGENTS.md`, which carries the running chronological record and already references issue #40.

## Repository state as left

- Branch `research/0040-agent-self-merge-controls`, pushed, no pull request opened, deliberately.
- It carries the research document and this handoff, and adds no other files.
- The branch was based on `5ce6a69` and is behind `origin/main`, which moved during the session. It only adds new files under `docs/research/`, so it is conflict-free and can be rebased or merged whenever.
- Working tree clean, no stashes.

## Environment notes worth not rediscovering

- **OpenAI documentation is unreachable from this network.** The operator's UniFi gateway DNS-sinkholes `openai.com`, `chatgpt.com`, `developers.openai.com`, and `learn.chatgpt.com` to `203.0.113.250`, then serves a block page whose certificate is signed by `CN=UniFi SSL Certificate Authority, O=Ubiquiti Inc.`. This surfaces as an SSL verification failure and looks like an upstream outage. It is not. `platform.openai.com` and `github.com` are unaffected, and the `openai/codex` repository on GitHub is reachable and carries the real material.
- **The Bash tool's sandbox blocks all network access**, so `gh`, `dig`, and `curl` need the sandbox disabled to work at all.
- **The shell is zsh**, which does not word-split unquoted parameter expansions the way bash does. A `for h in $hosts` loop silently iterates once over the whole string.
- **`AGENTS.md` line 29 is stale.** It describes issue #17, a non-root default user, as scoped but never built. It landed as `ca6b37c` (#65) during this session.

## Suggested skills

- **`grilling`** or **`grill-with-docs`**, before anything is recorded. The decision is deferred precisely because it has not been stress-tested, and the machine-account-versus-App tradeoff is the kind of thing that should be attacked before it becomes an ADR.
- **`domain-modeling`**, which is this repo's route for recording an architectural decision, once the decision exists.
- **`triage`**, for filing the credential broker and interim-control issues, since this repo has its own triage conventions in `.agents/skills/triage/` and `docs/agents/triage-labels.md`.
- **`research`**, if the credential broker needs its own investigation into how an App private key reaches a refresh flow without entering the guest.

## Do not repeat

- Do not re-derive whether a token can be scoped to push without merge. It cannot, this is settled and verified, and the research doc explains why.
- Do not re-recommend an organization without reading the correction above first.
- Do not attempt to fetch OpenAI's documentation site.
