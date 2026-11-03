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

shot() { # name, launch args
  name=$1; shift
  xcrun simctl terminate "$sim" "$BUNDLE_ID" 2>/dev/null
  xcrun simctl launch "$sim" "$BUNDLE_ID" -MotifMemoryBackend YES -MotifSeedSamples YES "$@" >/dev/null
  sleep 6
  xcrun simctl io "$sim" screenshot "$OUT/$name.png" >/dev/null
}

shot home
shot list -MotifRoute puzzle-list
shot detail -MotifRoute puzzle-detail
shot session -MotifRoute session:all
shot game -MotifRoute game:first
shot comment -MotifRoute game-comment
shot account -MotifRoute account
shot signin -MotifRoute signin

# If the simulator can change displays from here, this records what changes.
for arg in fold unfold; do
  xcrun simctl ui "$sim" "$arg" >> "$OUT/tools.txt" 2>&1 && echo "simctl ui $arg worked"
done
xcrun simctl io "$sim" screenshot "$OUT/after-unfold.png" >/dev/null
xcrun simctl list devicetypes | grep -i duo >> "$OUT/tools.txt"
