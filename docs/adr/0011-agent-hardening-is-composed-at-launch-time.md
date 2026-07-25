# Agent hardening is composed at launch time, not baked into a second image

Issue #13 asked which of Anthropic's reference devcontainer hardening mechanisms belong in this repo's dev image for autonomous / auto-mode agent use, and whether a separate hardened image is warranted the way a consumer like `actual-budget-transformer` gets its own Containerfile.

The controls that actually make auto mode safe at runtime - a default-deny network egress firewall, withholding host secrets, dropping Linux capabilities, `no-new-privileges` - are **launch-time** properties.
An OCI image carries a filesystem and metadata; it cannot grant itself capabilities (`NET_ADMIN`/`NET_RAW`), cannot decide which host paths are mounted, and cannot set `no-new-privileges`.
Those are set by whoever launches the container: `docker run`, a devcontainer's `runArgs`, a compose file, a Kubernetes `securityContext`.
A second "hardened" image therefore buys almost nothing - it still cannot turn its own firewall on - and the one thing it could bake differently, a `managed-settings.json` permission policy, is threat-model-specific and belongs to the consumer or org, not a shared base (ADR-0010's "fourth thing").

So there is **one dev image** (ADR-0004 holds), carrying only what is image-shaped: a non-root default user, bubblewrap, `DISABLE_AUTOUPDATER`, and an **inert** egress-firewall script - dormant, the same shape as `dotfiles-bootstrap`, which ships and does nothing until configured.
Everything else is composed at launch by a **reference profile**: the devcontainer configuration this repo dogfoods as its own first consumer.

## Considered options

- **A separate `-agent` / hardened published image.** Rejected: the safety-critical controls are launch-time, so a second image cannot deliver a turnkey-safe runtime; it would only add a variant axis to the tag matrix that ADR-0004 deliberately keeps flat, for no security gain.

## Consequences

- Each mechanism has a home in a four-tier model - **image** (this repo), **launch / consumer devcontainer**, **dotfiles** (personal), **org policy** (a separate repo, ADR-0010's fourth thing). The image column is deliberately small; most hardening lands in the launch tier.
- The image ships enabling machinery, never active policy, and presumes no threat model. A consumer that needs no hardening pays nothing; one that needs it composes the profile.
- This repo's own `.devcontainer/devcontainer.json` is the reference profile and the acceptance test for the approach.
