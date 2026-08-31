#!/usr/bin/env bats
#
# Runs against the real image built from images/dev/, not against the
# Containerfile or devcontainer.json source. See issue #1's "Test assertions"
# section: assert through the door a user walks through.
#
# Expects IMAGE to name an already-built image (set by `npm run test:dev`,
# which passes the same tag `npm run build:dev` built).

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

# Issue #1's literal spec text: "$HOME contains no chezmoi-managed file
# after build". Chezmoi never runs at build time (issue #6), so its source
# directory must be absent; installOhMyZsh/installOhMyZshConfig in
# devcontainer.json additionally prevent oh-my-zsh's installer writing
# ~/.zshrc and ~/.oh-my-zsh if either flips on.
@test "\$HOME carries no chezmoi-managed file or oh-my-zsh config" {
  run docker run --rm "$IMAGE" sh -c '[ ! -e /home/vscode/.zshrc ] && [ ! -e /home/vscode/.oh-my-zsh ] && [ ! -e /home/vscode/.local/share/chezmoi ]'
  [ "$status" -eq 0 ]
}

@test "uv is installed to a system path, not \$HOME" {
  run docker run --rm "$IMAGE" sh -c 'command -v uv && command -v uvx'
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/bin/uv
/usr/bin/uvx" ]
}

@test "mise is installed via apt, at /usr/bin/mise" {
  run docker run --rm "$IMAGE" sh -c 'dpkg -s mise >/dev/null && command -v mise'
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/bin/mise" ]
}

@test "mise's data directory is vscode-owned" {
  run docker run --rm "$IMAGE" stat -c '%U:%G' /usr/local/share/mise
  [ "$status" -eq 0 ]
  [ "$output" = "vscode:vscode" ]
}

@test "the mise shims directory is prepended to sudo's secure_path" {
  # /etc/sudoers is 0440 root:root (issue #17 made vscode the default user,
  # so root must be requested explicitly here, unlike the plain stat check
  # above).
  run docker run --rm --user root "$IMAGE" grep secure_path /etc/sudoers
  [ "$status" -eq 0 ]
  [[ "$output" == *'secure_path="/usr/local/share/mise/shims:'* ]]
}

# MISE_GLOBAL_CONFIG_FILE stays unset even with ADR-0020's baked default:
# that pin ships as mise's *system* config (/etc/mise/config.toml), a
# distinct and lower layer, not the global one.
@test "MISE_GLOBAL_CONFIG_FILE is not set" {
  run docker run --rm "$IMAGE" sh -c 'printenv MISE_GLOBAL_CONFIG_FILE'
  [ "$status" -ne 0 ]
}

# ADR-0020: the dev image bakes a default Node so tooling that runs before
# any project pin exists (npm-global helpers, hooks, installers invoked from
# unpinned directories) has a runtime, and no fresh guest re-downloads it.
# The pin ships as mise's system config, the layer a project pin overrides.
# It is a concrete Node major, not the `lts` alias, so Renovate's mise
# manager can bump it on the Node LTS schedule (issue #102).
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

# One test, not three: the three assertions share a single `mise install`,
# which downloads a real Node build. Splitting them would triple that
# download for no gain (ADR-0008 measures the same three outcomes together).
# The project pins a major distinct from the baked default, so IN_PROJECT
# genuinely proves the project config layers over /etc/mise/config.toml and
# wins; OUTSIDE_PROJECT proves the baked system pin resolves rather than the
# pre-ADR-0020 "No version is set for shim: node".
#
# Unreliable specifically when run from inside this repo's own workspace
# devcontainer, not a regression - see docs/agents/gotchas.md.
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

# ADR-0008's chown makes the shared data directory vscode-owned, so a global
# npm install under the baked Node writes there with no sudo. (npm's own
# ~/.npm cache still lands in $HOME at runtime, harmless, same as mise's own
# ~/.cache/mise - ADR-0008.)
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

@test "uv can resolve and fetch a Python interpreter" {
  run docker run --rm --user vscode "$IMAGE" zsh -lc 'uv python install 3.13'
  [ "$status" -eq 0 ]
}

@test "brew resolves in a non-interactive login shell" {
  run docker run --rm --user vscode "$IMAGE" zsh -lc 'command -v brew'
  [ "$status" -eq 0 ]
  [ "$output" = "/home/linuxbrew/.linuxbrew/bin/brew" ]
}

@test "the Homebrew prefix is vscode-owned" {
  run docker run --rm "$IMAGE" stat -c '%U:%G' /home/linuxbrew/.linuxbrew
  [ "$status" -eq 0 ]
  [ "$output" = "vscode:vscode" ]
}

@test "starship resolves on PATH" {
  run docker run --rm --user vscode "$IMAGE" zsh -lc 'command -v starship'
  [ "$status" -eq 0 ]
  [ "$output" = "/home/linuxbrew/.linuxbrew/bin/starship" ]
}

# Scoped to actual shell configuration, not /home/linuxbrew: the Cellar's own
# bundled docs and completions mention "starship init" as documentation, and
# that's not this image's concern. What matters is that no shell
# configuration file evaluates it (ADR-0010).
@test "no starship init line is written into any shell configuration" {
  run docker run --rm "$IMAGE" sh -c 'grep -rl "starship init" /etc/zsh /etc/profile.d /home/vscode 2>/dev/null'
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "\$HOME carries no Homebrew or starship file" {
  run docker run --rm "$IMAGE" sh -c '[ ! -e /home/vscode/.cache/Homebrew ] && [ ! -e /home/vscode/.config/starship.toml ]'
  [ "$status" -eq 0 ]
}

# Homebrew and starship wiring only ever appends to /etc/zsh/zshenv (above);
# this asserts /etc/zsh/zshrc carries none of it, i.e. it's left exactly as
# whatever wrote it before this layer ran (Debian's zsh package).
@test "/etc/zsh/zshrc carries no Homebrew or starship configuration" {
  run docker run --rm "$IMAGE" sh -c 'grep -iE "brew|starship" /etc/zsh/zshrc'
  [ "$status" -ne 0 ]
}

@test "gh, vim, bubblewrap and claude all resolve on PATH" {
  run docker run --rm "$IMAGE" sh -c \
    'command -v gh && command -v vim && command -v bwrap && command -v claude'
  [ "$status" -eq 0 ]
}

@test "gh, vim and bubblewrap are installed via apt, not hand-rolled" {
  run docker run --rm "$IMAGE" sh -c \
    'dpkg -s gh >/dev/null && dpkg -s vim >/dev/null && dpkg -s bubblewrap >/dev/null'
  [ "$status" -eq 0 ]
}

# dive is a Homebrew formula, like starship, so it only resolves in a
# non-interactive login shell where /etc/zsh/zshenv sources brew's shellenv
# (same reasoning as the "brew resolves" test above).
@test "dive resolves on PATH in a non-interactive login shell" {
  run docker run --rm --user vscode "$IMAGE" zsh -lc 'command -v dive'
  [ "$status" -eq 0 ]
  [ "$output" = "/home/linuxbrew/.linuxbrew/bin/dive" ]
}

@test "Claude Code is installed from the signed apt repository, stable channel" {
  run docker run --rm "$IMAGE" sh -c 'dpkg -s claude-code >/dev/null && cat /etc/apt/sources.list.d/claude-code.list'
  [ "$status" -eq 0 ]
  [[ "$output" == *"downloads.claude.ai/claude-code/apt/stable stable main"* ]]
}

@test "Claude Code's apt key fingerprint matches Anthropic's published fingerprint" {
  run docker run --rm "$IMAGE" sh -c \
    "gpg --show-keys --with-colons --with-fingerprint /etc/apt/keyrings/claude-code.asc 2>/dev/null | awk -F: '\$1 == \"fpr\" { print \$10; exit }'"
  [ "$status" -eq 0 ]
  [ "$output" = "31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE" ]
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

# Issue #7's explicit exclusion list: single-repo tools that stay with
# their repo rather than landing in the shared base.
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
