#!/usr/bin/env bash
# Captain launch alias for the firstmate stack (issue #145, ADR-0021).
# Sourced from the runtime shell rc (zsh); the shebang is for shellcheck.
#
# `captain` opens the interactive captain session with the model pinned
# on the command line, so an unattended pipeline can never fall through
# to Claude Code's interactive model picker.
#
# The pin is the literal below. Change it here, in a reviewed diff, and
# re-run tooling/firstmate/model-guard; it must stay off the barred tiers.
#
# Source this from the runtime shell rc:
#   echo 'source ~/container-base/tooling/firstmate/captain.sh' >> ~/.zshrc

captain() {
  (cd "${FM_HOME:-$HOME/firstmate}" && exec claude --model sonnet "$@")
}
