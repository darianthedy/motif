#!/usr/bin/env bash
#
# run-ios-eval-prompts.sh — drive the eval bar slices (E01..E03) with the same
# one-session-per-slice driver as the build prompts: branch → PR → ios-ci →
# merge → TestFlight. Resume at a slice with `scripts/run-ios-eval-prompts.sh E02`.
# Run it from a clean, dedicated checkout on `main` (it switches branches).
set -euo pipefail
cd "$(dirname "$0")/.."
export DOC="Motif - iOS Eval Bar Plan.md"
export PROMPT_IDS="E01 E02 E03"
export BRANCH_PREFIX="ios-eval/"
export SPEC_RULE="The plan's §1–§4 are the spec for the engine, analyzer and bar; the model, data layer and src/ behaviour stay unchanged."
exec scripts/run-ios-prompts.sh "$@"
