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
# MOTIF_TEST_RETRIES, MOTIF_TEST_REPEAT and MOTIF_ONLY_TESTING are described where they're read.
# MOTIF_XCODEBUILD_FLAGS adds extra xcodebuild options or build settings, unquoted
# (ios-ci turns on compilation caching and skips package re-resolution with it).
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

# MOTIF_ONLY_TESTING (space- or comma-separated, e.g. "MotifUITests/GamesFlowTests") runs
# just those tests, in place of the whole suite or the smoke set.
selection=""
if [ -n "${MOTIF_ONLY_TESTING:-}" ]; then
  for t in $(echo "$MOTIF_ONLY_TESTING" | tr ',' ' '); do selection="$selection -only-testing:$t"; done
elif [ "$smoke" = 1 ]; then
  selection="-only-testing:MotifTests"
  for t in $SMOKE_UI; do selection="$selection -only-testing:MotifUITests/$t"; done
fi

# MOTIF_TEST_RETRIES=N runs a failing test up to N times in all, and passes when one
# attempt does (ios-ci uses 2, so a flaky UI test doesn't cost a whole re-run).
retry=""
if [ "${MOTIF_TEST_RETRIES:-1}" -gt 1 ]; then
  retry="-retry-tests-on-failure -test-iterations $MOTIF_TEST_RETRIES"
fi
# MOTIF_TEST_REPEAT=N runs every selected test N times whatever each run gives, in place of
# the retries, to measure a flaky test: pair it with MOTIF_ONLY_TESTING. Any failure fails.
repeat=""
if [ "${MOTIF_TEST_REPEAT:-1}" -gt 1 ]; then
  repeat="-test-iterations $MOTIF_TEST_REPEAT"; retry=""
fi

# xcodebuild buffers its output into a pipe; unbuffered, the log's timestamps are real.
export NSUnbufferedIO=YES
# xcodebuild hands TEST_RUNNER_-prefixed variables to the test runner, unprefixed.
export TEST_RUNNER_MOTIF_POSE="${MOTIF_POSE:-}"
mkdir -p build
common=(-project "$PROJECT" -scheme "$SCHEME" -destination "platform=iOS Simulator,id=$sim" -derivedDataPath build/DerivedData)

# Run xcodebuild through xcbeautify (or a grep filter), teeing the filtered lines to $1.
# The filter must not decide the result, so the status is xcodebuild's own.
xcb() {
  log=$1; shift
  set +e
  if command -v xcbeautify >/dev/null 2>&1; then
    "$@" 2>&1 | xcbeautify --renderer terminal | tee "$log"
  else
    "$@" 2>&1 | grep --line-buffered -E 'error:|warning: .*Swift|Test Case .*(passed|failed)|Executed|\*\* (BUILD|TEST)' | tee "$log"
  fi
  status=${PIPESTATUS[0]}
  set -e
  return "$status"
}

# One `xcodebuild test`, as before: run as build-for-testing, a simulator boot and
# test-without-building, ios-ci took 2-4 minutes longer to reach the first test.
echo "== xcodebuild test on '$sim'${MOTIF_POSE:+ (pose $MOTIF_POSE)}${selection:+ (smoke)}${retry:+ (up to $MOTIF_TEST_RETRIES attempts)}${repeat:+ ($MOTIF_TEST_REPEAT runs each)}"
# `|| status=$?`, since xcb turns `set -e` back on: a failing run must still reach the summary below.
status=0
xcb build/test.log xcodebuild test "${common[@]}" $selection $retry $repeat \
  ${MOTIF_XCODEBUILD_FLAGS:-} CODE_SIGNING_ALLOWED=NO || status=$?

if [ -n "$repeat" ]; then
  plain=$(sed -E 's/\x1b\[[0-9;]*m//g' build/test.log)
  echo "== $MOTIF_TEST_REPEAT runs each: $(echo "$plain" | grep -cE '^ *✔ ' || true) passed, $(echo "$plain" | grep -cE '^ *✖ ' || true) failed"
fi

# A test that failed and then passed on a retry still deserves a look: flag it on the run.
if [ "$status" = 0 ] && [ -n "$retry" ]; then
  flaky=$(sed -E 's/\x1b\[[0-9;]*m//g' build/test.log | grep -E '^ *✖ ' | sed -E 's/^ *✖ //' | sort -u || true)
  if [ -n "$flaky" ]; then
    echo "== passed only on a retry:"
    echo "$flaky" | while IFS= read -r t; do
      echo "   $t"
      if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::warning title=Flaky test (passed on retry)::$t"; fi
    done
  fi
fi
exit "$status"
