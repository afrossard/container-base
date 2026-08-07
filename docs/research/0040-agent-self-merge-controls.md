# What actually stands between an agent's pull request and `main`

Research for [issue #40](https://github.com/afrossard/container-base/issues/40), which follows [#31](https://github.com/afrossard/container-base/issues/31) (the ruleset on `main`) and [#34](https://github.com/afrossard/container-base/issues/34) (the fine-grained PAT the agent runtime carries).
Issue #40 records a finding from #34's session: the `Contents: write` permission the token needs in order to push a branch at all is also sufficient to merge a pull request, so the agent can open a pull request and merge it in the same breath, and neither the token nor the ruleset can tell that apart from a human doing it.

This document does two things.
First it settles the mechanical question against GitHub's own primary sources: given a credential that can push branches and open pull requests, what if anything prevents that credential from merging its own pull request.
Second it surveys how people actually run unattended coding agents against real repositories today, and what structural control each of them puts between "the agent produced a change" and "the change is on the default branch".

[Research 0016](0016-community-agent-hardening-practices.md)'s closing "Credentials and secrets" section is the direct ancestor of this question.
It established that a credential is the one capability a disposable VM does not contain, that scoping and short lifetime are both load-bearing, and that "push branches, not `main`" is a server-side ruleset property rather than a token property.
Everything there is referenced, not re-derived.
This document goes past it to the part 0016 explicitly deferred: what happens once the token can push.

## Sources consulted

**GitHub's own reference documentation, fetched directly:**

- [Permissions required for fine-grained personal access tokens](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens) - the endpoint-to-permission mapping that settles the issue's central claim.
- [REST API endpoints for pull requests](https://docs.github.com/en/rest/pulls/pulls) - fetched, but see the note on verification below.
- [Available rules for rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
- [About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) and [Creating rulesets for a repository](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository)
- [About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) - for the classic-protection contrast.
- [Approving a pull request with required reviews](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/approving-a-pull-request-with-required-reviews)
- [About code owners](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)
- [Managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)
- [Generating an installation access token for a GitHub App](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app)
- [`GITHUB_TOKEN` concepts](https://docs.github.com/en/actions/concepts/security/github_token)
- [Managing GitHub Actions settings for a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository)
- [Managing your personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
- [Managing deploy keys](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys)
- [Managing custom repository roles for an organization](https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/managing-custom-repository-roles-for-an-organization)
- [GitHub Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service) - for the machine-account question.

**GitHub as an agent vendor, fetched directly:**

- [Risks and mitigations for GitHub Copilot cloud agent](https://docs.github.com/en/copilot/concepts/agents/cloud-agent/risks-and-mitigations)
- [Building guardrails for GitHub Copilot cloud agent](https://docs.github.com/en/copilot/tutorials/cloud-agent/build-guardrails)
- [Reviewing a pull request created by GitHub Copilot](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/review-copilot-prs)
- [Bot-created pull requests can run workflows if approved](https://github.blog/changelog/2026-06-11-bot-created-pull-requests-can-run-workflows-if-approved/) (changelog, 11 June 2026)
- [GitHub Agentic Workflows](https://github.github.com/gh-aw/): [security architecture](https://github.github.com/gh-aw/introduction/architecture/) and [safe outputs for pull requests](https://github.github.com/gh-aw/reference/safe-outputs-pull-requests/)

**Other agent vendors:**

- Anthropic, [`claude-code-action` security guide](https://github.com/anthropics/claude-code-action/blob/main/docs/security.md) and [capabilities and limitations](https://github.com/anthropics/claude-code-action/blob/main/docs/capabilities-and-limitations.md), fetched directly from the repository.
- Anthropic, Claude Code [settings](https://code.claude.com/docs/en/settings) and [hooks](https://code.claude.com/docs/en/hooks), fetched directly.
- Cognition, [Devin GitHub integration](https://docs.devin.ai/integrations/gh), fetched directly.
- OpenAI, the [`openai/codex`](https://github.com/openai/codex) repository, read with `gh api`. This is the shipped configuration surface rather than a rendered description of it, so it is the better primary source of the two. Specifically: [`codex-rs/execpolicy/README.md`](https://github.com/openai/codex/blob/main/codex-rs/execpolicy/README.md), [`codex-rs/execpolicy/examples/example.codexpolicy`](https://github.com/openai/codex/blob/main/codex-rs/execpolicy/examples/example.codexpolicy), [`codex-rs/config/src/requirements_exec_policy.rs`](https://github.com/openai/codex/blob/main/codex-rs/config/src/requirements_exec_policy.rs), [`codex-rs/config/src/requirements_layers/permissions.rs`](https://github.com/openai/codex/blob/main/codex-rs/config/src/requirements_layers/permissions.rs), [`docs/config.md`](https://github.com/openai/codex/blob/main/docs/config.md), [`.codex/skills/babysit-pr/SKILL.md`](https://github.com/openai/codex/blob/main/.codex/skills/babysit-pr/SKILL.md), and [`.github/CODEOWNERS`](https://github.com/openai/codex/blob/main/.github/CODEOWNERS). The `openai/codex` repository's own branch ruleset was also read with `gh api repos/openai/codex/rulesets`, and is reported in section 4.4 as real-repo evidence.
  Note on why the repository was used rather than the documentation site: `developers.openai.com` and `learn.chatgpt.com` are unreachable **from this network only**, because the operator's UniFi gateway DNS-sinkholes OpenAI properties to `203.0.113.250` and serves a block page with a certificate signed by `CN=UniFi SSL Certificate Authority, O=Ubiquiti Inc.`, which presents as a TLS verification failure. This is local DNS filtering, not an upstream outage, and a future reader on a different network will find those URLs work normally.
  A second, unrelated caveat applies: the Markdown files under `openai/codex/docs/` turned out to be three-line stubs that redirect to that same unreachable site, so the substantive Codex findings below come from the crate READMEs, the Rust configuration types, the shipped skill definitions, and the repository's live GitHub configuration rather than from prose documentation.
- Google, [Jules documentation](https://jules.google/docs). Fetched successfully but **says nothing** about GitHub permissions, merging, or review gates. Recorded as a documentation gap rather than as evidence either way.
- Cursor background agents. No first-party permission documentation found; only community forum threads, treated as low-confidence.

**Community evidence:**

- [community discussion #182732](https://github.com/orgs/community/discussions/182732), "Separate 'Pull Request Contribute' and 'Pull Request Merge' permissions for Fine-Grained PATs" - the exact request issue #40 implies, filed December 2025 by someone running Claude Code, ~95 reactions, no GitHub staff response.
- [community discussion #190713](https://github.com/orgs/community/discussions/190713), "App Permissions: write Pull Requests but not Code?"
- [community discussion #113172](https://github.com/orgs/community/discussions/113172), on the "Restrict updates" rule blocking pull request merges.
- Savas Parastatidis, ["My Coding Agent Needed Its Own GitHub Identity"](https://savas.me/2026/04/27/my-coding-agent-needed-its-own-github-identity/) (April 2026), a practitioner documenting his own App-based setup.
- AWS Security Blog, ["Balancing speed and safety: A control framework for AI coding agents"](https://aws.amazon.com/blogs/security/balancing-speed-and-safety-a-control-framework-for-ai-coding-agents/).
- ["My AI agent almost merged its own pull request"](https://dev.to/mjmirza/my-ai-agent-almost-merged-its-own-pull-request-23nk), a practitioner incident writeup.
- [`carrotRakko/github-finest-grained-permission-proxy`](https://github.com/carrotRakko/github-finest-grained-permission-proxy), the workaround proxy announced in discussion #182732.

**Live configuration of this repository, read with `gh api`**, recorded in section 2.

**A note on what could not be verified.**
GitHub's per-endpoint pages render a "Fine-grained access tokens for this endpoint" note listing the exact permission each endpoint needs.
That note did not survive this environment's HTML-to-Markdown conversion: repeated fetches of `docs.github.com/en/rest/pulls/pulls` with several different prompts reported the phrase absent from the page.
The claim below is therefore established from the [permissions reference page](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens), which is the same underlying data presented per permission rather than per endpoint, and which did fetch cleanly.
It is corroborated independently by community discussion #182732, whose author reached the same conclusion the hard way.
`gh api repos/afrossard/container-base/branches/main/protection` returned HTTP 403 rather than 404, because the token driving this session is itself a fine-grained PAT without the `Administration` permission - so "no classic branch protection exists" is an inference from the ruleset being the configured mechanism, not a directly observed fact.

## 1. The mechanical question, settled

### 1.1 The issue's central claim holds

GitHub's permissions reference lists `PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge` under **Repository permissions for "Contents", at write level**.
It does not appear under "Pull requests" at any level.
Conversely `POST /repos/{owner}/{repo}/pulls` (create a pull request) appears **only** under "Pull requests" at write level, and not under "Contents".

So issue #40 is exactly right, and the asymmetry is the whole problem: creating a pull request and merging it are governed by two different permissions, and the one that governs merging is the one you cannot avoid holding.

Community discussion #182732 is the same finding reached independently.
Its author opened it asking GitHub to split `pull-requests: write` into contribute and merge halves, then corrected himself in a follow-up: "Merge requires `contents:write`, not `pull-requests:write`. I conflated the two because my PAT had both permissions enabled."
His revised request is to split `contents: write` into a `contents: contribute` that permits pushes but not merges.
His stated motivation is identical to this repo's: an AI coding agent sharing a GitHub account with humans, where "we cannot give AI agents push access without also granting merge access."
The discussion has roughly 95 reactions and no GitHub staff response, only the automated feedback acknowledgement.

### 1.2 Push and merge are the same permission, and that is not fixable inside one repository

The trap is not that GitHub filed merge under the wrong permission.
It is that pushing a branch **is** writing repository contents, so any credential that can push over HTTPS necessarily holds `Contents: write`, and `Contents: write` is sufficient to merge.
Creating a branch through the Git Data API (`POST /repos/{owner}/{repo}/git/refs`) is also a Contents-write endpoint, so there is no back door there either.

Community discussion #190713 contains the popular but wrong version of this: "Pull requests (write) requires Contents (write) under the hood. So if an app can create/update PRs, it can technically push code."
That is a community claim with no GitHub staff response in the thread, and it disagrees with GitHub's own permissions reference, which lists `POST /repos/{owner}/{repo}/pulls` under Pull requests alone.
The correct statement is the reverse direction: opening a pull request does not require Contents, but **getting a branch to open it against** does.
The distinction matters, because it is the only crack in the wall and section 5 walks through it.

The consequence for issue #40's framing is worth stating plainly.
There is no token configuration, and no ruleset configuration, that gives a single credential push access to a repository while withholding merge access to that same repository.
Anything that looks like one is either a different identity, a different repository, or a control that lives outside GitHub.

### 1.3 What this repo's token cannot do, which turns out to matter

Issue #34 minted the token with `Contents: R/W`, `Pull requests: R/W`, `Issues: R/W`, `Metadata: R` and nothing else.
Against the permissions reference, that means the token **cannot**:

- Re-run a workflow. `POST /repos/{owner}/{repo}/actions/runs/{run_id}/rerun` is under **Actions: write**.
- Forge a commit status. `POST /repos/{owner}/{repo}/statuses/{sha}` is under **Commit statuses: write**.
- Create or update a check run. Check runs are under **Checks: write**, and fine-grained PATs are documented as unable to call the Checks API at all ("Using fine-grained personal access token to call the Checks API" is on GitHub's own list of known gaps).
- Edit or delete the ruleset, or change repository settings. Those are under **Administration: write**.
- Push a commit that touches `.github/workflows/`. AGENTS.md already records this from issue #37's session: GitHub gates any push touching workflow files behind a separate `workflow` scope the token does not carry.

It **can** create a pull request review (`POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews` is under Pull requests: write), but not an approving one on a pull request it authored, because "Pull request authors cannot approve their own pull requests."

This list is what makes section 3.5's answer about required status checks come out the way it does.

## 2. The live configuration, recorded

Read with `gh api` on 2026-08-07, from a session authenticated as `afrossard` with a fine-grained PAT.

`gh api repos/afrossard/container-base/rulesets` returns exactly one ruleset, id `19774480`, name `main`, `source_type: Repository`, `enforcement: active`, created 2026-07-26 and never updated since.

Drilling in with `gh api repos/afrossard/container-base/rulesets/19774480`:

- `conditions.ref_name.include: ["~DEFAULT_BRANCH"]`, `exclude: []`.
- Rules: `deletion`, `non_fast_forward`, and `pull_request`.
- The `pull_request` rule's parameters: `required_approving_review_count: 0`, `dismiss_stale_reviews_on_push: false`, `required_reviewers: []`, `require_code_owner_review: false`, `require_last_push_approval: false`, `required_review_thread_resolution: false`, `allowed_merge_methods: ["merge", "squash", "rebase"]`.
- **`bypass_actors: []`** and **`current_user_can_bypass: "never"`**.

There is no `required_status_checks` rule, no `required_signatures` rule, no `merge_queue` rule, no `update` (restrict updates) rule, no `creation` rule, and no `code_scanning` rule.

`gh api repos/afrossard/container-base` shows `private: false`, `allow_merge_commit: true`, `allow_squash_merge: true`, `allow_rebase_merge: true`, `allow_auto_merge: false`, `delete_branch_on_merge: false`, `web_commit_signoff_required: false`, and the authenticated user holding `admin: true`.
There is no `CODEOWNERS` file anywhere in the repository (checked at the root, `.github/`, and `docs/`).
`gh api repos/afrossard/container-base/actions/permissions/workflow` returned 403 for the reason given above, so the "Allow GitHub Actions to create and approve pull requests" setting could not be read directly.

Two things are worth extracting from this.

**`current_user_can_bypass: "never"` for the repository owner is the direct answer to the issue's bypass question.**
It is also the load-bearing difference from classic branch protection, which GitHub documents the opposite way: classic restrictions "do not apply to people with admin permissions to the repository or custom roles with the 'bypass branch protections' permission" unless "Do not allow bypassing the above settings" is explicitly ticked.
ADR-0015 and issue #31 both predicted this and chose rulesets for exactly this reason.
The prediction is now confirmed by the API rather than assumed, and by #31's own demonstration that a direct push to `main` with the owner's credential is rejected.
So the repo owner does **not** bypass this ruleset, the bypass list is genuinely empty, and there is nothing to turn off.

**Nothing in that configuration constrains merging.**
Every rule present constrains how `main` is written to (no deletion, no force push, must go through a pull request) and none constrains who may perform the merge or what must be true first.
`required_approving_review_count: 0` is the setting issue #31 was forced into, and it is exactly the hole issue #40 names.

## 3. What a ruleset can and cannot express

### 3.1 Every ruleset control is an identity control

This is the finding that reorganises the whole question, and it is worth stating before the rule-by-rule walk.

A ruleset has exactly two ways to treat one actor differently from another: the bypass list, and rules whose semantics reference the pull request author or the last pusher.
Both operate on **identity** - a user, a team, a repository role, a GitHub App, Dependabot.
GitHub's ruleset creation documentation lists the eligible bypass actor types as "Repository admins, organization owners, and enterprise owners", "the maintain or write role, or custom repository roles based on the write role", "Teams, excluding secret teams", "GitHub Apps", and "Dependabot".
There is no token axis anywhere in that list.

The agent runtime's PAT authenticates **as `afrossard`**.
It is not a distinguishable actor.
Any rule that exempts the owner exempts the agent, and any rule that constrains the agent constrains the operator identically.
That is why issue #31 had to set required approvals to 0, and it is why no amount of further ruleset configuration can produce the gate #40 wants while the agent keeps the operator's identity.

**The generalisation: within one repository, the only two ways out are to change the agent's identity or to stop giving it a write credential.** Section 5 enumerates both.

### 3.2 Required approvals and self-approval

GitHub states it flatly: "Pull request authors cannot approve their own pull requests."
With `required_approving_review_count: 1` and an owner-authored pull request in a single-maintainer repository, there is nobody left to approve, and the pull request deadlocks.
That is precisely #31's reasoning and it stands.

The classic-protection documentation says "Repository owners and administrators can merge a pull request even if it hasn't received an approving review", which reads like an escape hatch.
It is not one here: that sentence describes classic branch protection with admin bypass left at its default, and the live evidence in section 2 shows this repo's ruleset reports `current_user_can_bypass: "never"`.
This is a genuine documentation-versus-reality tension worth flagging, because the classic-protection page is still what most search results surface, and its statements about administrators do not transfer to rulesets.

### 3.3 Require approval of the most recent reviewable push

GitHub describes this rule as: "You can require an approval from someone other than the last person to push to a branch before a pull request can be merged. This means at least one other authorized reviewer has approved any changes."

This is the most interesting rule in the catalogue for issue #40's purposes, because unlike required approvals it is explicitly framed around _who pushed_, not just a count.
Search-derived material suggests it enforces an approval from a different actor even when `required_approving_review_count` is 0.
**That is not a claim I could confirm from GitHub's own documentation and it should be treated as low-confidence and demonstrated before being relied on.**

It also does not escape section 3.1.
If the agent and the operator are the same identity, "someone other than the last person to push" is nobody, and the rule deadlocks in the same way required approvals does.
It becomes useful the moment the agent has its own identity, and only then.

### 3.4 Code owners cannot be bots

"Require review from Code Owners" is GitHub's own top recommendation in its Copilot guardrails tutorial: "Protect important Copilot and MCP configuration files with a `CODEOWNERS` file, and enable the 'Require review from Code Owners' rule."

Its documentation says code owners are "GitHub usernames or team names using the standard `@username` or `@org/team-name` format", that "Users and teams must have explicit `write` access to the repository", and that with the rule enabled "an approval from _any_ of the owners is sufficient".
GitHub Apps and bots are not listed as valid code owner entities.

For this repository that means CODEOWNERS is a way to force a _named human_ to approve, which is useful in a team, and is another form of the same deadlock in a one-person repository where that human is also the agent's identity.
It is worth noting for a different reason though: a CODEOWNERS entry over `.github/workflows/`, `.claude/`, and `scripts/` is a targeted control over the files that would let an agent widen its own blast radius, and it costs nothing to write even if the approval gate itself is not yet usable.

### 3.5 Required status checks: a real gate against this token, but not the gate #40 wants

Issue #40 asks whether a required status check is meaningful "keeping in mind the PAT-as-owner can also see and re-run its own checks".

Against **this** token, the answer is that it cannot re-run them and cannot forge them, per section 1.3: re-running a workflow needs `Actions: write`, setting a commit status needs `Commit statuses: write`, creating a check run needs `Checks: write` and is on GitHub's list of things fine-grained PATs cannot do at all.
A token holding only Contents, Pull requests, Issues and Metadata cannot make a red check green by any route except pushing a commit that actually fixes it.
And pushing a commit that fixes it is the check working as designed.

So a required `format` check (now that issue #37 has landed a `format` workflow that always runs, deliberately, with no path filter) would be a **real** gate, not theatre, given this token's exact permission set.
Three caveats:

- It is a gate on _correctness_, not on _review_. It stops unformatted code landing unattended. It does nothing about "a human looked at this."
- It is only real because of the permissions the token happens to lack. Adding `Actions: write` later, for any reason, silently converts it to theatre. This is worth recording as a constraint on the token rather than as a property of the check.
- Issue #37 already documents the deadlock trap: a required check whose workflow is skipped by a path filter reports pending forever. `format` was built with no path filter for exactly this reason and is the only check safe to mark required.

### 3.6 Merge queue is a scheduler, not an authorization control

GitHub documents that "once a pull request has passed all required branch protection checks, a user with write access to the repository can add the pull request to the queue", and that GitHub itself then performs the merge once checks pass.

Adding to the queue needs write access, which the agent has.
The queue changes _who executes_ the merge and _when_, not _who is authorized to cause_ it.
It is a velocity and correctness mechanism, not an answer to issue #40, and adopting it for this repository would add real machinery for no gate.

### 3.7 "Restrict updates" is the one rule that might express what #40 wants, and it is unresolved

The `update` rule is documented as: "If selected, only users with bypass permissions can push to branches or tags whose name matches the pattern you specify."

If a merge into `main` counts as a push to `main`, then a ruleset with `update` enabled and a bypass list containing only a designated actor would express "only that actor may land anything on `main`", which is the actor-level gate the whole issue is looking for.
GitHub's rule documentation does not say whether it applies to pull request merges or only to direct pushes, and I could not find a first-party statement either way.
Community discussion #113172 reports the stronger and more awkward outcome: even actors _on_ the bypass list find themselves unable to merge pull requests into a branch covered by an `update` rule, with no "bypass rules and merge anyway" affordance in the UI.

This is reported as unresolved, and it is the one item in this document most worth settling by demonstration rather than by reading, in the spirit of #40's own second acceptance criterion.
Note that even if it works exactly as hoped, section 3.1 still applies: the bypass list would have to name an actor the agent is not, so it only becomes useful after the identity split.

### 3.8 Custom repository roles do not apply here

GitHub's granular custom repository roles are the obvious place to look for a "may push, may not merge" role.
They are unavailable: "Only organizations that use GitHub Enterprise Cloud can create custom repository roles."
`afrossard` is a user account, not an organization, so this path is closed before its permission catalogue even matters.
The built-in roles offer no split either - Read, Triage, Write, Maintain, Admin, where Triage cannot push and Write can both push and merge.

## 4. How the community actually runs unattended agents

### 4.1 GitHub Copilot cloud agent: GitHub solving this problem in its own product

This is the most valuable source in the survey, because GitHub had to answer issue #40's exact question for a product where the agent is untrusted by construction, and it published the answer.
Every quote below is from [Risks and mitigations for GitHub Copilot cloud agent](https://docs.github.com/en/copilot/concepts/agents/cloud-agent/risks-and-mitigations).

The credential is not a general write token, and the agent is not driving git:

> "Copilot cloud agent can only perform simple push operations. It cannot directly run `git push` or other Git commands."

The write surface is one branch, chosen by GitHub rather than by the agent:

> "Copilot cloud agent only has the ability to push to a single branch. When the agent is triggered by mentioning `@copilot` on an existing pull request, Copilot has write access to the pull request's branch. In other cases, a new `copilot/` branch is created for Copilot, and the agent can only push to that branch."

Merging is not available at all, and GitHub says so in the guardrails tutorial: "Copilot cloud agent is already restricted from actions like pushing to a default branch or merging pull requests."

The self-approval hole is closed by rule, not by convention:

> "Prevents the user who asked Copilot cloud agent to create a pull request from approving it. This maintains the expected controls in the 'Required approvals' rule and branch protection."

The user-facing version of the same rule, from [Reviewing a pull request created by GitHub Copilot](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/review-copilot-prs): "If your repository requires pull request approvals, your approval of a Copilot pull request won't count toward the required number. Another reviewer must approve the pull request before it can be merged."

And CI is gated on a human, separately from review:

> "By default, workflows are not triggered until Copilot cloud agent's code is reviewed and a user with write access to the repository clicks the **Approve and run workflows** button."

The full documented mitigation list runs to thirteen items, including code scanning on the agent's output, signed commits with co-author attribution, session logs, a firewall on the agent's outbound network, and filtering of hidden Unicode characters as a prompt-injection defence.

Two of these are worth pulling out as _ideas_ rather than as things this repo can copy.
The **single-writable-branch restriction** is a token-scope control GitHub can build because it mints its own credentials internally, and it is the cleanest expression of "push, but only here" that exists anywhere in this survey.
Nothing in the public fine-grained PAT or GitHub App permission model exposes it, which is a real asymmetry between what GitHub gives itself and what it gives customers, and it is worth saying so.
The **"cannot run git commands" restriction** is the same idea one layer up: the agent does not hold a git credential, it hands a change to a component that does.
That is the same shape as gh-aw's safe outputs in section 4.3, and it is the shape this repo has not considered.

### 4.2 Anthropic's `claude-code-action`: refusal in the harness, not in the token

Anthropic's action requests, per its own [security guide](https://github.com/anthropics/claude-code-action/blob/main/docs/security.md), Contents (read and write), Pull requests (read and write), and Issues (read and write) as the permissions currently used.
So at the token level it is in exactly this repo's position: it holds Contents: write and could therefore call the merge endpoint.

It does not, because the harness refuses.
From [capabilities and limitations](https://github.com/anthropics/claude-code-action/blob/main/docs/capabilities-and-limitations.md):

> "Cannot merge branches, rebase, or perform other git operations beyond pushing commits."

> "For security reasons, Claude cannot approve pull requests."

> "Claude cannot submit formal GitHub PR reviews."

And the default is not even to open the pull request: the action "commits to a branch and provides a link; users must manually initiate PRs", which the security guide describes as ensuring human oversight before merging.
The action also uses "a short-lived GitHub App token scoped exclusively to its repository", and warns "Do not use a personal access token."

The honest reading for this repo is that Anthropic's control is the same _category_ as ADR-0017's behavioural convention - the agent is not given the ability in its tool surface - but a materially stronger _instance_ of it, because it is enforced in the action's code rather than in a prompt.
That is the gap between "the agent is only ever instructed to open a PR and stop" and "the agent has no code path that merges".

### 4.3 GitHub Agentic Workflows: the agent never holds a write token at all

[`github/gh-aw`](https://github.com/github/gh-aw), in technical preview since February 2026, is GitHub's own framework for running agents in Actions, and it takes the most structurally different position in this survey.

> "The agent job runs with minimal read-only permissions, while write operations are deferred to separate jobs."

> "SafeOutputs provides security by design: the agent never requires write permissions."

> "Agent execution never has direct write access to external state."

Concretely, for pull requests, the agent emits a git bundle as a workflow artifact.
A separate `safe_outputs` job then "checks out the target repository", "applies the bundle via `git fetch`", and "pushes the branch using the GitHub GraphQL API", and that job is the one holding the write token.
Draft status is "enforced as policy (default: true)" and the agent cannot override it at runtime.
For the merge safe output specifically, "merges to the repository default branch are always refused."
For reviews, the recommended configuration is `allowed-events: [COMMENT, REQUEST_CHANGES]`, deliberately omitting `APPROVE` so bot reviews stay informative and non-blocking.

The framework also stacks the controls research 0021 and 0022 already care about: Docker isolation by default, optionally gVisor or a KVM-isolated microVM, and an egress firewall proxying all traffic against a domain allowlist.

**This is the pattern this repo has genuinely not considered**, and it is the subject of section 5D.

### 4.4 OpenAI Codex: a tested execution-policy layer, and a written GitHub mutation policy

Codex turns out to be the most interesting vendor in the survey after GitHub itself, and in a different direction from the others.
It contributes almost nothing on the credential question and a great deal on the harness question.

**On credentials, Codex CLI has no GitHub identity of its own.**
Nothing in the repository mints, stores, or scopes a GitHub credential.
The agent runs on the operator's machine and uses whatever `git` and `gh` credentials that machine already holds, which means locally it is in the same position as this repo's PAT and worse: it inherits the operator's full GitHub identity rather than a repo-scoped token.
The hosted Codex product is a separate thing whose credential model is documented only on the unreachable site, so **that half remains unverified and no claim is made about it here**.

**On the harness, Codex ships a policy engine, not a settings list.**
`codex-rs/execpolicy` is a Starlark-based command policy evaluated before execution.
Its README states the model: rules are `prefix_rule(pattern=[...], decision?, justification?, match?, not_match?)`, "tokens are matched in order; any `pattern` element may be a list to denote alternatives", `decision` "defaults to `allow`; valid values: `allow`, `prompt`, `forbidden`", and "the effective `decision` is the strictest severity across all matches (`forbidden` > `prompt` > `allow`)".

Four properties of that design are worth extracting, because three of them are things this repo's recommendation 2 does not have.

- **Matching is on parsed argument tokens, not on a command string.** Claude Code's `Bash(gh pr merge:*)` matches text; `prefix_rule(pattern = ["gh", "pr", "merge"])` matches a tokenised prefix, with `host_executable(name=..., paths=[...])` controlling whether an absolute path like `/usr/bin/gh` may fall back to the basename rule. That closes a class of near-miss evasions, though it closes none of the real ones: an agent that reaches the same endpoint through `gh api --method PUT`, `curl`, or a script still needs a separate rule, exactly as section 5E says.
- **Rules carry a justification that is shown when they fire.** The README instructs authors that when `decision = "forbidden"` is used, "include a recommended alternative in the `justification`, when appropriate (e.g., ``"Use `jj` instead of `git`."``)". A refusal that tells the agent what to do instead is materially more useful than a bare denial, because the agent's next move is the thing you actually want to steer.
- **Rules are unit tested at load time.** `match` and `not_match` "supply example invocations that are validated at load time (think of them as unit tests)". The shipped example policy demonstrates it: a `["git", "reset", "--hard"]` `forbidden` rule asserts it matches `git reset --hard` and does **not** match `git reset --keep` or `git reset --merge`. This is the single most transferable idea in the whole survey for a repo whose standard is "verified by demonstration, not assumed from documentation".
- **The policy has an administrator layer the user cannot weaken.** `codex-rs/config/src/requirements_exec_policy.rs` defines a TOML form of `prefix_rule` deliverable through `requirements.toml`, a separate layer from user or project config. `codex-rs/config/src/requirements_layers/permissions.rs` opens with the design note that "`permissions.filesystem.deny_read` is intentionally additive across requirements layers", so layered denials accumulate rather than override. `docs/config.md` documents the same idea for hooks: "Admins can set top-level `allow_managed_hooks_only = true` in `requirements.toml` to ignore user, project, and session hook configs while still allowing managed hooks", and notes that putting it in `config.toml` does not work. This is the same shape as Claude Code's managed settings and `allowManagedPermissionRulesOnly`, arrived at independently by a second vendor, which is worth recording as convergence rather than coincidence.

**On merging specifically, Codex's control is a written policy document, not code and not a token.**
`.codex/skills/babysit-pr/SKILL.md` is OpenAI's own shipped skill for supervising a pull request through to landing, and it contains a section headed "GitHub State Mutation Policy" whose opening line is: "You can read any PR state you need for monitoring. Writes must comply with this policy."
The permitted writes are pushing to the pull request branch, rerunning failed checks, and resolving review threads belonging to the requesting human or the Codex review bot.
The explicit prohibitions are commenting on other humans' review threads, resolving other humans' threads, interacting with humans other than the user, marking pull requests as draft or ready for review, and closing or reopening pull requests.

**Merging is not on either list.**
The skill's stated objective is to babysit "until the PR is merged or closed", which positions the agent as waiting for someone else to merge rather than as the actor that merges.
The governing principle the section closes on is the sentence worth carrying over verbatim: "In general, never act on GitHub in ways that would make it hard to tell whether you or the user did something visible to other humans."

That is the same _category_ of control as ADR-0017's behavioural convention, and it is a useful calibration point: OpenAI, running agents against their own repository, also relies on a written convention for this rather than a token control, because as section 1.2 establishes there is no token control to rely on.
What they have that this repo does not is that the convention is a versioned, reviewed file with an explicit allow list and an explicit deny list, rather than a sentence in an issue.

**Real-repo evidence: what `openai/codex` actually configures on its own `main`.**
Read with `gh api repos/openai/codex/rulesets` and drilled into ruleset `6735016`, named "CI must pass to merge to main", `enforcement: active`, targeting `~DEFAULT_BRANCH`:

- `pull_request` with **`required_approving_review_count: 1`** and **`require_code_owner_review: true`**.
- `required_status_checks` requiring the contexts `cla` and `CI required`.
- `required_linear_history`, `creation`, `deletion`, and `non_fast_forward`.
- `allowed_merge_methods: ["squash"]` only.
- **`current_user_can_bypass: "never"`.** The `bypass_actors` array itself is not returned to a caller without administrative access on that repository, so what the bypass list contains is not observable from here and no claim is made about it.

`.github/CODEOWNERS` backs the code-owner rule, and its last entry is `/.github/CODEOWNERS @openai/codex-core-agent-team` with the comment "Keep ownership changes reviewed by the same team", which is the self-protecting entry that stops the gate being edited away.

This is the closest thing in the survey to a direct answer to issue #40's broader question, because it is a repository where agents demonstrably do the work, configured by the people who build the agent.
The configuration is exactly what section 5A recommends and exactly what this repo cannot currently run: one required approval, code owners, required checks, squash-only, linear history.
The reason they can and this repo cannot is that they are an organisation with more than one human, so the approval requirement has somebody to land on.
That is the whole distance between `openai/codex`'s ruleset and this repo's, and it is an identity problem rather than a configuration problem.

### 4.5 The other vendors, and the thin documentation

**Devin** ([docs](https://docs.devin.ai/integrations/gh)) requests read-and-write on checks, commit statuses, contents, discussions, issues, pull requests, projects and workflows - the widest permission set of any vendor surveyed, and wide enough to merge, forge statuses, and edit workflow files.
Its documented mitigation is to push the problem back to the customer: "We recommend enabling branch protection rules on your main branch to ensure all required checks pass before Devin can merge changes."
That sentence concedes, in Devin's own words, that Devin merges.
It also inherits GitHub's actor problem: "Devin uses the permissions granted at the organization level, not the permissions of the individual user running a session."

**OpenAI Codex** is covered in full in section 4.4, from its own repository.
The one part that remains unverified is the hosted Codex product's credential model, which is documented only on the unreachable site.

**Cursor background agents.** No first-party permission documentation found.
Community forum threads show background agents able to "clone repositories, create branches, and push commits" while failing on PR comments and reviews, with a recommended workaround of supplying a personal access token with issues and pull request scopes.
**Low confidence, forum evidence only.**

**Google Jules.** Its documentation was fetched successfully and states only that "Jules needs access to your repositories in order to work."
It documents no permission list, no merge policy, and no review gate.
Recorded as silence, not as a position.

**The pattern across vendors is worth naming, with one honest exception.**
Every _hosted_ agent that documents this at all converges on the same two things: the agent acts as a **bot identity distinct from the requesting human**, and the agent's **tool surface excludes merge** regardless of what its token could do.
The exception is the locally-run CLI shape, where Codex and Claude Code both execute on the operator's machine with the operator's own credentials, and therefore have no identity of their own at all - which is precisely this repo's situation and precisely why both vendors put their control in the harness instead.
Nobody solves it with token permissions, because as section 1.2 establishes, nobody can.

### 4.6 Practitioners

Savas Parastatidis's ["My Coding Agent Needed Its Own GitHub Identity"](https://savas.me/2026/04/27/my-coding-agent-needed-its-own-github-identity/) is the closest published analogue to this repo's situation, and he reaches the conclusion issue #40 anticipates.
He rejects both alternatives explicitly: "The agent can act as you - the problem. You can create a 'machine account' - but that's a fake human user with yet another username and password to rotate."
He runs a GitHub App, `savasp-agent[bot]`, minting tokens locally by signing "a JWT with your private key (10 minutes)" and exchanging it "for an installation access token (1 hour)", cached and refreshed automatically before expiry.
His ruleset is "PR required, no direct pushes, no bypass for admins", one approval required, stale reviews dismissed on new commits, status checks required, squash-only with auto-merge.
His two load-bearing sentences: "The important part is not just creating the App; it is also not giving the App bypass rights on `main`", and "The App can't approve its own PRs. When it opens one, a human has to review it."

The [dev.to incident writeup](https://dev.to/mjmirza/my-ai-agent-almost-merged-its-own-pull-request-23nk) is the same failure this issue is about, observed live: "My coding agent finished a feature, pushed the branch, opened the pull request, and typed the merge command", inside ninety seconds, with no human review.
The author's diagnosis is the sentence worth keeping: "My agent was never the problem. My repos had a merge path with no review step in it."

The [AWS control framework](https://aws.amazon.com/blogs/security/balancing-speed-and-safety-a-control-framework-for-ai-coding-agents/) splits controls into author-time (in the IDE: steering documents, scoped MCP credentials, hooks) and build-time (in the pipeline: scanning, quality gates, human approval), and states the separation principle directly: "The agent that wrote the code should not be the agent that reviews it."

**Where the community has no consensus:** whether the agent should get a write credential at all.
GitHub's own gh-aw says no and routes everything through a privileged post-processing job.
Copilot cloud agent says a very narrow one, minted internally, one branch.
Anthropic says yes but the harness refuses to merge.
OpenAI's CLI does not answer the question at all, because it inherits whatever the operator's machine already holds, and puts its controls in an execution policy and a written mutation policy instead.
Devin says yes to nearly everything and tells you to configure branch protection.
These are five different answers from five serious vendors, and this document does not manufacture a majority out of them.
What they do agree on is the negative: none of them relies on the agent's token permissions to prevent merging, because none of them can.

## 5. The five structural patterns, and what each actually costs

### A. Give the agent its own identity

A GitHub App (`<app>[bot]`) or a machine account.
This is the pattern the vendor survey converges on and the one issue #40 anticipates.

It works because it restores the actor axis section 3.1 says is missing.
Once the pull request is authored by a bot, `required_approving_review_count: 1` stops deadlocking and becomes a real gate, since the bot cannot approve its own pull request and the operator is now a different actor who can.
`require_last_push_approval` becomes meaningful for the same reason.
A CODEOWNERS file pointing at the operator becomes enforceable.
The bypass list can name the operator and exclude the bot.

Costs, honestly:

- A GitHub App means the one-hour token ceiling, addressed in section 6.
- A machine account is explicitly permitted by GitHub's Terms of Service: "One person or legal entity may maintain no more than one free Account (if you choose to control a machine account as well, that's fine, but it can only be used for running a machine)", and "You may maintain no more than one free machine account in addition to your free Personal Account." So this is not a grey area. But it means a second set of credentials to rotate and a second 2FA enrolment, which is exactly Parastatidis's objection.
- Either way the operator must actually review. An identity split that ends with the operator reflexively clicking approve buys attribution, not review. That is a real risk in a solo repository and should be named rather than assumed away.

### B. Split the credential: push over SSH, API over HTTPS

The one crack in section 1.2's wall.
A **deploy key** is scoped to a single repository, is "read-only by default, but you can give them write access", and is an SSH credential used by git.
GitHub's deploy-key documentation does not state whether a deploy key can call the REST API, and I could not find a first-party statement either way, so this is flagged as needing demonstration rather than asserted.

If it holds, the shape is: push with a write deploy key, and hold a separate fine-grained PAT with `Pull requests: write` and `Metadata: read` but **no Contents** for opening the pull request and commenting.
That token cannot merge, because merge is a Contents endpoint.
Two things need demonstrating before this is real: that a deploy key genuinely has no API surface, and that `POST /repos/{owner}/{repo}/pulls` actually succeeds with Pull requests: write and no Contents permission (the endpoint page adds "you must have write access to the head or the source branch", and whether a Contents-less fine-grained PAT satisfies that is not documented).

The cost is one this repo has already priced.
ADR-0015 rejected deploy keys on the grounds that they are "real key material resident in guest storage and a genuine departure from the placeholder model", since microsandbox's `--secret` works by host-scoped TLS interception on HTTPS and cannot substitute anything inside an SSH session.
That objection stands, and it is a genuine trade: the placeholder model versus a credential split.
Worth noting that a deploy key's blast radius if exfiltrated is push access to one repository with no API - narrower in kind than the current PAT, which can also merge, comment, and file issues.

### C. Push somewhere else

Pushing to a fork closes this at the token-scope level cleanly, because the credential's `Contents: write` applies to the fork, and merging into the upstream needs `Contents: write` on the upstream, which the credential does not have.

The operational cost for **this** repository is higher than it looks.
GitHub does not permit forking a repository into the account that already owns it, with or without a different name, so a fork of `afrossard/container-base` requires a second owner: an organization, or the machine account from pattern A.
And a fine-grained PAT owned by that second account hits a documented gap: "Using fine-grained personal access token to contribute to public repos where the user is not a member" is on GitHub's own list of things fine-grained PATs cannot do, so the cross-fork pull request would need a classic PAT with `public_repo`, which is broader than the fine-grained token it replaces.

So the fork model costs a second identity anyway.
And once a second identity exists, pattern A is strictly better: it delivers the same merge exclusion plus a usable approval gate plus bot attribution in `git log`, without the fork's sync overhead.
**The fork model is not worth adopting here, and the reason is specific to this repository being personally owned rather than a general objection.**

No evidence was found of anyone in the community running agents through forks as a deliberate control.
Every vendor surveyed pushes branches into the target repository.

### D. Do not give the agent a write credential at all

The gh-aw pattern from section 4.3, and structurally the same thing Copilot cloud agent does by not letting the agent run git.

The agent produces a change as _data_ - a patch, a git bundle, a diff - and a separate trusted component with the write credential applies it.
The agent's own credential is read-only, or absent.
Merge is not excluded by a rule; it is unreachable because nothing the agent holds can write to GitHub.

This repository has already done this once, accidentally, and it worked.
AGENTS.md records that in issue #37's session the PAT lacked the `workflow` scope, so "the diff was posted to the issue as a comment instead of a commit, then applied, pushed, and opened as PR #56 by a separate, more-privileged session."
That is the safe-outputs shape, arrived at by accident, and it did not break the workflow.

Research 0016 records that the same shape was this repo's baseline before #34: "the agent commits locally but does not push, interacts with issues through a fine-grained PAT scoped to this repo with only `Issues: write`, and delivers code as a diff a human applies."
ADR-0015 then rejected the no-credential variant, and the reason it gives is worth quoting because it is narrower than it first reads: it rejected "no credential in the guest at all", on the grounds that "an agent that cannot open its own pull request, comment, or file an issue is missing most of what makes an autonomous session worth launching."
That objection is about _pull requests, comments and issues_, which are Pull-requests-and-Issues-write concerns.
It is not an argument for `Contents: write`.
A guest holding `Pull requests: write` and `Issues: write` but no `Contents` keeps everything ADR-0015 says it needs, and loses only the ability to push - which is exactly pattern B's other half, and which `msb copy` plus a host-side push already covers per ADR-0015's own "reviewing before publication is possible without a mount" consequence.

The cost is real: a host-side step between the agent finishing and the branch existing.
For the attended shape ADR-0017 is building, a human is already present, so that step is nearly free.
For the headless shape it needs automating, and automating it means the automation holds the write credential - which is exactly gh-aw's `safe_outputs` job.

### E. Deny it below GitHub

Three sub-layers, none of them a boundary, all of them cheap.

**The harness permission layer.** Claude Code's `permissions.deny` rules use the same `Bash(pattern)` syntax as allow rules, "denylist takes precedence over allowlist", and deny rules are enforced in every permission mode including bypass.
A `Bash(gh pr merge:*)` deny entry in `.claude/settings.json` would stop the literal command.
It is porous by construction: the agent could reach the same endpoint with `gh api --method PUT`, with `curl`, or with a shell construction the pattern does not match, and the microsandbox `--secret` scoping covers `api.github.com`, so a `curl` would get the real token substituted.
Worth having as a tripwire and a statement of intent; not worth calling a control.

**A `PreToolUse` hook.** Strictly stronger than a deny rule, because a hook receives `tool_input.command` and can apply arbitrary logic before returning `{"permissionDecision": "deny"}` or exiting 2.
It can match on the endpoint rather than the command name, which closes the `gh api` variant.
Still a harness-layer control that a sufficiently creative agent can route around, and still worth a great deal more than the prompt-level convention #40 currently records.

**Codex's execpolicy corroborates this whole sub-layer, and sharpens two details.**
Section 4.4 covers it in full; the parts that bear on recommendation 2 are that a second vendor independently arrived at the same three-valued decision model with strictest-wins precedence (`forbidden` > `prompt` > `allow`, against Claude Code's deny-beats-ask-beats-allow), the same admin-layer-cannot-be-weakened-by-user-config principle, denial rules that carry a justification naming the alternative, and - the part with no counterpart on the Claude Code side - denial rules that ship with `match` and `not_match` example invocations validated at load time.
None of that changes the conclusion that this layer is porous rather than a boundary.
It does raise how much of a control it is worth treating as, because a deny rule that is tested is a deny rule that is known to fire, and an untested one is a comment.

**A filtering proxy on the wire.** The tool from discussion #182732, [`carrotRakko/github-finest-grained-permission-proxy`](https://github.com/carrotRakko/github-finest-grained-permission-proxy), is architecturally the same idea as this repo's `--secret` model: "FGP isolates GitHub Personal Access Tokens from AI agents running in containers by keeping tokens on the host side", with `Container (fgh CLI) -> HTTP -> Host-side proxy (fgp) -> GitHub API/git`, plus AWS-IAM-style policy evaluation on top.
It is **archived and unmaintained** as of March 2026 with 2 stars, superseded by a successor project that could not be located, and it does not in fact block the merge endpoint.
Recorded because it demonstrates that at least one other person hit this exact problem and built the exact thing, not as a tool to adopt.

The interesting observation for this repo is that microsandbox already terminates TLS for `github.com` and `api.github.com` in order to substitute the placeholder (issue #34's finding).
An endpoint-level policy is therefore _architecturally_ within reach at the substrate, not just at the harness.
Whether microsandbox exposes any such hook is not established here and would need checking against its own documentation.

## 6. The GitHub App path, and the one-hour ceiling

Issue #40 asks whether an App-authored pull request genuinely restores the review gate.
It does, and the mechanism is section 3.1's actor axis rather than anything App-specific: the pull request author becomes `<app>[bot]`, the operator stops being the author, and "pull request authors cannot approve their own pull requests" stops pointing at the operator.
`required_approving_review_count` can go from 0 to 1 and become a real requirement instead of a deadlock.
Parastatidis's setup is exactly this and he states the result plainly: "The App can't approve its own PRs. When it opens one, a human has to review it."

Two caveats.

**The App must not be on the bypass list.** This is the whole point of Parastatidis's second load-bearing sentence, and it is the mistake that would silently undo the change. Section 2 shows this repo's bypass list is currently empty and should stay that way.

**Whether an App's own approving review counts toward required approvals is a separate question this document does not settle.** It matters only if someone later tries to close the loop with a second bot rather than a human, which would be theatre. GitHub's related lever - "Preventing GitHub Actions from creating or approving pull requests", where "by default, when you create a new repository in your personal account, workflows are not allowed to create or approve pull requests" - is evidence that GitHub treats bot self-approval as a thing to be off by default.

**On the one-hour ceiling.**
ADR-0015 defers the App because "the one-hour ceiling would expire mid-session, with the failure surfacing on the final push after all the work", and because "GitHub ships no supported local minting tool (`gh api` has no JWT or App auth; `actions/create-github-app-token` is CI-only)."

The documentation confirms the ceiling exactly: "The installation access token will expire after 1 hour."
It also shows the refresh flow is a documented, first-class thing rather than a workaround: "The SDK will take care of generating an installation access token for you and will regenerate the token once it expires."
And minting supports narrowing at mint time - `repositories` / `repository_ids` to scope to individual repositories, and `permissions` to request less than the App was granted - which is a real advantage over a PAT, whose permission set is fixed when it is created.
Parastatidis reports doing exactly this locally: sign a 10-minute JWT with the private key, exchange it for a 1-hour installation token, cache and refresh before expiry.

So the ceiling is solved in the general case.
The part that is **not** solved for this repo's architecture, and that ADR-0015 was right to flag, is _where the refresh loop runs_.

- If the refresh loop runs **inside the guest**, the guest must hold the App's private key. That is a durable, non-expiring secret with a far larger blast radius than the PAT it replaces, resident in guest storage, and it defeats the entire point of the placeholder model. This is the wrong answer.
- If the refresh loop runs **on the host**, the private key stays out of the guest, but `msb run --secret` substitutes a fixed value at launch. A token injected that way goes stale after an hour and there is no documented mechanism for the host to push a new one into a running guest.

The shape that resolves this is a host-side credential broker: the guest holds a placeholder or talks to a loopback endpoint, and the host mints on demand.
That is the same architecture as the FGP proxy in section 5E, and the same architecture as gh-aw's separation of the agent job from the write job.
It is also, notably, more machinery than this repo has built for anything else, and it should be scoped as its own issue rather than folded into #40.

**A cheaper interim observation:** for the _headless_ shape ADR-0013 describes, sessions are short and scripted, so a token minted at launch may simply outlive the session.
The one-hour ceiling is a problem for the _attended_ shape ADR-0017 is building first, which is precisely the shape where a human is present and the behavioural convention is least likely to fail.
That inversion is worth recording: the credential model and the session model want opposite things, and building the attended shape first means the App's costs land before its benefits do.

## 7. Controls outside GitHub entirely

Beyond section 5E's harness layer, this repository already carries more of this than issue #40 credits it with.

- **The permission mode.** ADR-0017 chose auto mode over `--dangerously-skip-permissions` on exactly this reasoning: "The VM bounds what the agent can do to the host, and it does that completely. It bounds nothing about the two things a session is deliberately handed: a GitHub credential and an open internet connection", and it names "merging its own pull request" in the list. Auto mode is the control currently covering issue #40, and ADR-0017 already says so.
- **Sandboxed bash.** `.claude/settings.json` commits `sandbox.enabled` and `sandbox.autoAllowBashIfSandboxed` (issue #35). It has no `permissions` block at all today, so there is nowhere a deny rule currently lives.
- **Egress policy.** Issue #30 pinned `--net public`, verified against a live guest. That denies private networks and metadata endpoints but permits `api.github.com`, which is the endpoint that matters here.
- **Secret scoping.** `--secret "GH_TOKEN@github.com,api.github.com"` with `--on-secret-violation block-and-log` means the token cannot leave for an out-of-scope host, verified in #34. It does not constrain what the token does at the hosts it is scoped to.
- **The `workflow` scope gap.** Recorded in AGENTS.md from #37: the PAT cannot push anything touching `.github/workflows/`, so the agent cannot rewrite CI to make a required check pass. This is an accidental but genuinely load-bearing control, and it should be treated as a deliberate constraint on the token from now on rather than a happy accident.

## 8. What the community does that this repo has not considered

Ranked by how much they change the picture.

1. **The agent never holds the write credential; a separate trusted step does.** gh-aw's safe outputs and Copilot cloud agent's "cannot run git commands". This is the only pattern in the survey that makes merge structurally unreachable rather than merely unauthorized, and it is GitHub's own answer in its own framework. Section 5D.
2. **Restricting the agent to a single writable branch.** Copilot's `copilot/` prefix is the control this repo's ruleset cannot express, and the reason it cannot is that GitHub does not expose branch-scoped write in any public credential type. Naming the asymmetry is useful even though it cannot be adopted.
3. **Denial rules that ship with their own tests.** Codex's execpolicy validates each rule's `match` and `not_match` example invocations at load time, so a `forbidden` rule for `git reset --hard` proves at startup that it fires on `git reset --hard` and does not fire on `git reset --keep`. This repo's standard is that a control is verified by demonstration rather than assumed, and this is that standard applied to the deny rule itself. Nothing in Claude Code's `permissions` schema does this, but a bats case asserting that the deny rule blocks `gh pr merge` and that a `PreToolUse` hook blocks `gh api --method PUT .../merge` is the same idea and costs very little. Section 5E.
4. **Gating CI on a human, separately from gating merge on a human.** Copilot's "Approve and run workflows" is a second, independent checkpoint: the agent's code cannot even _execute_ in CI until a human looks. GitHub's [June 2026 changelog](https://github.blog/changelog/2026-06-11-bot-created-pull-requests-can-run-workflows-if-approved/) extends the same model to `github-actions[bot]` PRs, and states the failure it prevents: previously such PRs "were not able to run CI/CD workflows, allowing pull requests to be accidentally merged without having gone through CI." This repo currently has the opposite posture - the agent's PRs run CI immediately and nothing gates the merge.
5. **CODEOWNERS over the agent's own configuration files, including CODEOWNERS itself.** GitHub's guardrails tutorial recommends protecting "important Copilot and MCP configuration files" with CODEOWNERS. `openai/codex` does exactly this and closes the obvious hole: its last entry is `/.github/CODEOWNERS @openai/codex-core-agent-team`, commented "Keep ownership changes reviewed by the same team". The analogue here is `.claude/`, `.github/workflows/`, `scripts/launch-agent-runtime`, and the CODEOWNERS file itself - the files that determine what the _next_ agent session can do. This is cheap and this repo has no CODEOWNERS at all.
6. **A written, versioned state-mutation policy with an explicit allow list and an explicit deny list.** Codex's `babysit-pr` skill devotes a section to "GitHub State Mutation Policy" enumerating exactly which writes the agent may perform and which it may not, and closes with a general principle rather than a rule list: "never act on GitHub in ways that would make it hard to tell whether you or the user did something visible to other humans." This is the same category of control as #40's current behavioural convention, but as a reviewed file rather than a sentence in an issue, which makes it auditable, diffable, and inheritable by the next session. Cheap, and strictly better than what #40 records today.
7. **Enforcing the refusal in the harness rather than the prompt.** Anthropic's own action does not tell Claude not to merge; it gives Claude no merge capability. #40 currently records a prompt-level convention.
8. **Signed commits and bot co-author attribution as an audit control.** Copilot signs its commits and attributes them; `claude-code-action` documents optional GitHub-API or SSH commit signing. This repo's ruleset has no `required_signatures` rule. It gates nothing on its own but it makes "which commits did an agent write" answerable after the fact, which is the question you want answerable when something goes wrong.
9. **Draft-by-default pull requests.** gh-aw enforces `draft: true` as policy the agent cannot override. A draft PR cannot be merged, so this is a genuine, if soft, gate that costs one flag on `gh pr create`. Nothing in this repo currently sets it.

## Recommendations

### Record the ground truth first, because it closes off two of the three options #40 lists

**Recommendation: write an ADR stating that within one repository, one credential, push access and merge access are the same GitHub permission, and that no token or ruleset configuration separates them.**

This is verified in section 1 and corroborated by community discussion #182732.
It disposes of the search for a cleverer ruleset, and it reframes the remaining options correctly: change the agent's identity, or stop giving it a write credential.
It also converts issue #31's `required_approving_review_count: 0` from an embarrassing compromise into a correct consequence of a documented constraint, which is worth having written down where a future reader will find it.

### Do not adopt the fork model

**Recommendation: close the fork option in #40 explicitly, with the reason.**

GitHub does not permit forking a repository into the account that owns it, so a fork of `afrossard/container-base` requires a second owner.
A fine-grained PAT from that second account cannot open a cross-fork pull request against a public repo it is not a member of, per GitHub's own list of known gaps, so it would need a classic `public_repo` PAT - broader than what it replaces.
And once a second identity exists, the GitHub App path delivers the same merge exclusion plus a working approval gate plus bot attribution, for less ongoing cost.
No source in this survey shows anyone running agents through forks as a deliberate control.

### The destination is the identity split, and it is the App

**Recommendation: keep ADR-0015's GitHub App as the destination, and make it explicit that the App is not a credential-hygiene improvement but the mechanism that makes a review gate possible at all.**

Once pull requests are authored by `<app>[bot]`, `required_approving_review_count` goes from 0 to 1 and stops being a deadlock.
That single change is the whole of issue #40's fix.
Two conditions on it: the App must never appear in the ruleset's `bypass_actors`, and the operator must actually read the diff rather than reflexively approving, which is a discipline problem an identity split does not solve.

`openai/codex`'s own live ruleset (section 4.4) is that target configuration stated concretely, by a team that builds a coding agent and runs it against that repository: one required approval, `require_code_owner_review: true`, required status checks, `required_linear_history`, squash-only, and `current_user_can_bypass: "never"`.
The only piece of it this repo cannot copy today is the approval, and the reason is that they have more than one human.

The one-hour ceiling is solved in the general case by the documented refresh flow, but not for this architecture, because the private key must not enter the guest and `msb run --secret` substitutes a fixed value at launch.
That needs a host-side credential broker, which is a separate piece of machinery and should be **its own issue**, not a sub-task of #40.

### In the meantime, four cheap things that are worth doing now

These do not close #40. They narrow it, and each is small enough to land without a design session.

1. **Mark `format` as a required status check.** Section 3.5 establishes it is a real gate against this specific token, which holds no Actions, Commit statuses, or Checks permission and cannot push workflow files. It gates correctness, not review. Record alongside it that granting the token `Actions: write` later would silently turn it into theatre.
2. **Add a `permissions.deny` block to `.claude/settings.json`, plus a `PreToolUse` hook, and write a test for both.** Deny rules are enforced in every permission mode including bypass, and a hook can match the endpoint rather than the command string, closing the `gh api --method PUT` variant a deny rule misses. Both are harness-layer and porous; the honest framing is a tripwire that makes an accidental merge require deliberate circumvention, upgrading #40's prompt-level convention to a code-level one. This is what Anthropic's own action does one layer down, and what Codex's execpolicy does one layer down in the other direction. The test is the part borrowed from Codex specifically: execpolicy validates each rule's `match` and `not_match` examples at load time, and the equivalent here is a bats case asserting the rule fires on `gh pr merge` and on the `gh api` form, and does not fire on `gh pr create`. Without it the deny rule is a comment.
3. **Add a `CODEOWNERS` file over `.claude/`, `.github/`, `scripts/`, and `CODEOWNERS` itself.** It gates nothing while the operator is the only identity, and it starts gating the moment the App lands. It is GitHub's own top guardrail recommendation for its own agent, `openai/codex` runs exactly this shape including the self-protecting entry on the file itself, and the files it covers are the ones that determine what the next session can do.
4. **Write the mutation policy down.** #40 currently records "the agent is only ever instructed to open a PR and stop" as a convention living in an issue. Codex ships the same category of control as a section of a versioned skill file, with an explicit list of permitted writes, an explicit list of forbidden ones, and a general principle covering the cases neither list anticipated. The natural home here is this repo's `AGENTS.md` or a `docs/agents/` entry, and it costs one file.

Two more worth considering and cheaper to argue about than to build: opening agent pull requests as drafts by default (gh-aw enforces this as policy), and adding a `required_signatures` rule so agent-authored commits are distinguishable after the fact.

### Two things to settle by demonstration, per #40's own acceptance criteria

- **Does the ruleset `update` rule apply to pull request merges, or only to direct pushes?** Section 3.7. If it applies to merges, then `update` plus a bypass list naming only the operator's App-free identity is a genuine actor-level merge gate, and community discussion #113172 suggests it may block bypass actors too, which would be a different and worse outcome. This is worth an experiment on a throwaway branch before it is designed around.
- **Can a fine-grained PAT with `Pull requests: write` and no `Contents` permission open a pull request?** Section 5B. If yes, then the deploy-key split is real and the agent could hold a token that provably cannot merge, at the cost ADR-0015 already priced. If no, pattern B collapses and pattern D is the only remaining option short of the App.
