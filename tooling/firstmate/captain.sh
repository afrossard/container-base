# Captain launch alias for the firstmate stack (issue #145, ADR-0021).
#
# `captain` opens the interactive captain session with the model pinned
# explicitly on the command line, so an unattended pipeline can never
# fall through to Claude Code's interactive model picker.
#
# Change the pin by editing CAPTAIN_MODEL below and re-running
# tooling/firstmate/model-guard; it must stay off the barred tiers.
#
# Source this from the runtime shell rc:
#   echo 'source ~/container-base/tooling/firstmate/captain.sh' >> ~/.zshrc

CAPTAIN_MODEL="${CAPTAIN_MODEL:-sonnet}"

captain() {
  (cd "${FM_HOME:-$HOME/firstmate}" && exec claude --model "$CAPTAIN_MODEL" "$@")
}
