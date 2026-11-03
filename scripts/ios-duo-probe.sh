#!/usr/bin/env bash
#
# Temporary: iPhone Duo Phases 0 and 1. Builds the app with the layout probe,
# records which simulator controls can change the pose, and screenshots the probe
# on the iPhone Duo simulator. Writes everything to build/duo-probe.

set -uo pipefail
cd "$(dirname "$0")/.."

OUT="build/duo-probe"
PROJECT="iOS/Motif/Motif.xcodeproj"
BUNDLE_ID="com.dthedy.Motif"
mkdir -p "$OUT"

# Does the pose have a command-line control? Everything here is informational.
{
  echo "== versions"; xcodebuild -version; xcrun --sdk iphonesimulator --show-sdk-version
  echo "== devices"; xcrun simctl list devices available
  echo "== simctl"; xcrun simctl help
  echo "== simctl ui"; xcrun simctl ui 2>&1
  echo "== simctl io"; xcrun simctl help io 2>&1
  echo "== devicectl"; xcrun devicectl --help 2>&1
  echo "== tools mentioning a pose"
  ls "$(xcode-select -p)/usr/bin" "$(xcode-select -p)/../Applications" 2>&1
  xcrun simctl help 2>&1 | grep -i -E 'fold|hinge|pose|posture' || echo "none in simctl help"
  echo "== DeviceHub"
  ls "$(xcode-select -p)/../Applications/DeviceHub.app/Contents/MacOS" 2>&1
} > "$OUT/tools.txt" 2>&1

sim=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for device in devices:
        if device["name"] == "iPhone Duo":
            print(device["udid"]); sys.exit()
sys.exit("No iPhone Duo simulator")') || exit 1
echo "iPhone Duo simulator: $sim"

xcrun simctl boot "$sim"
xcrun simctl bootstatus "$sim" -b
xcrun simctl ui "$sim" appearance dark

xcodebuild build -project "$PROJECT" -scheme Motif -configuration Debug \
  -destination "platform=iOS Simulator,id=$sim" -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO 'OTHER_SWIFT_FLAGS=$(inherited) -DMOTIF_LAYOUT_PROBE' \
  > "$OUT/build.log" 2>&1
status=$?
grep -E 'error:|\*\* BUILD' "$OUT/build.log"
[ "$status" -eq 0 ] || exit "$status"

xcrun simctl install "$sim" build/DerivedData/Build/Products/Debug-iphonesimulator/Motif.app

OUTER=1   # LCD (primary), 1398x2034

shot() { # display, name, launch args
  display=$1; name=$2; shift 2
  xcrun simctl terminate "$sim" "$BUNDLE_ID" 2>/dev/null
  xcrun simctl launch "$sim" "$BUNDLE_ID" -MotifMemoryBackend YES -MotifSeedSamples YES "$@" >/dev/null
  sleep 6
  xcrun simctl io "$sim" screenshot --display="$display" "$OUT/$name.png" >/dev/null
}

routes() { # display, prefix
  shot "$1" "$2-home"
  shot "$1" "$2-list" -MotifRoute puzzle-list
  shot "$1" "$2-detail" -MotifRoute puzzle-detail
  shot "$1" "$2-session" -MotifRoute session:all
  shot "$1" "$2-game" -MotifRoute game:first
  shot "$1" "$2-comment" -MotifRoute game-comment
  shot "$1" "$2-account" -MotifRoute account
  shot "$1" "$2-signin" -MotifRoute signin
}

enumerate() { # label
  { echo "== io enumerate: $1"; xcrun simctl io "$sim" enumerate; } >> "$OUT/tools.txt" 2>&1
}

enumerate boot
routes "$OUTER" boot-outer

# simctl has no fold command, and powering the screens off crashes the system
# shell, so only the outer display can be captured here.
ls "$OUT"/*.png >/dev/null 2>&1 || { echo "No screenshots were written" >&2; exit 1; }
