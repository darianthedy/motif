#!/usr/bin/env bash
#
# run-ios-duo-prompts.sh — drive the iPhone Duo slices (D01..D11), one fresh
# session per slice, in BATCH mode (plan §9.1): every slice is a commit on
# ios-duo/all with no CI in between; then one push, one PR, one ios-ci fix loop,
# merge, TestFlight. Resume at a slice with `scripts/run-ios-duo-prompts.sh D05`
# (it continues on the existing branch). `BATCH_BRANCH= scripts/…` runs the old
# per-slice flow (a PR and CI per slice) instead.
# Run it from a clean, dedicated checkout (it switches branches).
set -euo pipefail
cd "$(dirname "$0")/.."
export DOC="Motif - iOS iPhone Duo Plan.md"
export PROMPT_IDS="D01 D02 D03 D04 D05 D06 D07 D08 D09 D10 D11"
export BRANCH_PREFIX="ios-duo/"
export SPEC_RULE="The approved canvases in design/iphone-duo/ and the plan's §10 decisions are the spec for the UI (§9.2 has the shared rules); the model, data layer, engine and src/ behaviour stay unchanged."
export BATCH_BRANCH="${BATCH_BRANCH-ios-duo/all}"
export MAX_FIX_ATTEMPTS="${MAX_FIX_ATTEMPTS:-10}"
exec scripts/run-ios-prompts.sh "$@"
