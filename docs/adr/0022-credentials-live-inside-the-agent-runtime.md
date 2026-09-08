# Credentials live inside the agent runtime

With the runtime long-lived (ADR-0021), both pieces of launch-time credential machinery lost their footing, and both are retired: the operator logs in to Claude Code and GitHub interactively inside the runtime, once per reset.

**`--persist-claude-auth` is retired because its job disappeared.**
The `agent-claude-creds` volume, the `~/.claude.json` symlink, and the flag pair existed only to carry a login across disposable launches; a long-lived runtime keeps `~/.claude` on its own disk.
Retiring it also removes a real credential sitting as a plainly readable file under `~/.microsandbox/volumes/` on the host.

**`--github-token` is retired despite its job remaining.**
Microsandbox's in-flight secret substitution kept the token out of the guest entirely - the guest held only a placeholder, substitution happened in transit, and `msb start` re-reads the host variable on every resume without ever storing the value (all verified by direct experiment in this session).
That is a genuine containment property, and this decision knowingly gives it up.
It lost to its own operational record:

- The injected token never reached git at all - every push failed until `gh auth setup-git` was run by hand, and that command silently no-ops when invoked from agent tooling (issue #127). A session that cannot push cannot deliver, per ADR-0015.
- The placeholder itself killed sessions when it appeared in request bodies, and keeping the mechanism meant migrating the launcher onto upstream's new, breaking per-secret flag surface (issue #114).
- The interactive TUI login never accepted the env-var token anyway, so attended captain sessions - the shape this stack is actually run in (ADR-0017) - always needed an in-guest login regardless.

## The trade, stated plainly

Egress is open (`--net public`, allowlisting rejected as unworkable for this workload) and the agent holds root, so in-flight substitution was the only barrier between a misbehaving session and exfiltration of the GitHub credential.
That barrier is now gone, accepted because sessions are attended, the credential should be a fine-grained PAT scoped to the managed repos with a short expiry (bounding the blast radius at what the runtime legitimately touches anyway), and the mechanism being given up was failing its primary purpose - delivering a usable push credential - in practice.
Revisit this decision the first time a session misuses a credential, or if unattended operation becomes the norm.

## Consequences

- Token expiry (issue #100, Finding F) now surfaces inside the runtime and is fixed by an in-guest re-login, not a relaunch.
- Issues #127 and #114 become moot for the launcher once the flag is removed.
- The launcher's generic `--secret` passthrough to `msb run` remains for other uses; only the GitHub-token specialisation and its implied `--on-secret-violation` default go.
