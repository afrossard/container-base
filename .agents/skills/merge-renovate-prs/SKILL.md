---
name: merge-renovate-prs
description: Review and merge this repo's open Renovate dependency-bump PRs, applying the shipped-dependency release policy and agent autonomy boundary from CONTRIBUTING.md. Use when asked to merge, review, or triage Renovate PRs, or clear the Renovate/dependency-bump backlog.
---

Read CONTRIBUTING.md's "Renovate PRs and releases" section first - it holds the policy this skill only executes.

List every open Renovate PR: `gh pr list --state open --json number,title,headRefName,statusCheckRollup --search "head:renovate/"`.

For each one, in order:

1. **Green CI?** Check `statusCheckRollup`. Red or pending: leave it open, move to the next PR.
2. **Shipped-dependency major?** The title carries no breaking marker either way - Renovate can't emit one - so judge by the diff, not the title: does the PR touch `images/**`, and is it a major bump? If not, skip to step 3.
   Read the diff and decide whether it's actually breaking for a consumer (a changed default, a removed flag a consumer script relies on), not just "the version number jumped."
   Not breaking: skip to step 3, merge normally.
   Breaking: stop on this PR, don't merge, and present the diff, the reasoning, and the PR link to the operator instead.
3. **Everything else on green CI** (`chore(deps)`, or a non-major `fix(deps)`/`feat(deps)`): merge with the generated title, unedited, via `gh pr merge <number> --squash --delete-branch` (docs/agents/issue-tracker.md's standard merge convention).

Never edit a Renovate-generated PR title before merging - Renovate reverts it to its own on the next run it touches the branch anyway, so the only place an escalation sticks is the squash commit subject at merge time.
