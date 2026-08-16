# Operational gotchas

Failure modes specific to working in this repo as an agent, not obvious from the code, that have already recurred at least once.

## `msb doctor` reporting `/dev/kvm` missing isn't proof the host lacks KVM

Claude Code's own Bash tool sandbox filters `/dev/kvm` out of what a sandboxed command sees, confirmed by rerunning the identical `msb doctor` with the sandbox disabled, where `/dev/kvm` appears and is read/write.
If a session hits "KVM device missing" while trying to launch an agent runtime, retry unsandboxed before concluding the host can't run `msb`.

## A session's own PAT usually can't push to `.github/workflows/`

GitHub gates any push touching `.github/workflows/` behind a `workflow` PAT scope, deliberately: a same-repo pull request runs the workflow file version on its own head branch with no approval gate, so a token able to both edit workflows and open PRs could get a modified workflow to run before any human reviews it.
This has already blocked an agent session's push twice.
The resolution both times: post the diff to the issue as a comment, then have a separate, more-privileged session or a human apply, commit, and push it.

## `npm run test:dev` has real, expected failures when run nested inside this repo's own workspace devcontainer

`test/dev/dotfiles-bootstrap.bats` and one `mise install` case in `test/dev/dev.bats` are unreliable specifically when run from inside this repo's own `.devcontainer` - not a regression.
`docker-outside-of-docker` drives the _host_ daemon, so a `docker run -v` a test constructs from a container-local tmp path doesn't resolve there, and spawning containers this way adds real overhead on top.
CI runs the suite unnested and is the authoritative signal; don't chase a failure in these cases when running the suite from inside this devcontainer without first reproducing it in CI or a non-nested shell.
