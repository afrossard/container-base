# The released launcher pins the agent image by digest

The tap's formula `sha256` covers the launcher's source but not the image it runs, because the launcher names the agent image by its `{version}-agent` tag, and a moved tag reaches every host unchecked ([homebrew-tap ADR 0001](https://github.com/afrossard/homebrew-tap/blob/main/docs/adr/0001-protect-the-tap-and-its-source-repos.md), issue #251).
The digest cannot live in the committed launcher, because release-please tags the release commit before the publish jobs build the image, so the tagged source can never name its own image's digest.

We decided that the release workflow, after the agent image is published, writes the image's multi-arch index digest into the launcher and uploads the host-side scripts as a release asset, and the tap's formula installs from that asset instead of the tag's source tarball.
The formula's `sha256` then covers the digest, so the launcher a host installs can only run the exact image that release built.
The committed launcher keeps naming the image by tag, so a launcher run from a checkout still works and the release PR guard still sees only version lines.

`msb` 0.7.14 was driven against a real multi-arch image before deciding: it runs both `name:tag@sha256:…` and `name@sha256:…`, fetches the manifest by digest from the registry, and fails on an unknown digest.
Whether it rehashes the fetched content locally was not tested.

## Considered options

- **A follow-up commit pinning the digest in the committed launcher:** rejected, because it lands in the next release, so each tagged launcher would pin the previous release's image.
- **The formula pins the digest and writes it into the launcher at install:** rejected, because it moves the image's trust anchor out of the release that built the image into a second Renovate-maintained value in the tap.
- **Signing or attesting the image and verifying it at launch:** rejected for now, because verifying needs `gh` or `cosign` on the host, beyond the `msb`-and-`git` host prerequisites.

## Consequences

- **The tap's formula and its Renovate config change** to track the release asset rather than the tag's source tarball, in `afrossard/homebrew-tap`.
- **A release exists briefly without its launcher asset**, between release-please creating it and the publish jobs finishing, so a formula bump that runs in that window fails until the asset lands.
- **The release workflow needs `contents: write` in the job that uploads the asset**, on top of the publish jobs' `packages: write`.
- **A replaced release asset cannot reach hosts**, because the formula's `sha256` no longer matches it, so the tag ruleset allowing `gh release upload --clobber` is no gap here.
