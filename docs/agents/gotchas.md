# Operational gotchas

Failure modes specific to working in this repo as an agent, not obvious from the code, that have already recurred at least once.

## `msb doctor` reporting `/dev/kvm` missing isn't proof the host lacks KVM

Claude Code's Bash sandbox filters `/dev/kvm` out of what a sandboxed command sees; rerunning `msb doctor` unsandboxed shows it present and read/write.
Retry unsandboxed before concluding the host can't run `msb`.

## A session's own PAT usually can't push to `.github/workflows/`

GitHub gates any push touching `.github/workflows/` behind a `workflow` PAT scope, which a session's own PAT lacks.
This has blocked an agent session's push twice.
The resolution both times: post the diff to the issue, then have a more-privileged session or a human apply, commit, and push it.

## `npm run test:dev` has real, expected failures when run nested inside this repo's own workspace devcontainer

`test/dev/dotfiles-bootstrap.bats` and one `mise install` case in `test/dev/dev.bats` are unreliable when run from inside this repo's own `.devcontainer` - not a regression.
`docker-outside-of-docker` drives the _host_ daemon, so a `docker run -v` from a container-local tmp path doesn't resolve there.
CI runs the suite unnested and is the authoritative signal; reproduce a failure in CI or a non-nested shell before chasing it.
