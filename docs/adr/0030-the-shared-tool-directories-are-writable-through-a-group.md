# The shared tool directories are writable through a group

On a Linux host whose user isn't uid 1000, `devcontainer up` changes `vscode`'s uid and its own group's gid to match, so that the bind-mounted workspace is writable (`updateRemoteUserUID`, on by default).
It then re-owns only `/home/vscode` (`scripts/updateUID.Dockerfile` in the devcontainer CLI).
mise's data directory (ADR-0008) and the Homebrew prefix live outside `$HOME` and were owned by uid 1000, so the renumbered `vscode` lost write access to both, and `mise install` failed with `Permission denied` (found by issue #213's end-to-end test, on a uid-1001 CI runner).

We decided that each shared tool directory belongs to a dedicated group, `mise` and `linuxbrew`, group-writable with the setgid bit on every directory, and that `vscode` joins both groups.
The uid change rewrites neither group nor the member list, so `vscode` keeps write access whatever uid it gets.
This is the pattern the official devcontainer features already use for their shared directories: the `node` feature's `nvm` group, the `python` feature's `python` and `pipx` groups.
The owner stays uid 1000, so a uid-1000 host sees no change.

The Containerfile creates the groups and sets the permissions in the same step that fills each directory, because changing them in a later layer would store a second copy of every file.
`vscode` joins them through the common-utils feature's `addGroups` option, because `vscode` doesn't exist until that feature runs, after the Containerfile, and `groupadd` refuses a member that doesn't exist yet.

## Considered options

- **Turning `updateRemoteUserUID` off in each consumer:** rejected, because the bind-mounted workspace then belongs to a different uid than `vscode`, the problem the setting exists to fix.
- **Re-owning the directories at container start:** rejected, because a recursive `chown` of every installed toolchain on each create is slow and needs `sudo` in a lifecycle command.
- **Group-writable by `vscode`'s own group:** rejected, because the uid change renumbers that group too.

## Consequences

- **Files `vscode` creates later aren't group-writable**, because the image sets no `umask 0002`. That is harmless while `vscode` is the only user of a container, since it owns what it creates.
- **The agent image inherits the groups and the membership**, since it builds FROM the dev image, so `runuser` to `vscode` there is unaffected.
