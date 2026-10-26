#!/usr/bin/env bash
#
# run-ios-ui-prompts.sh — drive the UI refresh slices (U01..U10) with the same
# one-session-per-slice driver as the build prompts: branch → PR → ios-ci →
# merge → TestFlight. Resume at a slice with `scripts/run-ios-ui-prompts.sh U04`.
# Run it from a clean, dedicated checkout on `main` (it switches branches).
set -euo pipefail
cd "$(dirname "$0")/.."
export DOC="Motif - iOS UI Refresh Plan.md"
export PROMPT_IDS="U01 U02 U03 U04 U05 U06 U07 U08 U09 U10"
export BRANCH_PREFIX="ios-ui/"
export SPEC_RULE="The plan's screen descriptions (and the mockups it links) are the spec for the UI; the model, data layer and src/ behaviour stay unchanged."
exec scripts/run-ios-prompts.sh "$@"
