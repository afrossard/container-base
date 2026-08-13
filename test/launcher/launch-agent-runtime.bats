#!/usr/bin/env bats
#
# Argument-assembly tests for scripts/launch-agent-runtime.
#
# The launcher's job is to turn a small set of flags into one long `msb run`
# invocation, so the assembled command line is the thing worth asserting on.
# A stub `msb` earlier on PATH records that command line and exits, which
# makes these tests fast, deterministic, and runnable with no hypervisor,
# no network, and no real image - the opposite of the live launches that
# verified this script's earlier behaviour (issues #32, #33, #34, #54).
#
# The stub records one argument per line, never "$*", because the property
# most worth protecting here is that a scope stays a single argument: a
# `github.com,api.github.com` that word-split into two would read identically
# in a flattened string and be wrong on the wire. The two scope assertions
# below were confirmed to go red against a deliberately word-split build,
# rather than only ever observed green.
#
# What a stub cannot check is whether msb honours what it was handed. That
# the guest holds only a placeholder was verified separately by a live
# launch with a dummy token (it came back as the literal $MSB_GH_TOKEN);
# that `gh` actually authenticates against the scoped hosts needs a live
# launch with a real token, and is recorded as such in issue #77.

setup() {
  stub_dir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$stub_dir"
  export MSB_ARGS_FILE="$BATS_TEST_TMPDIR/msb-args"
  # The stub records the GH_TOKEN it inherits as well as its arguments.
  # Without this, nothing would notice if the launcher stopped exporting a
  # stdin-supplied token: the forwarded *name* would still look right while
  # msb had no value to resolve.
  export MSB_ENV_FILE="$BATS_TEST_TMPDIR/msb-env"

  # The launcher now requires --github-token to name a variable that is
  # actually set, so that a literal token value is rejected rather than
  # forwarded into argv. The value is irrelevant here - only msb ever
  # resolves it, and msb is stubbed.
  export GH_TOKEN="not-a-real-token"

  # Answers just enough for the launcher to reach its final `exec msb run`:
  # no sandbox exists, every volume already exists (so nothing is created),
  # and `run` records its arguments instead of booting anything.
  cat > "$stub_dir/msb" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  list) echo '[]' ;;
  volume)
    # `volume inspect` succeeding means ensure_volume never calls create.
    exit 0
    ;;
  run)
    printf '%s\n' "$@" > "$MSB_ARGS_FILE"
    printf '%s' "$GH_TOKEN" > "$MSB_ENV_FILE"
    exit 0
    ;;
  *)
    # Loud rather than a silent exit 0, which would let an unrecognized
    # subcommand turn into a passing test that asserted nothing.
    echo "msb stub: unexpected subcommand: $1" >&2
    exit 64
    ;;
esac
STUB
  chmod +x "$stub_dir/msb"
  export PATH="$stub_dir:$PATH"
}

# Keeps every case to the one flag under test: an explicit --name skips
# sandbox resolution, an explicit --clone-url skips the git remote lookup,
# and a COMMAND keeps --persist-claude-auth off (and so its extra mount).
launch() {
  "$BATS_TEST_DIRNAME/../../scripts/launch-agent-runtime" \
    --name test-session \
    --clone-url https://example.invalid/repo.git \
    "$@" -- true
}

# One whole argument, matched as a full line - so a value that word-split
# into two arguments fails here rather than passing on a substring.
has_arg() {
  grep -Fxq -- "$1" "$MSB_ARGS_FILE"
}

# $2 is the argument immediately following $1, again as whole lines.
has_flag_value() {
  grep -A1 -Fx -- "$1" "$MSB_ARGS_FILE" | grep -Fxq -- "$2"
}

@test "--github-token expands to the two-host scope gh and git both need" {
  run launch --github-token GH_TOKEN
  [ "$status" -eq 0 ]
  has_flag_value "--secret" "GH_TOKEN@github.com,api.github.com"
}

# github.com alone leaves `gh` talking to an out-of-scope api.github.com and
# receiving the placeholder, which GitHub rejects as an invalid token - the
# exact failure #77 was filed for.
@test "--github-token never scopes the token to github.com alone" {
  run launch --github-token GH_TOKEN
  [ "$status" -eq 0 ]
  ! has_arg "GH_TOKEN@github.com"
}

@test "--github-token applies the recommended violation action by default" {
  run launch --github-token GH_TOKEN
  [ "$status" -eq 0 ]
  has_flag_value "--on-secret-violation" "block-and-log"
}

@test "an explicit --on-secret-violation wins over the default" {
  run launch --github-token GH_TOKEN --on-secret-violation passthrough
  [ "$status" -eq 0 ]
  has_flag_value "--on-secret-violation" "passthrough"
  ! has_arg "block-and-log"
}

@test "the flag order does not decide which violation action wins" {
  run launch --on-secret-violation passthrough --github-token GH_TOKEN
  [ "$status" -eq 0 ]
  has_flag_value "--on-secret-violation" "passthrough"
  ! has_arg "block-and-log"
}

@test "--github-token composes with a hand-written --secret" {
  run launch --github-token GH_TOKEN --secret OTHER@example.com
  [ "$status" -eq 0 ]
  has_flag_value "--secret" "GH_TOKEN@github.com,api.github.com"
  has_flag_value "--secret" "OTHER@example.com"
}

# `--github-token "$GH_TOKEN"` is the natural slip, and it would put the real
# token into this process's argv where `ps` can read it. The charset check
# alone cannot catch it, since real tokens are identifier-shaped; being an
# unset variable is what gives them away.
@test "a literal token value is rejected rather than forwarded" {
  run launch --github-token "ghp_thisisnotarealtokenvalue123456789"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a token value"* || "$output" == *"not the token value"* ]]
  [ ! -f "$MSB_ARGS_FILE" ]
}

# Whatever it rejects, it must never print it back: an error message is one
# more place a real token could end up.
@test "the rejection never echoes back what it rejected" {
  run launch --github-token "ghp_thisisnotarealtokenvalue123456789"
  [ "$status" -ne 0 ]
  [[ "$output" != *"ghp_thisisnotarealtokenvalue123456789"* ]]
}

@test "--github-token naming an unset variable fails at launch, not in the guest" {
  unset UNSET_TOKEN_VAR
  run launch --github-token UNSET_TOKEN_VAR
  [ "$status" -ne 0 ]
  [ ! -f "$MSB_ARGS_FILE" ]
}

@test "--github-token with an empty value is rejected, not silently ignored" {
  run launch --github-token ""
  [ "$status" -ne 0 ]
  [ ! -f "$MSB_ARGS_FILE" ]
}

# Guards the existing contract: the violation default belongs to
# --github-token alone and must not leak onto plain --secret launches,
# which have always left the action to msb unless asked otherwise.
@test "a plain --secret launch is left exactly as it was" {
  run launch --secret OTHER@example.com
  [ "$status" -eq 0 ]
  has_flag_value "--secret" "OTHER@example.com"
  ! has_arg "--on-secret-violation"
}

# `--github-token -` reads the token itself rather than naming a variable
# that holds it, so the operator never has to export anything. Only the
# non-tty half is testable here; the prompt branch needs a real terminal
# and is checked live instead.
@test "--github-token - reads the token from stdin and forwards a name" {
  run launch --github-token - <<< "piped-token-value"
  [ "$status" -eq 0 ]
  has_flag_value "--secret" "GH_TOKEN@github.com,api.github.com"
}

# The whole point of forwarding a name is that the value never reaches the
# command line, where `ps` would show it.
@test "a piped token never appears in the msb command line" {
  run launch --github-token - <<< "piped-token-value"
  [ "$status" -eq 0 ]
  ! grep -q "piped-token-value" "$MSB_ARGS_FILE"
}

@test "--github-token - still applies the recommended violation action" {
  run launch --github-token - <<< "piped-token-value"
  [ "$status" -eq 0 ]
  has_flag_value "--on-secret-violation" "block-and-log"
}

# `read` returns non-zero at EOF when the input has no trailing newline,
# which under `set -e` would kill the script even though the variable was
# populated. Piping from a password manager is exactly where that happens.
@test "a piped token without a trailing newline still works" {
  run launch --github-token - < <(printf 'no-trailing-newline')
  [ "$status" -eq 0 ]
  has_flag_value "--secret" "GH_TOKEN@github.com,api.github.com"
}

@test "--github-token - with nothing on stdin fails before launching" {
  run launch --github-token - < /dev/null
  [ "$status" -ne 0 ]
  [ ! -f "$MSB_ARGS_FILE" ]
}

# Forwarding the right name is only half the job: msb resolves that name
# against the launcher's own environment, so a stdin-supplied token has to
# actually be exported there. GH_TOKEN is unset first, or setup()'s own
# export would mask a launcher that stopped exporting anything.
@test "a stdin-supplied token reaches the environment msb inherits" {
  unset GH_TOKEN
  run launch --github-token - <<< "piped-token-value"
  [ "$status" -eq 0 ]
  [ "$(cat "$MSB_ENV_FILE")" = "piped-token-value" ]
}

# A token piped from a CRLF file, or pasted with a stray space, would
# otherwise be forwarded intact and rejected inside the guest as an invalid
# token - the misdirection this whole issue is about.
@test "a piped token loses a trailing carriage return and surrounding spaces" {
  unset GH_TOKEN
  run launch --github-token - < <(printf ' goodtoken \r\n')
  [ "$status" -eq 0 ]
  [ "$(cat "$MSB_ENV_FILE")" = "goodtoken" ]
}

# The usage text promises "a second one replaces the first". That has to
# hold across the two forms, not just within each of them, or whichever
# form the code happens to favour wins over whatever the operator typed.
@test "a later --github-token name replaces an earlier -" {
  export NAMED_TOKEN_VAR="named-value"
  run launch --github-token - --github-token NAMED_TOKEN_VAR <<< "piped-token-value"
  [ "$status" -eq 0 ]
  has_flag_value "--secret" "NAMED_TOKEN_VAR@github.com,api.github.com"
  ! has_arg "GH_TOKEN@github.com,api.github.com"
}

@test "a later --github-token - replaces an earlier name" {
  export NAMED_TOKEN_VAR="named-value"
  run launch --github-token NAMED_TOKEN_VAR --github-token - <<< "piped-token-value"
  [ "$status" -eq 0 ]
  has_flag_value "--secret" "GH_TOKEN@github.com,api.github.com"
  ! has_arg "NAMED_TOKEN_VAR@github.com,api.github.com"
}

@test "--github-token - is not mistaken for a variable named -" {
  run launch --github-token - <<< "piped-token-value"
  [ "$status" -eq 0 ]
  ! has_arg "-@github.com,api.github.com"
}

@test "--github-token is documented in --help" {
  run "$BATS_TEST_DIRNAME/../../scripts/launch-agent-runtime" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--github-token"* ]]
  [[ "$output" == *"api.github.com"* ]]
}
