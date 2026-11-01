#!/usr/bin/env bats
#
# Runs against the real image built from images/dev/ (issue #1: assert
# through the door a user walks through).
#
# Expects IMAGE to name an already-built image (set by `npm run test:dev`).

setup_file() {
  : "${IMAGE:?set IMAGE to the image tag built by \`npm run build:dev\`}"
}

@test "vscode is uid 1000, gid 1000, login shell /bin/zsh" {
  run docker run --rm "$IMAGE" getent passwd vscode
  [ "$status" -eq 0 ]
  IFS=: read -r _ _ uid gid _ _ shell <<<"$output"
  [ "$uid" = "1000" ]
  [ "$gid" = "1000" ]
  [ "$shell" = "/bin/zsh" ]
}

@test "the default user, with no --user given, is uid 1000" {
  run docker run --rm "$IMAGE" id -u
  [ "$status" -eq 0 ]
  [ "$output" = "1000" ]
}

@test "vscode has passwordless sudo" {
  run docker run --rm --user vscode "$IMAGE" sudo -n whoami
  [ "$status" -eq 0 ]
  [ "$output" = "root" ]
}

@test "LANG is set" {
  run docker run --rm "$IMAGE" sh -c 'printenv LANG'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

# Chezmoi never runs at build time (issue #6), so its source directory
# must be absent; installOhMyZsh/installOhMyZshConfig keep oh-my-zsh's
# installer from writing ~/.zshrc and ~/.oh-my-zsh.
@test "\$HOME carries no chezmoi-managed file or oh-my-zsh config" {
  run docker run --rm "$IMAGE" sh -c '[ ! -e /home/vscode/.zshrc ] && [ ! -e /home/vscode/.oh-my-zsh ] && [ ! -e /home/vscode/.local/share/chezmoi ]'
  [ "$status" -eq 0 ]
}

# ADR-0024: every floating mise tool, and the Node pin, resolves through the
# shims on the image's own PATH - under plain sh and bash too, not only in
# shells that read /etc/zsh/zshenv or /etc/profile.d.
@test "the floating mise tools and node resolve to mise shims under sh and bash" {
  shims=/usr/local/share/mise/shims
  expected="$shims/uv
$shims/uvx
$shims/gh
$shims/chezmoi
$shims/starship
$shims/dive
$shims/node"
  for shell in sh bash; do
    # One name per `command -v`: dash's reports only its first argument.
    run docker run --rm "$IMAGE" "$shell" -c \
      'for tool in uv uvx gh chezmoi starship dive node; do command -v "$tool"; done'
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
  done
}

# "latest" must resolve to the baked version, not to whatever is newest
# upstream, or a shim would fail offline - or the day a new release ships.
@test "the floating mise tools and node run with no network" {
  run docker run --rm --network none "$IMAGE" sh -c \
    'cd /tmp && uv --version && gh --version && chezmoi --version && starship --version && dive --version && node --version'
  [ "$status" -eq 0 ]
}

@test "mise is installed via apt, at /usr/bin/mise" {
  run docker run --rm "$IMAGE" sh -c 'dpkg -s mise >/dev/null && command -v mise'
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/bin/mise" ]
}

# ADR-0024: the shipped config declares every floating apt package and
# mise tool, and the build installs them all from it. --missing still lists
# every entry and carries the verdict in the exit code alone.
@test "mise bootstrap reports nothing the shipped config declares as missing" {
  run docker run --rm "$IMAGE" sh -c 'cd /tmp && mise bootstrap status --missing'
  [ "$status" -eq 0 ]
  [[ "$output" == *"apt:claude-code"* ]]
  [[ "$output" == *"uv@latest"* ]]
}

@test "mise's data directory is vscode-owned" {
  run docker run --rm "$IMAGE" stat -c '%U:%G' /usr/local/share/mise
  [ "$status" -eq 0 ]
  [ "$output" = "vscode:vscode" ]
}

@test "the mise shims directory is prepended to sudo's secure_path" {
  # /etc/sudoers is 0440 root:root, so --user root is needed here.
  run docker run --rm --user root "$IMAGE" grep secure_path /etc/sudoers
  [ "$status" -eq 0 ]
  [[ "$output" == *'secure_path="/usr/local/share/mise/shims:'* ]]
}

# ADR-0020's pin ships as mise's system config, a lower layer than global,
# so MISE_GLOBAL_CONFIG_FILE stays unset.
@test "MISE_GLOBAL_CONFIG_FILE is not set" {
  run docker run --rm "$IMAGE" sh -c 'printenv MISE_GLOBAL_CONFIG_FILE'
  [ "$status" -ne 0 ]
}

# ADR-0020: the dev image bakes a default Node so tooling running before
# any project pin has a runtime. A concrete major, not the `lts` alias, so
# Renovate's mise manager can bump it (issue #102).
@test "the dev image carries a mise system config pinning a concrete Node major" {
  run docker run --rm "$IMAGE" cat /etc/mise/config.toml
  [ "$status" -eq 0 ]
  [[ "$output" =~ node[[:space:]]*=[[:space:]]*\"[0-9]+\" ]]
}

@test "a bare node resolves outside any project, to the baked default" {
  run docker run --rm --user vscode "$IMAGE" zsh -lc 'cd /tmp && node --version'
  [ "$status" -eq 0 ]
  [[ "$output" == v* ]]
}

# One test, not three: the assertions share one `mise install` (a real Node
# download). The project pins a major distinct from the baked default, so
# IN_PROJECT proves the project config wins and OUTSIDE_PROJECT proves the
# baked pin resolves.
#
# Unreliable when run inside this repo's own devcontainer - see
# docs/agents/gotchas.md.
@test "a project pin overrides the baked default, through shims and under sudo" {
  run docker run --rm --user vscode "$IMAGE" zsh -lc '
    set -e
    mkdir -p /tmp/proj && cd /tmp/proj
    printf "[tools]\nnode = \"22\"\n" > .mise.toml
    mise trust >/dev/null
    mise install >/dev/null 2>&1
    echo "IN_PROJECT=$(node --version)"
    echo "UNDER_SUDO=$(sudo node --version)"
    cd /tmp
    echo "OUTSIDE_PROJECT=$(node --version)"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"IN_PROJECT=v22"* ]]
  [[ "$output" == *"UNDER_SUDO=v22"* ]]
  [[ "$output" == *"OUTSIDE_PROJECT=v"* ]]
  [[ "$output" != *"OUTSIDE_PROJECT=v22"* ]]
}

# Node 26's upstream Linux binaries link libatomic.so.1, which trixie-slim
# doesn't ship (issue #223). Pinned at 26 rather than the baked default so
# a project on a newer Node than the image bakes is still covered.
@test "a project pinning Node 26 installs and runs it" {
  run docker run --rm --user vscode "$IMAGE" zsh -lc '
    set -e
    mkdir -p /tmp/proj && cd /tmp/proj
    printf "[tools]\nnode = \"26\"\n" > .mise.toml
    mise trust >/dev/null
    mise install 2>&1
    node --version
  '
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == v26.* ]]
}

# ADR-0008's chown makes the shared data directory vscode-owned, so a
# global npm install under the baked Node writes there with no sudo.
@test "a global npm install under the baked Node needs no sudo and lands in the shared data dir" {
  run docker run --rm --user vscode "$IMAGE" zsh -lc '
    set -e
    cd /tmp
    root=$(npm root -g)
    case "$root" in
      /usr/local/share/mise/*) ;;
      *) echo "npm root -g outside the shared data dir: $root"; exit 1 ;;
    esac
    npm install -g cowsay >/dev/null 2>&1
    test -x "$(npm prefix -g)/bin/cowsay"
  '
  [ "$status" -eq 0 ]
}

# ADR-0024's one upgrade command, as an operator runs it: as vscode, with no
# TTY. The data directory must stay vscode-owned after it (ADR-0008).
@test "mise bootstrap --upgrade runs as vscode with no TTY and keeps the data dir vscode-owned" {
  run docker run --rm --user vscode "$IMAGE" sh -c '
    set -e
    cd /tmp
    mise bootstrap --upgrade --yes >/dev/null 2>&1
    stat -c "%U:%G" /usr/local/share/mise /usr/local/share/mise/installs
  '
  [ "$status" -eq 0 ]
  [ "$output" = "vscode:vscode
vscode:vscode" ]
}

@test "uv can resolve and fetch a Python interpreter" {
  run docker run --rm --user vscode "$IMAGE" zsh -lc 'uv python install 3.13'
  [ "$status" -eq 0 ]
}

# Issues #210 and #215: neither mise nor the floating mise tools ship
# completion files, so the shipped config's bootstrap task generates them.
# Same compinit check as brew's below.
@test "compinit registers the bootstrap task's generated completions in a non-interactive zsh" {
  run docker run --rm --user vscode "$IMAGE" zsh -c \
    'autoload -Uz compinit && compinit -u -D && print -r -- "${_comps[mise]} ${_comps[uv]} ${_comps[uvx]} ${_comps[gh]} ${_comps[chezmoi]} ${_comps[starship]} ${_comps[dive]}"'
  [ "$status" -eq 0 ]
  [ "$output" = "_mise _uv _uvx _gh _chezmoi _starship _dive" ]
}

@test "brew resolves in a non-interactive login shell" {
  run docker run --rm --user vscode "$IMAGE" zsh -lc 'command -v brew'
  [ "$status" -eq 0 ]
  [ "$output" = "/home/linuxbrew/.linuxbrew/bin/brew" ]
}

# Issue #210: dotfiles' ~/.zshrc only runs compinit, so completions must
# already be on fpath. -D keeps compinit from writing a dump into $HOME.
@test "compinit registers brew's completion in a non-interactive zsh" {
  run docker run --rm --user vscode "$IMAGE" zsh -c \
    'autoload -Uz compinit && compinit -u -D && print -r -- "${_comps[brew]}"'
  [ "$status" -eq 0 ]
  [ "$output" = "_brew" ]
}

# ADR-0024: Homebrew is kept for the operator's own formulae; the image
# declares none.
@test "Homebrew carries no formula" {
  run docker run --rm --user vscode "$IMAGE" zsh -lc 'brew list --formula'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the Homebrew prefix is vscode-owned" {
  run docker run --rm "$IMAGE" stat -c '%U:%G' /home/linuxbrew/.linuxbrew
  [ "$status" -eq 0 ]
  [ "$output" = "vscode:vscode" ]
}

# Scoped to shell configuration, not /home/linuxbrew: the Cellar's bundled
# docs mention "starship init" harmlessly. What matters is that no shell
# config file evaluates it (ADR-0010).
@test "no starship init line is written into any shell configuration" {
  run docker run --rm "$IMAGE" sh -c 'grep -rl "starship init" /etc/zsh /etc/profile.d /home/vscode 2>/dev/null'
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "\$HOME carries no Homebrew or starship file" {
  run docker run --rm "$IMAGE" sh -c '[ ! -e /home/vscode/.cache/Homebrew ] && [ ! -e /home/vscode/.config/starship.toml ]'
  [ "$status" -eq 0 ]
}

# Homebrew and starship wiring only appends to /etc/zsh/zshenv; /etc/zsh/zshrc
# must carry none of it.
@test "/etc/zsh/zshrc carries no Homebrew or starship configuration" {
  run docker run --rm "$IMAGE" sh -c 'grep -iE "brew|starship" /etc/zsh/zshrc'
  [ "$status" -ne 0 ]
}

@test "gh, vim, bubblewrap and claude all resolve on PATH" {
  run docker run --rm "$IMAGE" sh -c \
    'command -v gh && command -v vim && command -v bwrap && command -v claude'
  [ "$status" -eq 0 ]
}

# docker-prune-credsstore (issue #205) needs jq, which the image gets from
# the common-utils feature (ADR-0005) rather than its own apt-get.
@test "jq resolves on PATH" {
  run docker run --rm "$IMAGE" sh -c 'command -v jq'
  [ "$status" -eq 0 ]
}

@test "vim and bubblewrap are installed via apt, not hand-rolled" {
  run docker run --rm "$IMAGE" sh -c \
    'dpkg -s vim >/dev/null && dpkg -s bubblewrap >/dev/null'
  [ "$status" -eq 0 ]
}

# ADR-0024: Debian's gh lags far behind upstream, so gh is a mise tool.
@test "gh is not installed via apt" {
  run docker run --rm "$IMAGE" dpkg -s gh
  [ "$status" -ne 0 ]
}

# The floating mise tools resolve in a login shell too, where Debian's
# /etc/profile has rewritten PATH and /etc/zsh/zshenv puts the shims back.
@test "the floating mise tools resolve to mise shims in a non-interactive login shell" {
  shims=/usr/local/share/mise/shims
  run docker run --rm --user vscode "$IMAGE" zsh -lc 'command -v uv gh chezmoi starship dive'
  [ "$status" -eq 0 ]
  [ "$output" = "$shims/uv
$shims/gh
$shims/chezmoi
$shims/starship
$shims/dive" ]
}

# Issue #231: the shipped mise config declares Anthropic's repository, and
# mise writes its source.
@test "Claude Code is installed from the signed apt repository, stable channel" {
  run docker run --rm "$IMAGE" sh -c 'dpkg -s claude-code >/dev/null && cat /etc/apt/sources.list.d/mise-claude-code.sources'
  [ "$status" -eq 0 ]
  [[ "$output" == *"URIs: https://downloads.claude.ai/claude-code/apt/stable"* ]]
  [[ "$output" == *"Suites: stable"* ]]
  [[ "$output" == *"Components: main"* ]]
}

# The key is embedded in the source's Signed-By, so it is trusted for that
# repository only. deb822 indents a multi-line field by one space and writes
# its blank lines as " .". gpg comes from the common-utils feature
# (ADR-0005), not the Containerfile.
@test "Claude Code's apt key, embedded in its source, matches Anthropic's published fingerprint" {
  run docker run --rm "$IMAGE" sh -c "
    sed -n '/^Signed-By:/,/END PGP PUBLIC KEY BLOCK/{/^ /p}' /etc/apt/sources.list.d/mise-claude-code.sources \
      | sed 's/^ //; s/^\.\$//' \
      | gpg --show-keys --with-colons --with-fingerprint 2>/dev/null \
      | awk -F: '\$1 == \"fpr\" { print \$10; exit }'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE" ]
}

# Issue #231: ADR-0024's upgrade command rewrites the source, so it repairs a
# broken or rotated key in place, as vscode with no TTY.
@test "mise bootstrap --upgrade restores a deleted Claude Code apt source" {
  run docker run --rm --user vscode "$IMAGE" sh -c '
    set -e
    cd /tmp
    sudo rm /etc/apt/sources.list.d/mise-claude-code.sources
    mise bootstrap --upgrade --yes >/dev/null 2>&1
    grep "^URIs:" /etc/apt/sources.list.d/mise-claude-code.sources
  '
  [ "$status" -eq 0 ]
  [ "$output" = "URIs: https://downloads.claude.ai/claude-code/apt/stable" ]
}

# Issue #231: two sources for the same repository with different Signed-By
# values make every `apt-get update` fail with "The list of sources could not
# be read".
@test "Anthropic's repository has exactly one apt source and no separate keyring" {
  run docker run --rm "$IMAGE" sh -c \
    'grep -rl downloads.claude.ai /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; [ ! -e /etc/apt/keyrings/claude-code.asc ]'
  [ "$status" -eq 0 ]
  [ "$output" = "/etc/apt/sources.list.d/mise-claude-code.sources" ]
}

@test "\$HOME carries no file from gh, gnupg, vim or claude" {
  run docker run --rm "$IMAGE" sh -c '
    [ ! -e /home/vscode/.config/gh ] &&
    [ ! -e /home/vscode/.gnupg ] &&
    [ ! -e /home/vscode/.vimrc ] &&
    [ ! -e /home/vscode/.viminfo ] &&
    [ ! -e /home/vscode/.claude ] &&
    [ ! -e /home/vscode/.claude.json ]
  '
  [ "$status" -eq 0 ]
}

# The build's `mise bootstrap` runs as root, and its tools write caches and
# state there - gh's telemetry device id among them - that no image should
# share across every container built from it.
@test "/root carries no cache or state from the build" {
  run docker run --rm --user root "$IMAGE" sh -c '[ ! -e /root/.cache ] && [ ! -e /root/.local ]'
  [ "$status" -eq 0 ]
}

# Issue #7's exclusion list: single-repo tools that stay with their repo.
@test "none of the explicitly excluded single-repo tools are present" {
  run docker run --rm "$IMAGE" sh -c '
    for tool in kubectl k9s helm flux talosctl talhelper sops age yq gptfdisk xorriso gemini-cli; do
      if command -v "$tool" >/dev/null 2>&1; then
        echo "unexpectedly present: $tool"
      fi
    done
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
