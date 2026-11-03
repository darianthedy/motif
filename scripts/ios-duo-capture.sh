#!/usr/bin/env bash
#
# iPhone Duo Phase 2: put the iPhone Duo simulator in one pose, run the capture
# suite (MotifUITests/DuoCaptureTests), and export its screenshots as
# build/duo-capture/<label>/<state>.png. See "Motif - iOS iPhone Duo Plan.md" §8.
#
#   scripts/ios-duo-capture.sh build                    # build-for-testing with the selected Xcode
#   scripts/ios-duo-capture.sh capture <pose> <label> [app]
#
# Poses: O (closed), IL (open, wide), IP (open, tall), FB (half open, wide: book),
# FT (half open, tall: tabletop). The hinge and rotation are set with duoctl, which
# drives the simulator through private interfaces (Xcode 27.1+). `app` replaces the
# app under test, e.g. one built with the iOS 26 SDK to capture compatibility mode.
# MOTIF_CAPTURE_ONLY narrows the states (see DuoCaptureTests).
#
# Needs Xcode 27.1, the iOS 27.1 runtime and duoctl (brew install skarol/tap/duoctl).

set -uo pipefail
cd "$(dirname "$0")/.."

PROJECT="iOS/Motif/Motif.xcodeproj"
DERIVED="build/DerivedData"
PRODUCTS="$DERIVED/Build/Products"
OUT="build/duo-capture"

duo() { # the UDID of an iPhone Duo on the newest runtime, created if missing
  local udid
  udid=$(xcrun simctl list devices available --json | python3 -c '
import json, re, sys
found = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    match = re.search(r"\.iOS-(\d+(?:-\d+)*)$", runtime)
    for device in devices:
        if match and device["name"].startswith("iPhone Duo"):
            found.append((tuple(int(n) for n in match[1].split("-")), device["udid"]))
if found: print(sorted(found)[-1][1])')
  if [ -z "$udid" ]; then
    local runtime
    runtime=$(xcrun simctl list runtimes --json | python3 -c '
import json, sys
ios = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
print(sorted(ios, key=lambda r: [int(n) for n in r["version"].split(".")])[-1]["identifier"])')
    udid=$(xcrun simctl create "iPhone Duo Capture" "iPhone Duo" "$runtime")
  fi
  echo "$udid"
}

case "${1:-}" in
build)
  sim=$(duo) || exit 1
  scripts/fetch-nnue.sh >/dev/null || exit 1
  xcodebuild build-for-testing -project "$PROJECT" -scheme Motif -configuration Debug \
    -destination "platform=iOS Simulator,id=$sim" -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO -quiet || exit 1
  ls "$PRODUCTS"/*.xctestrun
  ;;
capture)
  pose="${2:?usage: $0 capture <O|IL|IP|FB|FT> <label> [app]}"
  label="${3:?usage: $0 capture <pose> <label> [app]}"
  app="${4:-}"
  dir="$OUT/$label"
  rm -rf "$dir" "$dir.xcresult"; mkdir -p "$dir"
  sim=$(duo) || exit 1
  export DUOCTL_UDID="$sim"
  xcrun simctl boot "$sim" 2>/dev/null || true
  xcrun simctl bootstatus "$sim" -b >/dev/null
  xcrun simctl ui "$sim" appearance light

  if [ -n "$app" ]; then
    # Same bundle ID, so the UI tests drive whichever app sits at the test target's path.
    target="$PRODUCTS/Debug-iphonesimulator/Motif.app"
    rm -rf "$target" && cp -R "$app" "$target" || exit 1
    xcrun simctl uninstall "$sim" com.dthedy.Motif 2>/dev/null || true
  fi

  case "$pose" in
    O)  duoctl close && duoctl rotate portrait ;;
    IL) duoctl open && duoctl rotate landscape ;;
    IP) duoctl open && duoctl rotate portrait ;;
    FB) duoctl half && duoctl rotate landscape ;;
    FT) duoctl half && duoctl rotate portrait ;;
    *) echo "Unknown pose $pose" >&2; exit 1 ;;
  esac || { echo "duoctl couldn't set pose $pose" >&2; exit 1; }
  sleep 2
  duoctl state > "$dir/pose-before.json" 2>&1

  xctestrun=$(ls "$PRODUCTS"/*.xctestrun | head -1)
  TEST_RUNNER_MOTIF_CAPTURE=1 TEST_RUNNER_MOTIF_CAPTURE_ONLY="${MOTIF_CAPTURE_ONLY:-}" \
    xcodebuild test-without-building -xctestrun "$xctestrun" \
      -destination "platform=iOS Simulator,id=$sim" \
      -only-testing:MotifUITests/DuoCaptureTests \
      -resultBundlePath "$dir.xcresult" > "$dir/xcodebuild.log" 2>&1
  status=$?
  grep -E "Test Case .*(passed|failed|skipped)|error:|\*\* TEST" "$dir/xcodebuild.log" | tail -40
  duoctl state > "$dir/pose-after.json" 2>&1

  # One PNG per state, named for its cell.
  raw="$dir/raw"; mkdir -p "$raw"
  xcrun xcresulttool export attachments --path "$dir.xcresult" --output-path "$raw" >/dev/null || exit 1
  python3 - "$raw" "$dir" <<'EOF'
import json, os, re, shutil, sys
raw, out = sys.argv[1], sys.argv[2]
count = 0
for test in json.load(open(os.path.join(raw, "manifest.json"))):
    for item in test.get("attachments", []):
        match = re.match(r"(S\d\d[a-z](?:-S\d\d)?)", item.get("suggestedHumanReadableName", ""))
        if match:
            shutil.copy(os.path.join(raw, item["exportedFileName"]), os.path.join(out, match[1] + ".png")); count += 1
print(f"{count} screenshots in {out}")
EOF
  rm -rf "$raw"
  # A state that couldn't be reached is still captured; the log says which.
  grep -E "error: .*DuoCaptureTests" "$dir/xcodebuild.log" > "$dir/failures.txt" || true
  echo "xcodebuild exited $status; $(wc -l < "$dir/failures.txt" | tr -d ' ') assertion failures (failures.txt)"
  ;;
*)
  sed -n 3,16p "$0"; exit 1 ;;
esac
