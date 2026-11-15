# The dev image ships the shared devcontainer lifecycle

Every consumer devcontainer carried the same `post-create` (`mise trust && mise install`), the same `post-start` (`git config --global --add safe.directory "$PWD"` and `dotfiles-bootstrap`), and the same `remoteEnv.DOTFILES_REPO`, `waitFor` and VS Code extension keys, so a fix to any of them had to land in every repo (issue #213).
We decided that `images/dev/devcontainer.json` declares them, so `devcontainer build` writes them into the image's `devcontainer.metadata` label and the devcontainer CLI merges them into each consumer's config, the way `remoteUser: vscode` already reached consumers.
A consumer keeps only what is its own: its name, its build, its features, and any extra lifecycle command, which runs after the image's rather than replacing it.

**Supersedes in part ADR-0007**: its "every consumer calls the script" no longer holds for a devcontainer, which now gets the call from the image.
ADR-0007's reasons for leaving the `dotfiles.repository` setting off and declaring no `ENTRYPOINT` both stand.

## Considered options

- **A shared script each consumer calls from its own lifecycle commands:** rejected, because each consumer would still repeat the keys that call it, and `waitFor` and `remoteEnv` can't be shipped as a script.
- **Baking `docker-outside-of-docker` into the dev image too:** rejected, because image metadata can't add a feature to a consumer, and the feature would clash with the agent image's own dockerd.

## Consequences

- **Opening a dev-image devcontainer now runs `dotfiles-bootstrap` without the consumer asking for it**, so ADR-0007's "nothing in the estate starts a container that silently reaches GitHub" no longer holds as written.
  The network fetch still happens only where the operator asked for it, because the bootstrap is a no-op unless `DOTFILES_REPO` is set on the host.
- **A consumer that still carries its own scripts runs each step twice** until it drops them.
  Every step is idempotent, so this costs time but breaks nothing.
- **`docker-outside-of-docker` and `docker-prune-credsstore` stay per consumer**, the second because it only matters alongside the first.
- **The agent image inherits the label**, because it builds FROM the dev image, but nothing reads it there: msb ignores devcontainer metadata, and `agent-bringup` runs the bootstrap itself (ADR-0016).
- **A container no platform launches**, such as a compose service started with `docker compose up`, reads no metadata either, so it still calls `dotfiles-bootstrap` from its own entrypoint as ADR-0007 describes.
