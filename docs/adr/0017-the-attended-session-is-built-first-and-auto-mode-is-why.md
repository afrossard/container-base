# The attended session is built first, and auto mode is what makes it safe

ADR-0013 architected the agent runtime for autonomy: disposable, no persistent writable state, one repo, a lifetime equal to the task's.
The first shape actually being built is the other one - a human at the keyboard, launching a guest, and driving Claude Code in auto mode inside it.

That is deliberate, and it is recorded here because the two read as contradicting each other and the reasoning otherwise lives nowhere.

The headless shape is the destination, not an abandoned option.

## Why attended first

- `--persist-claude-auth` had already landed and serves only the attended shape, since research 0022's addendum established that the interactive TUI requires a real browser OAuth login while headless invocation authenticates from an environment variable. Finishing the attended path banks work already done rather than stranding it.
- The workspace-in and branch-out problem (ADR-0015) is identical for both shapes, so solving it with a human watching de-risks it for the unattended one at no extra cost.
- Auto mode unattended is the worst place to discover that the classifier's failure mode is a silent block rather than a loud error. With a human present that takes seconds to find.

## Why auto mode rather than `--dangerously-skip-permissions`

The natural objection is that building a hypervisor boundary in order to keep asking permission is self-defeating.
It is not, because **the VM and the permission mode guard disjoint assets.**

The VM bounds what the agent can do to the **host**, and it does that completely.
It bounds nothing about the two things a session is deliberately handed: a GitHub credential and an open internet connection.
Force-pushing over a branch, filing issues in bulk, merging its own pull request, pulling arbitrary code into the work product - the hypervisor is irrelevant to every one of them.
Auto mode is the only control covering that surface.

This also matches Claude Code's own guidance, which reserves bypass for sandboxes **with no internet access**.
The agent runtime has internet by design (ADR-0015 depends on it for both the clone and the push), so the precondition for bypass is never met.

## Consequences

- **The launcher's interactive affordances are deliberate and must not be "corrected" toward disposability.** Persisted credentials, sandbox reuse across launches, and interactive replace/abort prompts all pull against ADR-0013's disposable-VM model. They are the attended shape working as intended. A future reader comparing the launcher against ADR-0013 alone would reasonably conclude it had drifted; it has not.
- **The accretion risk is real and accepted.** Each affordance added for the attended shape makes the disposable one marginally harder to reach later. The mitigation is that `--persist-claude-auth` already defaults off whenever a command is given, keeping the headless path on the stricter default without a flag.
- **Three things are known to need revisiting when the headless shape is built**, rather than being discovered then: ADR-0016's reproducibility hole, since dotfiles make session behaviour depend on host-side state; ADR-0015's credential, where a GitHub App's one-hour token and bot attribution become advantages rather than costs; and the egress policy, which was left open partly because a human is present to notice anything strange.
- **`disableBypassPermissionsMode` stays parked.** Issue #13 raised shipping a baseline `managed-settings.json` in the image. ADR-0011's rule is that the image ships enabling machinery and never active policy, and a published image carrying a permission policy is precisely that. If bypass ever needs forbidding, it is the launcher's or the operator's business.
