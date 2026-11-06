#!/usr/bin/env bash
#
# run-ios-duo-prompts.sh — drive the iPhone Duo slices (D01..D11) with the same
# one-session-per-slice driver as the build prompts: branch → PR → ios-ci →
# merge → TestFlight. Resume at a slice with `scripts/run-ios-duo-prompts.sh D05`.
# Run it from a clean, dedicated checkout on `main` (it switches branches).
set -euo pipefail
cd "$(dirname "$0")/.."
export DOC="Motif - iOS iPhone Duo Plan.md"
export PROMPT_IDS="D01 D02 D03 D04 D05 D06 D07 D08 D09 D10 D11"
export BRANCH_PREFIX="ios-duo/"
export SPEC_RULE="The approved canvases in design/iphone-duo/ and the plan's §10 decisions are the spec for the UI (§9.2 has the shared rules); the model, data layer, engine and src/ behaviour stay unchanged."
exec scripts/run-ios-prompts.sh "$@"
