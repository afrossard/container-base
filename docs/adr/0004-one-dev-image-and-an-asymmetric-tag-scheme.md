# One dev image, and an asymmetric tag scheme

ADR-0003 published every language-variant × build-variant combination, which made adding a language cost two images and made the dev side grow without bound.
We publish exactly one dev image carrying every language toolchain, and keep the language axis only for runtime bases.
The two sides were never the same kind of artifact: a dev image is a workstation you work inside and should have everything, while a runtime base is a floor you build on and should have as little as possible.
Forcing them into one `{language}-{build}` scheme is what generated the combinatorics.

Tags carry the version as a prefix and the variant as a suffix, in a single GHCR package:

```
ghcr.io/afrossard/container-base:1.4.2-dev
ghcr.io/afrossard/container-base:1.4.2-base-prod
ghcr.io/afrossard/container-base:1.4.2-python-prod
```

## Considered options

Separate GHCR packages per artifact kind (`container-base/dev:1.4.2`) were seriously considered, because the two really are different things and Microsoft's own devcontainer images are named that way.
Rejected on the observation that `debian:trixie` and `debian:trixie-slim` are also very different artifacts under one name and nobody finds that confusing, so one package with expressive tags is sufficient and costs one fewer package to publish and grant access to.

Putting the variant first (`dev-1.4.2`) was rejected on measured Renovate behaviour rather than on taste.
Renovate handles a version **suffix** natively: it bumps `1.2.0-alpine` to `1.2.1-alpine` and never rewrites the suffix, treating it as a compatibility marker.
A version **prefix** is the one form that needs custom regex `packageRules`, which would have to be configured in every consumer repo - itself a drift surface, and drift is what this repo exists to remove.

Mutable tags with no version, so that every rebuild converges the whole estate automatically, were rejected in favour of pinned versions bumped by Renovate.
The convergence argument is real and was the reason to consider it, but a production image built from a moving base cannot answer what was actually shipped last Tuesday.

## Consequences

- `CONTEXT.md`'s "every language variant publishes both build variants" is false and has been rewritten. There is no `python-dev`.
- Adding a language adds one runtime base, and adds nothing at all to the dev image beyond what its language manager already resolves (ADR-0006).
- The dev image is larger than any single-language `-dev` image would have been. Accepted: it is a workstation, and one image that is always right beats four that each might not be.
- Consumers pin a version and Renovate bumps it with no per-repo configuration.
