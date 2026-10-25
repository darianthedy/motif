#!/usr/bin/env bash
#
# Mac mode's definition of "builds": the web suite, then the iOS unit tests on
# an iPhone simulator. Exit 0 only when both pass. See "Motif - iOS Mac Mode.md".
#
#   scripts/ios-verify.sh            # npm test + xcodebuild test
#   scripts/ios-verify.sh --ios      # skip npm test
#
# Written for macOS's bash 3.2: no associative arrays, no GNU-only flags.

set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="iOS/Motif/Motif.xcodeproj"
SCHEME="Motif"

if [ "${1:-}" != "--ios" ]; then
  echo "== npm test"
  npm test --silent
fi

# The first available iPhone simulator, by name. Names change with each Xcode
# ("iPhone 17", …), so it is looked up rather than hard-coded.
sim=$(xcrun simctl list devices available | sed -n 's/^ *\(iPhone[^(]*\) (.*/\1/p' | head -1 | sed 's/ *$//')
[ -n "$sim" ] || { echo "No iPhone simulator available — install the iOS runtime (Xcode → Settings → Components)." >&2; exit 1; }

echo "== xcodebuild test on '$sim'"
set -- xcodebuild test -project "$PROJECT" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$sim" \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO
if command -v xcbeautify >/dev/null 2>&1; then
  "$@" 2>&1 | xcbeautify --renderer terminal
else
  # The filter must not decide the result (grep fails on no match), so take
  # xcodebuild's own status from the pipeline.
  set +e
  "$@" 2>&1 | grep -E 'error:|warning: .*Swift|Test Case .*(passed|failed)|Executed|\*\* (BUILD|TEST)'
  status=${PIPESTATUS[0]}
  set -e
  exit "$status"
fi
