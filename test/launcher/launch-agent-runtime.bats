#!/usr/bin/env bats
#
# Argument-assembly tests for scripts/launch-agent-runtime: a stub `msb`
# earlier on PATH records the assembled command line and exits.
#
# The stub records one argument per line, never "$*", so a scope that
# word-split into two arguments fails here rather than reading identically
# in a flattened string. A stub cannot check whether msb honours what it
# was handed; that is live-checked separately (issues #77, #87).

setup() {
  stub_dir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$stub_dir"
  export MSB_ARGS_FILE="$BATS_TEST_TMPDIR/msb-args"
  # The stub records the GH_TOKEN it inherits, so a launcher that stopped
  # exporting a stdin-supplied token is noticed even though the forwarded
  # name still looks right.
  export MSB_ENV_FILE="$BATS_TEST_TMPDIR/msb-env"

  # --github-token needs a variable that is set; the value is irrelevant
  # here since only the stubbed msb resolves it.
  export GH_TOKEN="not-a-real-token"

  # The launcher must not call jq (issue #83). Exit 127 alone isn't enough:
  # sandbox_is_running runs as `... || return 0`, which suppresses set -e,
  # so the stub records the call and the test asserts on the recording.
  export JQ_CALLED_FILE="$BATS_TEST_TMPDIR/jq-called"
  cat > "$stub_dir/jq" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$JQ_CALLED_FILE"
exit 127
STUB
  chmod +x "$stub_dir/jq"

  # Answers just enough for the launcher to reach its final `exec msb run`:
  # no sandbox exists, every volume already exists, `run` records its args.
  cat > "$stub_dir/msb" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  list) ;;
  volume)
    # Succeeding means ensure_volume never calls create.
    exit 0
    ;;
  run)
    printf '%s\n' "$@" > "$MSB_ARGS_FILE"
    printf '%s' "$GH_TOKEN" > "$MSB_ENV_FILE"
    exit 0
    ;;
  *)
    # Loud, so an unrecognized subcommand can't become a silent pass.
    echo "msb stub: unexpected subcommand: $1" >&2
    exit 64
    ;;
esac
STUB
  chmod +x "$stub_dir/msb"
  export PATH="$stub_dir:$PATH"
}

# Explicit --name skips sandbox resolution, --clone-url skips the remote
# lookup, and a COMMAND keeps --persist-claude-auth (and its mount) off.
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

@test "--github-token expands to the two-host scope gh and git both need" {
  run launch --github-token GH_TOKEN
  [ "$status" -eq 0 ]
  has_flag_value "--secret" "GH_TOKEN@github.com,api.github.com"
}

# github.com alone leaves `gh` on an out-of-scope api.github.com (issue #77).
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

# `--github-token "$GH_TOKEN"` would put the token in argv. Tokens are
# identifier-shaped, so being an unset variable is what gives them away.
@test "a literal token value is rejected rather than forwarded" {
  run launch --github-token "ghp_thisisnotarealtokenvalue123456789"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a token value"* || "$output" == *"not the token value"* ]]
  [ ! -f "$MSB_ARGS_FILE" ]
}

# An error message is one more place a real token could end up.
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

# The violation default belongs to --github-token alone and must not leak
# onto plain --secret launches.
@test "a plain --secret launch is left exactly as it was" {
  run launch --secret OTHER@example.com
  [ "$status" -eq 0 ]
  has_flag_value "--secret" "OTHER@example.com"
  ! has_arg "--on-secret-violation"
}

# Only the non-tty half is testable here; the prompt branch needs a real
# terminal and is checked live instead.
@test "--github-token - reads the token from stdin and forwards a name" {
  run launch --github-token - <<< "piped-token-value"
  [ "$status" -eq 0 ]
  has_flag_value "--secret" "GH_TOKEN@github.com,api.github.com"
}

# The value must never reach the command line, where `ps` would show it.
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

# `read` returns non-zero at EOF on input with no trailing newline (a
# password-manager pipe), which under `set -e` would kill the script.
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

# msb resolves the forwarded name against the launcher's environment, so a
# stdin-supplied token must be exported there. GH_TOKEN is unset first, or
# setup()'s export would mask a launcher that stopped exporting.
@test "a stdin-supplied token reaches the environment msb inherits" {
  unset GH_TOKEN
  run launch --github-token - <<< "piped-token-value"
  [ "$status" -eq 0 ]
  [ "$(cat "$MSB_ENV_FILE")" = "piped-token-value" ]
}

# A CRLF-piped or space-padded token would otherwise be forwarded intact
# and rejected inside the guest (issue #77).
@test "a piped token loses a trailing carriage return and surrounding spaces" {
  unset GH_TOKEN
  run launch --github-token - < <(printf ' goodtoken \r\n')
  [ "$status" -eq 0 ]
  [ "$(cat "$MSB_ENV_FILE")" = "goodtoken" ]
}

# "A second one replaces the first" has to hold across the two forms, not
# just within each.
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

# The sandbox lookup is the path that used jq (issue #83), so a launch that
# resolves its own name exercises it - unlike launch(), which passes --name.
@test "a launch never calls jq" {
  run "$BATS_TEST_DIRNAME/../../scripts/launch-agent-runtime" \
    --clone-url https://example.invalid/repo.git -- true
  [ "$status" -eq 0 ]
  [ ! -f "$JQ_CALLED_FILE" ]
}

@test "--github-token is documented in --help" {
  run "$BATS_TEST_DIRNAME/../../scripts/launch-agent-runtime" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--github-token"* ]]
  [[ "$output" == *"api.github.com"* ]]
}
