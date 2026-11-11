#!/usr/bin/env bash
#
# iPhone Duo screenshot tests (plan D09): put the iPhone Duo simulator in one pose
# (or boot an iPhone 17), run the capture suite (MotifUITests/DuoCaptureTests), and
# export its screenshots as build/duo-capture/<label>/<cell>.png. See
# "Motif - iOS iPhone Duo Plan.md" §8 and §9 (D09).
#
#   scripts/ios-duo-capture.sh build                    # build-for-testing with the selected Xcode
#   scripts/ios-duo-capture.sh capture <pose> <label> [app]
#   scripts/ios-duo-capture.sh pose <pose>              # boot a fresh Duo in the pose, for ios-ci
#
# Poses: O (closed), IL (open, wide), IP (open, tall), FB (half open, wide: book),
# FT (half open, tall: tabletop), and `iphone` (an iPhone 17, capture only). The hinge
# and rotation are set with duoctl, which drives the simulator through private
# interfaces (Xcode 27.1+). `app` replaces the app under test. MOTIF_CAPTURE_ONLY
# narrows the states (see DuoCaptureTests). The capture exits non-zero when a state
# wasn't reached (unreached.txt, apart from S12h: a drag can't be held) or a cell in
# an exact MOTIF_CAPTURE_ONLY list has no screenshot (missing.txt).
#
# Needs Xcode 27.1, the iOS 27.1 runtime and duoctl (brew install skarol/tap/duoctl).

set -uo pipefail
cd "$(dirname "$0")/.."

PROJECT="iOS/Motif/Motif.xcodeproj"
DERIVED="build/DerivedData"
PRODUCTS="$DERIVED/Build/Products"
OUT="build/duo-capture"

# The iPhone Duo runtime's identifier, newest first.
runtime() {
  xcrun simctl list runtimes --json | python3 -c '
import json, sys
ios = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]
       and any(d.get("name") == "iPhone Duo" for d in r.get("supportedDeviceTypes", []))]
print(sorted(ios, key=lambda r: [int(n) for n in r["version"].split(".")])[-1]["identifier"])'
}
# A capture device of our own, made fresh when asked: duoctl finds no active display on
# the runner image's preinstalled iPhone Duo, and a Duo left mid-fold needs recreating.
duo() {
  local udid
  udid=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["name"] == "Motif Duo Capture": print(device["udid"]); sys.exit()')
  if [ "${1:-}" = fresh ] && [ -n "$udid" ]; then xcrun simctl delete "$udid"; udid=""; fi
  [ -n "$udid" ] || udid=$(xcrun simctl create "Motif Duo Capture" "iPhone Duo" "$(runtime)")
  echo "$udid"
}

# A fresh capture device, booted and put in a pose; sets $sim and exports DUOCTL_UDID.
pose_duo() {
  local pose="$1" want steps attempt command list words
  sim=$(duo fresh) || return 1
  export DUOCTL_UDID="$sim"
  xcrun simctl boot "$sim" 2>/dev/null || true
  xcrun simctl bootstatus "$sim" -b >/dev/null
  xcrun simctl ui "$sim" appearance light
  # A display comes up a little after boot finishes; a boot that never shows one gets a reboot.
  ready() { for _ in $(seq 1 36); do duoctl state > /dev/null 2>&1 && return 0; sleep 5; done; return 1; }
  if ! ready; then
    echo "No active display after boot; rebooting the simulator" >&2
    xcrun simctl shutdown "$sim"; xcrun simctl boot "$sim"; xcrun simctl bootstatus "$sim" -b >/dev/null
    ready || { echo "No active display on the iPhone Duo simulator" >&2; return 1; }
  fi
  duoctl state

  # duoctl can briefly find no active display while the screens switch, so each
  # step is retried, and the pose is checked against what it should be.
  step() { for _ in 1 2 3 4 5; do duoctl "$@" > /dev/null 2>&1 && return 0; sleep 5; done; duoctl "$@"; }
  posed() { # hinge, screen, orientation
    duoctl state 2>/dev/null | python3 -c '
import json, sys
s = json.load(sys.stdin); hinge, screen, orientation = sys.argv[1:]
sys.exit(0 if abs(s["hingeAngle"] - float(hinge)) < 15 and s["activeScreen"] == screen and s["orientation"] == orientation else 1)' "$@"
  }
  case "$pose" in
    O)  want="0 cover portrait";     steps="close|rotate portrait" ;;
    IL) want="180 inner landscape";  steps="open|rotate landscape" ;;
    IP) want="180 inner portrait";   steps="open|rotate portrait" ;;
    # Rotate while open, then bend: bending first and rotating to portrait lands on the cover screen.
    FB) want="90 inner landscape";   steps="open|rotate landscape|half" ;;
    FT) want="90 inner portrait";    steps="open|rotate portrait|half" ;;
    *) echo "Unknown pose $pose" >&2; return 1 ;;
  esac
  for attempt in 1 2 3; do
    IFS='|' read -ra list <<< "$steps"
    for command in "${list[@]}"; do read -ra words <<< "$command"; step "${words[@]}"; done
    sleep 2
    # shellcheck disable=SC2086
    posed $want && break
    echo "Pose $pose not reached (attempt $attempt): $(duoctl state 2>&1 | tr -d '\n ')" >&2
    [ "$attempt" = 3 ] && { echo "duoctl couldn't set pose $pose" >&2; return 1; }
  done
  sleep 2
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
pose)
  # Leaves "Motif Duo Capture" booted in the pose, for ios-ci's IL destination
  # (MOTIF_SIM="Motif Duo Capture" scripts/ios-verify.sh).
  pose_duo "${2:?usage: $0 pose <O|IL|IP|FB|FT>}" || exit 1
  duoctl state
  ;;
capture)
  pose="${2:?usage: $0 capture <O|IL|IP|FB|FT|iphone> <label> [app]}"
  label="${3:?usage: $0 capture <pose> <label> [app]}"
  app="${4:-}"
  dir="$OUT/$label"
  rm -rf "$dir" "$dir.xcresult"; mkdir -p "$dir"
  if [ "$pose" = iphone ]; then
    # A clean iPhone 17: no duoctl; simctl takes the shots.
    sim=$(MOTIF_SIM="iPhone 17" scripts/ios-simulator.sh) || exit 1
    xcrun simctl shutdown "$sim" 2>/dev/null || true
    xcrun simctl erase "$sim" || exit 1
    xcrun simctl boot "$sim" || exit 1
    xcrun simctl bootstatus "$sim" -b >/dev/null
    xcrun simctl ui "$sim" appearance light
    shoot() { xcrun simctl io "$sim" screenshot "$1"; }
    state() { xcrun simctl list devices --json | python3 -c 'import json,sys; print(json.dumps([d for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["udid"]==sys.argv[1]]))' "$sim"; }
  else
    pose_duo "$pose" || exit 1
    shoot() { duoctl screenshot "$1"; }
    state() { duoctl state; }
  fi
  if [ -n "$app" ]; then
    # Same bundle ID, so the UI tests drive whichever app sits at the test target's path.
    target="$PRODUCTS/Debug-iphonesimulator/Motif.app"
    rm -rf "$target" && cp -R "$app" "$target" || exit 1
    xcrun simctl uninstall "$sim" com.dthedy.Motif 2>/dev/null || true
  fi

  state > "$dir/pose-before.json" 2>&1

  # The first shot after boot is slow; take it before the suite waits on one.
  abs="$(cd "$dir" && pwd)"
  for _ in 1 2 3; do shoot "$abs/.warmup.png" >/dev/null 2>&1 && break; sleep 3; done
  rm -f "$abs/.warmup.png"
  # The suite asks for each shot through $dir/request; duoctl (simctl on the iPhone) takes it
  # from the screen showing. A shot the suite gave up on (abandoned-<id>) is dropped, so a late
  # one never lands under an id while the next state is on screen.
  (
    while true; do
      if [ -f "$abs/request" ]; then
        id=$(cat "$abs/request"); rm -f "$abs/request"
        # A shot can hang (S01a, S01d, S05a waited out the suite's 90 s with no image), so
        # each try is cut off at 25 s: three tries still land inside the suite's wait.
        for try in 1 2 3; do
          sim="${sim:-}" perl -e 'alarm shift; exec @ARGV' 25 bash -c "$(declare -f shoot); shoot \"\$1\"" _ "$abs/$id.tmp.png" >/dev/null 2>&1 && break
          echo "shot $id: try $try failed or timed out" >&2
          rm -f "$abs/$id.tmp.png"; sleep 1
        done
        if [ -f "$abs/abandoned-$id" ]; then rm -f "$abs/$id.tmp.png"
        elif [ -f "$abs/$id.tmp.png" ]; then mv "$abs/$id.tmp.png" "$abs/$id.png"; fi
      fi
      sleep 0.2
    done
  ) &
  shooter=$!
  xctestrun=$(ls "$PRODUCTS"/*.xctestrun | head -1)
  TEST_RUNNER_MOTIF_CAPTURE_DIR="$abs" TEST_RUNNER_MOTIF_CAPTURE=1 TEST_RUNNER_MOTIF_CAPTURE_ONLY="${MOTIF_CAPTURE_ONLY:-}" \
  TEST_RUNNER_MOTIF_POSE="$pose" \
    xcodebuild test-without-building -xctestrun "$xctestrun" \
      -destination "platform=iOS Simulator,id=$sim" \
      -only-testing:MotifUITests/DuoCaptureTests \
      -resultBundlePath "$dir.xcresult" > "$dir/xcodebuild.log" 2>&1
  status=$?
  kill "$shooter" 2>/dev/null
  grep -E "Test Case .*(passed|failed|skipped)|error:|\*\* TEST" "$dir/xcodebuild.log" | tail -40
  state > "$dir/pose-after.json" 2>&1
  rm -f "$abs"/abandoned-* "$abs"/*.tmp.png

  # One PNG per state, named for its cell.
  raw="$dir/raw"; mkdir -p "$raw"
  xcrun xcresulttool export attachments --path "$dir.xcresult" --output-path "$raw" >/dev/null || exit 1
  python3 - "$raw" "$dir" <<'EOF'
import json, os, re, shutil, sys
raw, out = sys.argv[1], sys.argv[2]
count = 0
for test in json.load(open(os.path.join(raw, "manifest.json"))):
    for item in test.get("attachments", []):
        match = re.match(r"(S\d\d[a-z](?:-(?:S\d\d|sidebar))?)(?![-A-Za-z0-9])", item.get("suggestedHumanReadableName", ""))
        if match:
            target = os.path.join(out, match[1] + ".png")
            if not os.path.exists(target): shutil.copy(os.path.join(raw, item["exportedFileName"]), target); count += 1
print(f"{count} fallback screenshots from XCUIScreen; {len([f for f in os.listdir(out) if f.endswith('.png')])} in {out}")
EOF
  rm -rf "$raw"
  # A state that couldn't be reached is still captured; the log says which.
  grep -E "error: .*DuoCaptureTests" "$dir/xcodebuild.log" > "$dir/failures.txt" || true
  touch "$dir/unreached.txt"
  echo "xcodebuild exited $status; $(wc -l < "$dir/unreached.txt" | tr -d ' ') states not reached (unreached.txt)"
  # An exact list of cells (the workflow's drawn cells) must all be captured.
  : > "$dir/missing.txt"
  IFS=',' read -ra cells <<< "${MOTIF_CAPTURE_ONLY:-}"
  for cell in "${cells[@]}"; do
    [[ "$cell" =~ ^S[0-9][0-9][a-z](-[A-Za-z0-9]+)?$ ]] || { : > "$dir/missing.txt"; break; }
    [ -f "$dir/$cell.png" ] || echo "$cell" >> "$dir/missing.txt"
  done
  # S12h can't hold its drag; every other state must be reached (D09).
  blocking=$(grep -v '^S12h' "$dir/unreached.txt" || true)
  failed=0
  if [ -n "$blocking" ]; then echo "Not reached:"; echo "$blocking"; failed=1; fi
  if [ -s "$dir/missing.txt" ]; then echo "No screenshot:"; cat "$dir/missing.txt"; failed=1; fi
  if [ "$status" != 0 ] && [ "$failed" = 0 ]; then echo "xcodebuild failed with every state reached; see xcodebuild.log"; failed=1; fi
  exit "$failed"
  ;;
*)
  sed -n 3,17p "$0"; exit 1 ;;
esac
