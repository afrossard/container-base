# container-base

Shared container base images, published to `ghcr.io/afrossard/container-base`.

Three kinds of image, tagged `{version}-{variant}`:

- **Dev image** (`1.4.2-dev`) - one image, every language toolchain, plus the dev layer: zsh, Homebrew, chezmoi, starship. What a devcontainer builds on.
- **Agent image** (`1.4.2-agent`) - the dev image plus its own docker daemon and an entrypoint that starts it, with no dev layer added. What a long-lived per-repo agent VM (the agent runtime) boots as its guest (ADR-0013, ADR-0014, ADR-0021).
- **Runtime base** (`1.4.2-base-prod`, `1.4.2-python-prod`) - minimal, one language runtime, no dev layer. What a deployable artifact builds on.

There is no `python-dev`. The dev image carries every language, so there is nothing to choose between.

Only a default Node is baked (ADR-0020): `uv` resolves Python and `mise` resolves everything else, from the version each project declares.

Pin a version and let Renovate bump it.

`launch-agent-runtime` owns the agent runtime's lifecycle: a bare launch attaches to the current repo's runtime, resumes it if stopped, and creates one only if none exists, never destroying anything (ADR-0021).
The launcher's one destruction path is `launch-agent-runtime --reset`: it removes the runtime and its paired docker volume after a confirmation prompt (`--force` skips it), so the next launch starts from nothing.
It is host-side tooling, a deliberate, narrow exception to this repo's image-only scope (ADR-0014).
`cleanup-agent-sessions` is the housekeeping counterpart, acting only on runtimes labelled for the current repo: a bare call lists them and removes nothing; `--name SESSION` removes one and its volume; `--all` removes the stopped ones, and `--all --force` extends that to running ones.

Both ship through a personal Homebrew tap (`brew install afrossard/tap/agent-runtime`), so any machine gets a working launcher and cleanup script with one command - no container-base checkout, no PATH edits.
`brew upgrade` delivers new releases, each carrying its release-please-stamped agent image pin.
Run either from inside any repo's checkout to create or resume a runtime anchored to that repo.

## Reaching a LAN service from the agent runtime

The runtime reaches the public internet and nothing on your local network (ADR-0013, issue #30).
To let it reach one service on your LAN, pass its URL when the runtime is created:

```sh
launch-agent-runtime --allow-url https://homeassistant.home.example
launch-agent-runtime --allow-url http://192.168.1.20:8080 --allow-url https://nas.lan
```

- The whole host and port is reachable, not just the URL's path; the port is the URL's own, else 80 or 443 for `http` or `https`.
- One port per host: a second `--allow-url` resolving to an address already allowed is refused.
- LAN addresses only (10/8, 172.16/12, 192.168/16, and 100.64/10 for Tailscale): public addresses are already reachable, and loopback or link-local ones are refused.
- The host is resolved on your machine, so names your router or split-horizon DNS provides work, and the name resolves inside the runtime too.
- The exception is fixed when the runtime is created: to add, change, or follow a moved address, run `launch-agent-runtime --reset` and launch again with the new set.
  Passing `--allow-url` to an existing runtime warns instead.
- It is chosen on the host by whoever launches, never read from the checkout the agent edits.

ADR-0025 records why the forwarded msb rule has the shape it does.

## Upgrading in place

Only the Debian release, the default Node major and the devcontainer features the images build with are pinned; every other tool floats, and an image carries whatever was newest when it was built (ADR-0024).
`/etc/mise/config.toml` declares all of it, so one command brings a running environment current:

| Where                                | Command                                             | What it does                                                                                |
| ------------------------------------ | --------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| inside a devcontainer or runtime     | `mise bootstrap --upgrade`                          | every floating mise tool, every declared apt package, then a full Debian upgrade            |
| same, for formulae installed by hand | `brew upgrade`                                      | your own Homebrew formulae; the image declares none                                         |
| host, only to take a newer image     | `brew upgrade`, then `launch-agent-runtime --reset` | the launcher's image pin; optional, since the runtime's tools already stay current in place |

Nothing upgrades in place unattended: attaching to or starting an environment never runs the upgrade.

## Host prerequisites

The tap-installed launcher runs on your own machine, alongside the tools it needs there already:

- **Homebrew (`brew`)** - already part of the machine bootstrap; taps the formula that installs the launcher and cleanup script.
- **[microsandbox](https://docs.microsandbox.dev/) (`msb`)** - the hypervisor the agent runtime runs on.
- **git** - the session's clone URL and the repo name both come from your `origin` remote.

Nothing else.
Both scripts check for `msb` and `git`, stopping with one message if either is missing, so `--help` still works on a machine with neither.
Everything else the images need ships inside them, and `npm ci` supplies the test tooling.

See [`GLOSSARY.md`](./GLOSSARY.md) for the glossary and [`docs/adr/`](./docs/adr/) for why it's shaped this way.
