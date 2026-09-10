# Captain preferences

Fixed preferences for the captain session in this runtime, applied by the
`provision-firstmate` recipe (issue #145, ADR-0021).
Reviewable here as a diff, not improvised per session.

## Model discipline

Every agent in the fleet runs on Sonnet.
The larger tiers are barred; `tooling/firstmate/model-guard` fails the
runtime if a barred tier is configured or running.
Open the captain with the `captain` alias, never a bare `claude` - the
alias pins `--model` so no interactive picker is reachable.

## Dispatch

Crewmates and scouts are pinned by `config/crew-dispatch.json`.
Do not pass a different `--model` at dispatch time.

## Merge authority

This runtime manages one project, `container-base`.
Ship tasks land as pull requests through the no-mistakes gate
(`.no-mistakes.yaml`), never by direct push (ADR-0015).

## Escalation

Escalate to the operator on: a failing gate that a mechanical fix will
not clear, a credential expiry, or any request to touch a repo other
than the managed project.
