# The nested docker daemon picks its iptables backend at boot

The agent image's nested dockerd stopped starting on every CI run once `ubuntu-latest` moved from ubuntu-24.04 to ubuntu-26.04 (issue #222).
dockerd died creating its NAT chain: `iptables v1.8.11 (legacy): can't initialize iptables table 'nat': Table does not exist`.
The `docker-in-docker` feature at major 2 chose the iptables alternative at image build time, and chose `iptables-legacy` because legacy worked on the build host.
Legacy iptables only works when the host kernel already has the `ip_tables` module loaded, and a guest cannot load it itself.
The ubuntu-24.04 runner host had `ip_tables` loaded and the ubuntu-26.04 runner host does not, on the very same `7.0.0-1017-azure` kernel, because its own Docker and iptables run purely on nf_tables.
So the image baked a choice that depends on the kernel it would later run on, which the build cannot know.

**Decision: the nested docker daemon's iptables backend is chosen when the runtime boots, against the kernel it actually runs on.**
We get this by moving the `docker-in-docker` feature from major 2 to major 4, whose `iptablesSwitchAtRuntime` option (default `true`) makes `docker-init.sh` pick legacy only when `ip_tables` is loaded and `iptables-nft` otherwise.
This keeps ADR-0014's choice of the community feature as the owner of iptables alternative selection; only its version moves.

**The move also relocates image storage, and the launcher's disk-backed volume follows it to `/var/lib/containerd`.**
From major 3 the feature runs its own containerd rooted at `/var/lib/containerd` instead of the dockerd-managed one under `/var/lib/docker`, so image layers and snapshots now live there.
That is the directory whose overlayfs mounts cannot nest on the guest's overlayfs root (`docs/research/0022`), so it, not `/var/lib/docker`, gets the runtime's one disk-backed volume.
`/var/lib/docker` stays on the guest root, holding dockerd's own metadata, logs, and named volumes; none of it is overlay-mounted.

## Considered options

- **Pin the CI runner to `ubuntu-24.04`.** Rejected: it would hide the bug rather than fix it, since the image would still fail on any host without `ip_tables` loaded, an msb guest kernel included, and the label would expire with the runner image.
- **Force `iptables-nft` in `images/agent/Containerfile`.** Rejected: it hand-rolls a choice the feature already makes, and it is wrong for a kernel that has legacy tables but no nf_tables.
- **Set dockerd's `firewall-backend` to `nftables`.** Verified to work on both runner images, but it changes how dockerd programs its rules, not just which iptables binary it calls, and it would be config this repo owns instead of the feature.
- **Two disk-backed volumes, one each at `/var/lib/docker` and `/var/lib/containerd`,** as the feature's own `devcontainer up` metadata declares. Rejected: only the overlay-mounted directory needs a filesystem of its own, and a second volume per runtime splits one size budget in two for no benefit.
- **Point containerd's root back under `/var/lib/docker`.** Rejected: it overrides a layout the feature owns and may move again.

## Consequences

- **An existing agent runtime must be reset to use an image built on this change.** Its disk-backed volume is mounted at `/var/lib/docker`, fixed when it was created, so a new image would put its image layers on the guest's overlayfs root and every real container run or build would fail. A reset recreates the runtime with the volume at the new path (ADR-0021).
- **The other feature changes between major 2 and 4 come along with the move.** Major 3 also disables containerd's erofs snapshotter, and major 4 defaults Docker Compose to `latest`.
- **Verified on both runner images by differential probe (#222):** with the published `4.0.4-agent` image, nested dockerd starts on ubuntu-24.04 and fails on ubuntu-26.04; switching the guest to `iptables-nft`, setting dockerd's `firewall-backend` to `nftables`, or loading `iptable_nat` on the host each turns ubuntu-26.04 green. With feature major 4 and the one volume at `/var/lib/containerd`, the full `test/agent` suite passes on ubuntu-26.04. The msb live test was not run (CI has no msb).
- **The feature pin was not Renovate-tracked in practice,** contradicting ADR-0014's wording: Renovate's `devcontainer` manager only scans `.devcontainer/devcontainer.json` by default, so `images/*/devcontainer.json` never appeared in its detected dependencies and the 2-to-4 move was never proposed.
