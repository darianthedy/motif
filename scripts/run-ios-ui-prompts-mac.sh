#!/usr/bin/env bash
#
# run-ios-ui-prompts-mac.sh — build the UI refresh slices (U01..U10) locally on
# a Mac with the Mac-mode driver: branch → session → scripts/ios-verify.sh (+
# simulator screenshots) → merge into main-mac → backup bundle. No GitHub.
# Resume at a slice with `scripts/run-ios-ui-prompts-mac.sh U04`.
set -euo pipefail
cd "$(dirname "$0")/.."
export DOC="Motif - iOS UI Refresh Plan.md"
export PROMPT_IDS="U01 U02 U03 U04 U05 U06 U07 U08 U09 U10"
export BRANCH_PREFIX="ios-ui/"
export SPEC_RULE="The plan's screen descriptions (and the mockups it links) are the spec for the UI; the model, data layer and src/ behaviour stay unchanged."
exec scripts/run-ios-prompts-mac.sh "$@"
