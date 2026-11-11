#!/usr/bin/env bash
#
# Mac mode's definition of "builds": the web suite, then the iOS unit and UI tests on
# an iPhone simulator. Exit 0 only when both pass. See "Motif - iOS Mac Mode.md".
#
#   scripts/ios-verify.sh            # npm test + xcodebuild test
#   scripts/ios-verify.sh --ios      # skip npm test
#   scripts/ios-verify.sh --smoke    # all MotifTests, only the UI smoke set (SMOKE_UI)
#   scripts/ios-verify.sh --ios --smoke
#
# The flags combine in any order. Without --smoke every test runs, as before; ios-ci
# uses --smoke for its quick PR leg and the full run everywhere else.
#
# MOTIF_SIM (a device name or UDID) picks the simulator, and MOTIF_RUNTIME an iOS
# major version to prefer (see ios-simulator.sh); the default is the first
# available iPhone. MOTIF_POSE (iphone, IL, ipad…) reaches the tests as MOTIF_POSE, for
# UI tests that only hold in one pose. ios-ci sets all three per destination.
#
# Written for macOS's bash 3.2: no associative arrays, no GNU-only flags.

set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="iOS/Motif/Motif.xcodeproj"
SCHEME="Motif"

# The PR smoke set: the whole unit target plus the UI flows that touch every screen
# once. Solve keeps just its end-to-end test (sign in, import, solve, finish).
SMOKE_UI="AccountFlowTests NavigationFlowTests PuzzlesHomeFlowTests SheetsBannersFlowTests
SolveFlowTests/testSignInPasteImportAndCleanTapSolve"

web=1
smoke=0
for arg in "$@"; do
  case "$arg" in
    --ios) web=0 ;;
    --smoke) smoke=1 ;;
    *) echo "ios-verify.sh: unknown option '$arg' (use --ios, --smoke)" >&2; exit 2 ;;
  esac
done

if [ "$web" = 1 ]; then
  echo "== npm test"
  npm test --silent
fi

# The Stockfish nets the app bundles; a missing net fails here, before the build.
echo "== fetch NNUE nets"
scripts/fetch-nnue.sh

# A UDID distinguishes simulators with the same name on different runtimes.
sim=$(scripts/ios-simulator.sh)

selection=""
if [ "$smoke" = 1 ]; then
  selection="-only-testing:MotifTests"
  for t in $SMOKE_UI; do selection="$selection -only-testing:MotifUITests/$t"; done
fi

echo "== xcodebuild test on '$sim'${MOTIF_POSE:+ (pose $MOTIF_POSE)}${selection:+ (smoke)}"
# xcodebuild hands TEST_RUNNER_-prefixed variables to the test runner, unprefixed.
export TEST_RUNNER_MOTIF_POSE="${MOTIF_POSE:-}"
set -- xcodebuild test -project "$PROJECT" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$sim" \
  -derivedDataPath build/DerivedData \
  $selection \
  CODE_SIGNING_ALLOWED=NO
if command -v xcbeautify >/dev/null 2>&1; then
  "$@" 2>&1 | xcbeautify --renderer terminal
else
  # The filter must not decide the result (grep fails on no match), so take
  # xcodebuild's own status from the pipeline.
  set +e
  "$@" 2>&1 | grep --line-buffered -E 'error:|warning: .*Swift|Test Case .*(passed|failed)|Executed|\*\* (BUILD|TEST)'
  status=${PIPESTATUS[0]}
  set -e
  exit "$status"
fi
