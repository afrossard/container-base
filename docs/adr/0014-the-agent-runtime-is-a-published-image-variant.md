# The agent runtime ships as a published image variant

ADR-0011 rejected a second published image on the grounds that the safety-critical controls are launch-time properties an image cannot grant itself, so a hardened image buys almost nothing.
That argument is sound and it does not cover this artifact, because it is about **policy** - firewalls, capabilities, `no-new-privileges` - and the agent runtime differs from the dev image in **carried capability**: it holds a docker daemon, an init or supervisor to run that daemon alongside the agent, and the agent CLI, and it carries no editor server.

We publish it as a third variant, `{version}-agent`, alongside `-dev` and `{language variant}-prod`, from the same GHCR pipeline that publishes the dev image today.

Two things make this the cheap answer rather than a new axis of work.
ADR-0013 defines the reusable, never-written-by-a-session part of an agent runtime as a prebuilt image, which is a published artifact by construction - and publishing shared container images is the entire scope of this repo (ADR-0001).
And a per-container-VM tool that consumes OCI images boots one directly as a VM guest, so `docker build` → GHCR → run-as-a-VM needs no VM-image format, no disk-image publishing, and no second pipeline.

## Consequences

- **ADR-0004's asymmetric tag scheme absorbs this without combinatorics.** `agent` is unqualified by language, exactly like `dev`; only runtime bases keep the language axis. Adding a language still adds one runtime base and nothing else.
- **`CONTEXT.md`'s image-tag entry gains a variant**, and the publish workflow gains one build, not a new package.
- **The agent never needs registry-push credentials.** It builds and tests images; CI publishes them, as it does today.
- **ADR-0011 narrows rather than reverses.** Its conclusion - that hardening is composed by whoever launches, and the image ships enabling machinery rather than active policy - is unchanged and applies to the agent runtime image too.
- **Whether this image is published from this repo long-term is still open.** It is an image, and images are what this repo publishes, which is the argument for keeping it here; if the runtime grows parts that are not image-shaped, that argument weakens.
- **`scripts/launch-agent-runtime` is a deliberate, noted exception to ADR-0001's scope.** The image is what this repo publishes; launching it as a microsandbox guest - the disk-backed `/var/lib/docker` volume, `--secret` credential injection, no default command (`docs/research/0022`) - is host-side tooling that consumes the image rather than an image itself. It lives here anyway, next to the artifact it launches, rather than in a separate repo: it has no independent reason to exist, and splitting it out would just add a repo boundary between a script and its one caller for no isolation or reuse benefit. If it ever grows features unrelated to launching this repo's own image, that argument weakens the same way the previous consequence already flags for the image itself.
