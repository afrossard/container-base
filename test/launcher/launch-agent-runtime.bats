#!/usr/bin/env bats
#
# Argument-assembly tests for scripts/launch-agent-runtime: a stub `msb`
# earlier on PATH records the assembled command line and exits.
#
# The stub records one argument per line, never "$*", so a value that
# word-split into two arguments fails here rather than reading identically
# in a flattened string. A stub cannot check whether msb honours what it
# was handed; that is live-checked separately.

setup() {
  stub_dir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$stub_dir"
  cp "$BATS_TEST_DIRNAME/../helpers/msb" "$BATS_TEST_DIRNAME/../helpers/jq" \
    "$BATS_TEST_DIRNAME/../helpers/getent" "$stub_dir/"
  chmod +x "$stub_dir/msb" "$stub_dir/jq" "$stub_dir/getent"
  export PATH="$stub_dir:$PATH"

  # The stub records one argument per line, so a value that word-split
  # into two arguments fails a whole-line match here. Each file below is
  # read by at least one test; see test/helpers/msb for the stub itself.
  export MSB_ARGS_FILE="$BATS_TEST_TMPDIR/msb-args"
  export MSB_START_FILE="$BATS_TEST_TMPDIR/msb-start"
  export MSB_EXEC_FILE="$BATS_TEST_TMPDIR/msb-exec"
  export MSB_RM_FILE="$BATS_TEST_TMPDIR/msb-rm"
  export MSB_VOLUME_FILE="$BATS_TEST_TMPDIR/msb-volume"
  export JQ_CALLED_FILE="$BATS_TEST_TMPDIR/jq-called"

  # Runtime state the stub answers `list` from: names in STUB_ALL exist,
  # names also in STUB_RUNNING are running. Empty by default, so the
  # common case is "no runtime yet" and the launcher takes its create
  # path.
  export STUB_ALL=""
  export STUB_RUNNING=""

  # Host DNS the stub getent answers from, as NAME=IP[,IP...] entries.
  export STUB_HOSTS="nas.lan=192.168.1.20"
}

# Explicit --name skips sandbox resolution and --clone-url skips the remote
# lookup, so each test drives only the assembly it cares about.
launch() {
  "$BATS_TEST_DIRNAME/../../scripts/launch-agent-runtime" \
    --name test-session \
    --clone-url https://example.invalid/repo.git \
    "$@" -- true
}

# Matched as a whole line, so a word-split value fails rather than matching
# on a substring.
has_arg() {
  grep -Fxq -- "$1" "$MSB_ARGS_FILE"
}

# $2 is the argument immediately following $1, again as whole lines.
has_flag_value() {
  grep -A1 -Fx -- "$1" "$MSB_ARGS_FILE" | grep -Fxq -- "$2"
}

# --- generic secret passthrough (kept; the GitHub specialisation is not) ---

@test "a plain --secret is forwarded to msb run unchanged" {
  run launch --secret OTHER@example.com
  [ "$status" -eq 0 ]
  has_flag_value "--secret" "OTHER@example.com"
}

@test "--secret alone adds no --secret-violation-action of its own" {
  run launch --secret OTHER@example.com
  [ "$status" -eq 0 ]
  ! has_arg "--secret-violation-action"
}

@test "an explicit --secret-violation-action is forwarded verbatim" {
  run launch --secret OTHER@example.com --secret-violation-action block-and-terminate
  [ "$status" -eq 0 ]
  has_flag_value "--secret-violation-action" "block-and-terminate"
}

@test "--secret-violation-action passthrough is rejected" {
  run launch --secret OTHER@example.com --secret-violation-action passthrough
  [ "$status" -ne 0 ]
  [[ "$output" == *"passthrough is rejected"* ]]
  [ ! -f "$MSB_ARGS_FILE" ]
}

# msb renamed --on-secret-violation to --secret-violation-action (upstream
# microsandbox#1356); the old spelling gets no alias and falls to the
# generic unknown-argument path, same as the ADR-0022 removals below.
@test "the old --on-secret-violation spelling is rejected as an unknown argument" {
  run launch --secret OTHER@example.com --on-secret-violation block-and-log
  [ "$status" -ne 0 ]
  [[ "$output" == *"unrecognized argument"* ]]
  [ ! -f "$MSB_ARGS_FILE" ]
}

# --- flags removed with the disposable model get no special handling; they
#     fall to the generic unknown-argument path. --github-token and
#     --persist-claude-auth are retired (ADR-0022). --force is no longer
#     retired: it is the reset path's confirmation override (issue #146),
#     tested below. ---

@test "the removed credential flags are rejected as unknown arguments" {
  for flag in --github-token --persist-claude-auth --no-persist-claude-auth; do
    run launch "$flag"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unrecognized argument"* ]]
    [ ! -f "$MSB_ARGS_FILE" ]
  done
}

# --- reset: the one launcher path that destroys a runtime (issue #146) ---
#
# reset() calls the script directly: unlike launch(), it appends no
# `-- true` and no --clone-url, because reset returns before either is
# read. reset_bare() drops --name too, exercising reset's own runtime
# resolution.

reset() {
  "$BATS_TEST_DIRNAME/../../scripts/launch-agent-runtime" \
    --name test-session --reset "$@"
}

reset_bare() {
  "$BATS_TEST_DIRNAME/../../scripts/launch-agent-runtime" --reset "$@"
}

@test "--reset with --force destroys the runtime and its paired docker volume, and creates nothing" {
  export STUB_ALL="test-session"
  run reset --force
  [ "$status" -eq 0 ]
  grep -Fxq "test-session" "$MSB_RM_FILE"
  grep -Fxq "remove" "$MSB_VOLUME_FILE"
  grep -Fxq "test-session-docker-data" "$MSB_VOLUME_FILE"
  [ ! -f "$MSB_ARGS_FILE" ]
  [ ! -f "$MSB_START_FILE" ]
}

@test "--reset --name for a runtime that does not exist removes nothing and says so" {
  export STUB_ALL=""
  run reset --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"no runtime named 'test-session'"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

# --reset acts only on this repo's label set, so a --name that exists for
# another repo is refused, not destroyed.
@test "--reset --name for a runtime outside this repo's label set is refused" {
  export STUB_ALL="test-session other-repo-box"
  export STUB_LABELLED="test-session"
  run "$BATS_TEST_DIRNAME/../../scripts/launch-agent-runtime" \
    --name other-repo-box --reset --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"no runtime named 'other-repo-box'"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "a bare --reset with no runtime for the repo removes nothing and says so" {
  export STUB_ALL=""
  run reset_bare --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"no runtime for"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

# reset targets this repo's runtime directly - it must never fall through
# to the attach picker's "start a new one" branch.
@test "a bare --reset with several matching runtimes refuses and asks for --name" {
  export STUB_ALL="one two"
  run reset_bare --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"pass --name"* ]]
  [[ "$output" != *"start a new one"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "a bare --reset with exactly one matching runtime destroys it" {
  export STUB_ALL="solo"
  run reset_bare --force
  [ "$status" -eq 0 ]
  grep -Fxq "solo" "$MSB_RM_FILE"
  grep -Fxq "solo-docker-data" "$MSB_VOLUME_FILE"
}

@test "--reset without --force refuses when stdin isn't a terminal, and removes nothing" {
  export STUB_ALL="test-session"
  run reset
  [ "$status" -ne 0 ]
  [[ "$output" == *"terminal"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "--force without --reset is rejected" {
  run launch --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"--force only applies to --reset"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "no bare launch path removes a runtime" {
  export STUB_ALL="test-session" STUB_RUNNING="test-session"
  run launch
  [ "$status" -eq 0 ]
  [ ! -f "$MSB_RM_FILE" ]
}

@test "the usage text names reset as the launcher's only destruction path" {
  run "$BATS_TEST_DIRNAME/../../scripts/launch-agent-runtime" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--reset is the only launcher path that destroys a runtime"* ]]
}

@test "the create path carries no ~/.claude volume or PERSIST_CLAUDE_AUTH env" {
  run launch
  [ "$status" -eq 0 ]
  ! grep -q "/home/vscode/.claude" "$MSB_ARGS_FILE"
  ! grep -q "agent-claude-creds" "$MSB_ARGS_FILE"
  ! grep -q "PERSIST_CLAUDE_AUTH" "$MSB_ARGS_FILE"
}

# The sandbox lookup is the path that used jq (issue #83), so a launch that
# resolves its own name exercises it - unlike launch(), which passes --name.
@test "a launch never calls jq" {
  run "$BATS_TEST_DIRNAME/../../scripts/launch-agent-runtime" \
    --clone-url https://example.invalid/repo.git -- true
  [ "$status" -eq 0 ]
  [ ! -f "$JQ_CALLED_FILE" ]
}

# --- runtime lifecycle: which subcommand for which state (issue #144) ---
#
# The bare launch attaches to a running runtime, resumes a stopped one, and
# creates one only when none exists - never `msb run --replace`.

@test "no runtime for the repo: the launcher creates one with 'msb run'" {
  run launch
  [ "$status" -eq 0 ]
  [ -f "$MSB_ARGS_FILE" ]
  [ ! -f "$MSB_START_FILE" ]
  [ ! -f "$MSB_EXEC_FILE" ]
}

@test "a stopped runtime: the launcher resumes with 'msb start' then attaches, never 'msb run'" {
  export STUB_ALL="test-session"
  run launch
  [ "$status" -eq 0 ]
  grep -Fxq "test-session" "$MSB_START_FILE"
  [ -f "$MSB_EXEC_FILE" ]
  [ ! -f "$MSB_ARGS_FILE" ]
}

@test "a running runtime: the launcher attaches with 'msb exec' only, never 'msb start' or 'msb run'" {
  export STUB_ALL="test-session" STUB_RUNNING="test-session"
  run launch
  [ "$status" -eq 0 ]
  [ -f "$MSB_EXEC_FILE" ]
  [ ! -f "$MSB_START_FILE" ]
  [ ! -f "$MSB_ARGS_FILE" ]
}

@test "a failed agent-bringup warns and still hands over in the workspace" {
  export STUB_ALL="test-session" STUB_RUNNING="test-session"
  export STUB_EXEC_FAIL="-- agent-bringup"
  run launch
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-bringup reported a failure"* ]]
  grep -A1 -Fx -- "-w" "$MSB_EXEC_FILE" | grep -Fxq "/home/vscode/git/repo"
}

@test "a missing workspace clone warns and hands over in the home directory" {
  export STUB_ALL="test-session" STUB_RUNNING="test-session"
  export STUB_EXEC_FAIL="-- test -d /home/vscode/git/repo"
  run launch
  [ "$status" -eq 0 ]
  [[ "$output" == *"/home/vscode/git/repo is missing"* ]]
  grep -A1 -Fx -- "-w" "$MSB_EXEC_FILE" | grep -Fxq "/home/vscode"
}

@test "attach converges the runtime with agent-bringup before handing over" {
  export STUB_ALL="test-session" STUB_RUNNING="test-session"
  run launch
  [ "$status" -eq 0 ]
  grep -Fxq "agent-bringup" "$MSB_EXEC_FILE"
}

@test "attach runs the command as the vscode user in the workspace directory" {
  export STUB_ALL="test-session" STUB_RUNNING="test-session"
  run launch
  [ "$status" -eq 0 ]
  grep -A1 -Fx -- "-u" "$MSB_EXEC_FILE" | grep -Fxq -- "vscode"
  grep -A1 -Fx -- "-w" "$MSB_EXEC_FILE" | grep -Fxq -- "/home/vscode/git/repo"
}

@test "the create path no longer replaces a runtime or registers a boot script" {
  run launch
  [ "$status" -eq 0 ]
  ! has_arg "--replace"
  ! has_arg "--script-path"
  ! grep -q "workspace-init" "$MSB_ARGS_FILE"
}

@test "the create path passes the command straight through, unwrapped" {
  run launch
  [ "$status" -eq 0 ]
  # `-- true`, not `-- workspace-init true`.
  grep -A1 -Fx -- "--" "$MSB_ARGS_FILE" | grep -Fxq -- "true"
}

# Issue #222: the docker-in-docker feature's containerd keeps image layers
# under /var/lib/containerd, so that is the path that must not nest
# overlayfs on the guest's overlayfs root (docs/research/0022, ADR-0023).
@test "the create path mounts the disk-backed docker volume where containerd keeps image layers" {
  run launch
  [ "$status" -eq 0 ]
  has_flag_value "--mount-named" "test-session-docker-data:/var/lib/containerd:kind=disk,size=20G"
}

@test "the create path still forwards the clone URL and dotfiles repo as env" {
  run launch
  [ "$status" -eq 0 ]
  has_flag_value "--env" "WORKSPACE_CLONE_URL=https://example.invalid/repo.git"
  has_arg "--env"
}

# --- TOOLING_REPO (issue #172): passed at create time exactly as
#     DOTFILES_REPO is, defaulting to this repo's own clone URL. ---

@test "the create path forwards TOOLING_REPO, defaulting to this repo's clone URL" {
  run launch
  [ "$status" -eq 0 ]
  has_flag_value "--env" "TOOLING_REPO=https://github.com/afrossard/container-base.git"
}

@test "an operator-set TOOLING_REPO overrides the default" {
  export TOOLING_REPO="https://example.invalid/tooling.git"
  run launch
  [ "$status" -eq 0 ]
  has_flag_value "--env" "TOOLING_REPO=https://example.invalid/tooling.git"
}

# --- --allow-url: the "explicitly allowed" half of the private-network
#     policy (issue #234; the deny half is ADR-0013 / issue #30). ---

# Line number of the first whole-line match of $1 in the recorded args.
arg_line() {
  grep -nFx -- "$1" "$MSB_ARGS_FILE" | head -1 | cut -d: -f1
}

# The rule shape is the one measured against msb 0.7.13 on issue #234: msb's
# DNS rebind protection drops a private answer unless an address-only rule
# allows that address, so the group ends in a bare allow@IP, and port-range
# denies ahead of it (first match wins) narrow it back to the one port.
@test "--allow-url resolves the host and forwards a one-port rule group after --net public" {
  run launch --allow-url http://nas.lan:8080
  [ "$status" -eq 0 ]
  has_flag_value "--net" "public"
  has_flag_value "--net-rule" \
    "deny@192.168.1.20:tcp:1-8079,deny@192.168.1.20:tcp:8081-65535,deny@192.168.1.20:udp,allow@192.168.1.20"
  [ "$(arg_line --net)" -lt "$(arg_line --net-rule)" ]
}

@test "--allow-url takes the port from the scheme when the URL names none, and drops the path" {
  export STUB_HOSTS="nas.lan=192.168.1.20 ha.lan=192.168.1.30"
  run launch --allow-url http://nas.lan/admin --allow-url https://ha.lan/
  [ "$status" -eq 0 ]
  has_flag_value "--net-rule" \
    "deny@192.168.1.20:tcp:1-79,deny@192.168.1.20:tcp:81-65535,deny@192.168.1.20:udp,allow@192.168.1.20"
  has_flag_value "--net-rule" \
    "deny@192.168.1.30:tcp:1-442,deny@192.168.1.30:tcp:444-65535,deny@192.168.1.30:udp,allow@192.168.1.30"
}

# msb drops a whole DNS answer if any private address in it isn't allowed
# (measured on issue #234), so every address the host resolves gets a group.
@test "--allow-url forwards one rule group per address the host resolves to" {
  export STUB_HOSTS="nas.lan=192.168.1.20,192.168.2.20"
  run launch --allow-url https://nas.lan
  [ "$status" -eq 0 ]
  has_flag_value "--net-rule" \
    "deny@192.168.1.20:tcp:1-442,deny@192.168.1.20:tcp:444-65535,deny@192.168.1.20:udp,allow@192.168.1.20"
  has_flag_value "--net-rule" \
    "deny@192.168.2.20:tcp:1-442,deny@192.168.2.20:tcp:444-65535,deny@192.168.2.20:udp,allow@192.168.2.20"
}

@test "--allow-url with an IPv4 literal uses it as given, without a lookup" {
  export STUB_HOSTS=""
  run launch --allow-url http://10.0.0.5:3000
  [ "$status" -eq 0 ]
  has_flag_value "--net-rule" \
    "deny@10.0.0.5:tcp:1-2999,deny@10.0.0.5:tcp:3001-65535,deny@10.0.0.5:udp,allow@10.0.0.5"
}

@test "--allow-url on port 1 or 65535 leaves out the empty deny range" {
  export STUB_HOSTS="a.lan=10.0.0.1 b.lan=10.0.0.2"
  run launch --allow-url http://a.lan:1 --allow-url http://b.lan:65535
  [ "$status" -eq 0 ]
  has_flag_value "--net-rule" "deny@10.0.0.1:tcp:2-65535,deny@10.0.0.1:udp,allow@10.0.0.1"
  has_flag_value "--net-rule" "deny@10.0.0.2:tcp:1-65534,deny@10.0.0.2:udp,allow@10.0.0.2"
}

@test "--allow-url with a host that doesn't resolve fails before creating anything" {
  run launch --allow-url http://missing.lan
  [ "$status" -ne 0 ]
  [[ "$output" == *"'missing.lan' does not resolve"* ]]
  [ ! -f "$MSB_ARGS_FILE" ]
  [ ! -f "$MSB_VOLUME_FILE" ]
}

# One port per host: a second group for an address would never be reached,
# since the first group's denies match first.
@test "a second --allow-url landing on an already-allowed address is refused" {
  export STUB_HOSTS="nas.lan=192.168.1.20 nas-alias.lan=192.168.1.20"
  run launch --allow-url https://nas.lan --allow-url http://nas-alias.lan:8080
  [ "$status" -ne 0 ]
  [[ "$output" == *"one port per host"* ]]
  [ ! -f "$MSB_ARGS_FILE" ]
}

@test "--allow-url rejects a URL it cannot turn into one host and port, and creates nothing" {
  for url in nas.lan:8080 ftp://nas.lan http://nas.lan:80a http://nas.lan:0 \
    http://nas.lan:65536 http://nas.lan:123456789012345678901 http:// http://user:pw@nas.lan http://[fd00::1]:8080; do
    run launch --allow-url "$url"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--allow-url"* ]]
    [ ! -f "$MSB_ARGS_FILE" ]
  done
}

# A LAN exception only: --net public already allows public addresses, and a
# group for one would narrow it to a single port; loopback and link-local
# (cloud metadata) are never a LAN service.
@test "--allow-url refuses an address outside the private ranges, before creating anything" {
  export STUB_HOSTS="example.com=93.184.215.14 mixed.lan=192.168.1.20,93.184.215.14"
  for url in https://example.com https://mixed.lan http://127.0.0.1:8080 \
    http://169.254.169.254 http://999.1.1.1 http://192.168.1.256; do
    run launch --allow-url "$url"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--allow-url"* ]]
    [ ! -f "$MSB_ARGS_FILE" ]
    [ ! -f "$MSB_VOLUME_FILE" ]
  done
}

@test "--allow-url accepts each private range" {
  export STUB_HOSTS=""
  run launch --allow-url http://10.1.2.3 --allow-url http://172.31.0.1 \
    --allow-url http://192.168.0.1 --allow-url http://100.64.0.1
  [ "$status" -eq 0 ]
  for ip in 10.1.2.3 172.31.0.1 192.168.0.1 100.64.0.1; do
    has_flag_value "--net-rule" "deny@$ip:tcp:1-79,deny@$ip:tcp:81-65535,deny@$ip:udp,allow@$ip"
  done
}

@test "--allow-url matches the scheme case-insensitively" {
  run launch --allow-url HTTPS://nas.lan
  [ "$status" -eq 0 ]
  has_flag_value "--net-rule" \
    "deny@192.168.1.20:tcp:1-442,deny@192.168.1.20:tcp:444-65535,deny@192.168.1.20:udp,allow@192.168.1.20"
}

@test "--allow-url with --reset is rejected rather than ignored" {
  export STUB_ALL="test-session"
  run reset --force --allow-url https://nas.lan
  [ "$status" -ne 0 ]
  [[ "$output" == *"--allow-url"*"--reset"* ]]
  [ ! -f "$MSB_RM_FILE" ]
}

# The policy is fixed at creation (ADR-0021) and msb can't change an
# existing sandbox's network rules, so an exception passed to an existing
# runtime is reported, not silently dropped.
@test "--allow-url passed to an existing runtime warns that it needs --reset, and still attaches" {
  for running in "" test-session; do
    export STUB_ALL="test-session" STUB_RUNNING="$running"
    run launch --allow-url http://nas.lan:8080
    [ "$status" -eq 0 ]
    [[ "$output" == *"--allow-url"*"--reset"* ]]
    [ -f "$MSB_EXEC_FILE" ]
  done
}

@test "an attach without --allow-url says nothing about the network policy" {
  export STUB_ALL="test-session" STUB_RUNNING="test-session"
  run launch
  [ "$status" -eq 0 ]
  [[ "$output" != *"--allow-url"* ]]
}
