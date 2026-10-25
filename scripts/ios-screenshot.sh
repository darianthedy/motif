#!/usr/bin/env bash
#
# Build the app for a simulator, launch it with the given arguments, and save a
# screenshot, so a session can look at what it built. See "Motif - iOS Mac Mode.md".
#
#   scripts/ios-screenshot.sh session-dark -MotifRoute session:all
#   APPEARANCE=light scripts/ios-screenshot.sh session-light -MotifRoute session:all
#
# Always runs on the memory backend with the samples loaded. Writes
# build/screenshots/<name>.png and prints the path.

set -euo pipefail
cd "$(dirname "$0")/.."

name="${1:?usage: $0 <name> [launch args…]}"; shift
PROJECT="iOS/Motif/Motif.xcodeproj"
SCHEME="Motif"
BUNDLE_ID="com.dthedy.Motif"
DERIVED="build/DerivedData"
OUT="build/screenshots"
WAIT="${WAIT:-4}"

sim=$(scripts/ios-simulator.sh)

xcrun simctl boot "$sim" 2>/dev/null || true   # already booted is fine
xcrun simctl bootstatus "$sim" -b
xcrun simctl ui "$sim" appearance "${APPEARANCE:-dark}"

app="$DERIVED/Build/Products/Debug-iphonesimulator/Motif.app"
if [ "${IOS_SCREENSHOT_SKIP_BUILD:-0}" != 1 ]; then
  xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
    -destination "platform=iOS Simulator,id=$sim" -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO -quiet
elif [ ! -d "$app" ]; then
  echo "No built app. Run without IOS_SCREENSHOT_SKIP_BUILD first." >&2
  exit 1
fi

xcrun simctl install "$sim" "$app"
xcrun simctl terminate "$sim" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$sim" "$BUNDLE_ID" -MotifMemoryBackend YES -MotifSeedSamples YES "$@" >/dev/null
sleep "$WAIT"

mkdir -p "$OUT"
xcrun simctl io "$sim" screenshot "$OUT/$name.png" >/dev/null
echo "$OUT/$name.png"
