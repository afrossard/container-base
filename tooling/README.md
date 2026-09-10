<!-- model-guard: skip-prose-scan - this file documents the model policy in prose -->

# tooling/

Versioned tooling recipes: the fixed configuration and provisioning instructions that bring a freshly reset agent runtime back to a working workflow stack without an operator following a readme by hand (ADR-0021).

## Scope exception

This repo publishes shared container images and nothing else (ADR-0001).
`tooling/` is a deliberate, documented exception to that image-only scope, exactly like the host-side launcher under `scripts/` (ADR-0014).
It is neither an image nor a layer of one.
It lives here because it is a handful of small files that need review in the same diffs as the runtime they provision, and because the runtime's workspace clone is this repo, so a fresh runtime already has the recipe on disk.
It is the first thing to extract into its own repo if it grows a second recipe or a firstmate hub that manages more than one project.

## Recipes

### `firstmate/`

The firstmate + no-mistakes stack.
Every "applied as" path is where the provisioning skill copies the fixed file; the skill then verifies firstmate or no-mistakes actually reads it.

| File                 | Applied as                                      | Purpose                                            |
| -------------------- | ----------------------------------------------- | -------------------------------------------------- |
| `crew-dispatch.json` | `$FM_HOME/config/crew-dispatch.json`            | Crewmate and scout dispatch pin (harness, model)   |
| `captain.md`         | `$FM_HOME/data/captain.md`                      | Captain preferences                                |
| `no-mistakes.yaml`   | `$FM_HOME/projects/<project>/.no-mistakes.yaml` | Gate-agent model pin and merge mode                |
| `captain.sh`         | sourced from the runtime shell rc               | `captain` launch alias, model pinned explicitly    |
| `model-guard`        | run as a check                                  | Deterministic opus/fable assertion                 |
| `SKILL.md`           | invoked by the applying agent                   | Provisioning skill: applies and verifies the above |

## Version policy

Firstmate's tool family (herdr, treehouse, the axi npm globals) ships two disagreeing version sources: firstmate's own pinned installers under `bin/fm-install-*.sh`, and Homebrew's floating latest.

**This recipe takes Homebrew's floating latest.**
Firstmate's consent flow is still what installs the tools - the recipe never bypasses the consent gate - but where that flow would pin a version behind Homebrew's latest, the applying agent takes the latest and verifies it against firstmate's stated contract: published protocol floors where firstmate publishes them, observed behaviour where it does not.
Firstmate's pinned installer is the fallback for a tool whose floating latest fails that verification.
This choice is recorded here so it is deliberate rather than accidental (issue #100 candidate 2, issue #145).

## Model policy

Every agent this recipe configures runs on Sonnet.
The opus and fable model tiers are barred outright: the token-burn incident from the firstmate tryout (issue #100) must not be able to recur silently.

`firstmate/model-guard` is the deterministic check.
It scans the recipe's own configuration, the configuration applied into `$FM_HOME`, and live process command lines, and it exits non-zero on any opus or fable selection.
It reads command lines, not a running agent's interactive state, so the `captain` alias always passing `--model` is what closes the interactive-picker path (AC5).
It has direct bats coverage in `test/tooling/`.
