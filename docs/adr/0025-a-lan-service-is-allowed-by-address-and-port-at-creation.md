# A LAN service is allowed by address and port, at creation

The agent runtime launches with `--net public`, which denies every private range (ADR-0013, issue #30).
Research 0016 framed the policy as "local / private-network access denied unless explicitly allowed", and issue #234 built the "explicitly allowed" half: a downstream repo sometimes needs one service on the operator's LAN, such as a NAS or Home Assistant.

**Decision: `launch-agent-runtime --allow-url URL` resolves the URL's host on the host machine, and for each address it gets, forwards one msb rule group allowing exactly that address and TCP port; the group is fixed when the runtime is created.**

For `https://homeassistant.home.example` resolving to `192.168.10.231`, the launcher forwards, after `--net public`:

```
--net-rule "deny@192.168.10.231:tcp:1-442,deny@192.168.10.231:tcp:444-65535,deny@192.168.10.231:udp,allow@192.168.10.231"
```

The shape is not the obvious `allow@<host>:tcp:443`, and every part of it was measured against msb 0.7.13 from a real guest on issue #234, because msb's help text is not sufficient evidence (research 0022):

- **An explicit IP allow wins over `--net public`.** `allow@192.168.50.1:tcp:443` reached that port while the rest of the private ranges stayed blocked.
- **A hostname rule cannot carry a LAN name.** DNS rebind protection rewrites a private answer to NXDOMAIN even when the hostname is explicitly allowed, so the name never resolves. msb's docs name the one exception: "the first matching explicit, address-only egress rule permits the returned address"; port-scoped rules do not count.
- **Strict mode fails HTTPS allowed only by a hostname.** `--net-strict`, on by default, makes "non-intercepted HTTPS fail closed when only a hostname rule allows it". Making a hostname rule work took both `--no-dns-rebind-protection` and `--net-strict=false`, and both apply to the whole sandbox, not just the one service.
- **So the group ends in an address-only `allow@IP`, which keeps the name resolvable**, and port-range denies ahead of it narrow it back to the one port, since the first matching rule wins.
- **The denies must be port ranges.** A protocol-wide `deny@IP:tcp` blocks the same ports, but it counts as an address deny and the name stops resolving again.
- **Every address in a DNS answer needs a group.** A name with five private answers, only one of them allowed, did not resolve at all; with all five allowed, it did. The launcher emits a group for each address the host resolves.
- **An IP alone is not enough over HTTPS.** Allowing only the IP leaves the service reachable by address, but its certificate names the hostname, so clients fail verification; resolving the name inside the guest is what makes the exception usable.

## Considered options

- **Forward a hostname rule as given (`allow@nas.lan:tcp:8080`).** What issue #234 first specified. Rejected: the name never resolves, for the rebind and strict-mode reasons above.
- **Hostname rules plus `--no-dns-rebind-protection` and `--net-strict=false`.** Works, but weakens rebind and SNI-spoofing protection for every hostname the agent touches, to serve one LAN service. The issue already called the sandbox-wide flag a last resort.
- **Accept only a literal `IP:PORT`.** The issue's fallback. Rejected once the address-only exemption was found: it leaves the name unresolvable and HTTPS failing certificate checks.
- **Several ports per host, merged into one group.** Works (measured), but needs gap arithmetic across URLs for a need nobody has yet. A second URL landing on an address that is already allowed is refused instead.
- **Allow a whole host (`allow@IP`, every port).** Works and is simpler, but opens SSH, admin UIs, and every UDP service on that machine. Not built; nothing needs it.
- **Accept any address the host resolves.** Rejected: `--net public` already allows public addresses, and a group for one would narrow it to a single port, silently breaking the rest of that address. Only RFC 1918 and carrier-grade NAT (`100.64.0.0/10`, where Tailscale lives) are accepted; loopback and link-local (cloud metadata) are never a LAN service.
- **Read the exceptions from a config file in the downstream checkout.** Rejected: the agent edits that checkout and could propose widening its own egress in a PR. Exceptions are chosen on the host by whoever launches, like `--secret`.

## Consequences

- **The whole address and port is reachable, not the URL's path,** because msb filters on address, protocol, and port. Anything else served on that address and port, under any name, is reachable too.
- **The address is resolved on the host at creation and does not follow later DNS changes.** A service that moves needs `--reset`. Host resolution means router-provided and split-horizon names work as the operator's own machine sees them.
- **The policy is fixed at creation (ADR-0021) and msb cannot change an existing sandbox's rules.** Passing `--allow-url` to an existing runtime warns and points at `--reset` instead of silently dropping it.
- **ICMP to an allowed address is not denied** by the group; only TCP and UDP are narrowed. This was not measured.
- **The shape depends on msb behaviour that is documented but subtle,** notably which denies re-arm rebind protection. A msb upgrade that changes it shows up as the name failing to resolve in the guest, not as a widened policy.
