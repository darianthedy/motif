#!/usr/bin/env bash
#
# Print an available iPhone simulator UDID. Prefer the selected Xcode's SDK
# runtime; names alone are ambiguous when multiple iOS runtimes are installed.
# IOS_SIMULATOR_UDID may select a particular available iPhone explicitly.

set -euo pipefail

sdk=$(xcrun --sdk iphonesimulator --show-sdk-version)
xcrun simctl list devices available --json | python3 -c '
import json, os, re, sys

preferred = "com.apple.CoreSimulator.SimRuntime.iOS-" + sys.argv[1].replace(".", "-")
requested = os.environ.get("IOS_SIMULATOR_UDID")
candidates = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    match = re.search(r"\.iOS-(\d+(?:-\d+)*)$", runtime)
    if not match:
        continue
    version = tuple(int(part) for part in match[1].split("-"))
    if version < (26, 1):
        continue
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            candidates.append((runtime == preferred, version, device))
if requested:
    candidates = [item for item in candidates if item[2]["udid"] == requested]
if not candidates:
    print("No available iPhone simulator with iOS 26.1 or newer. "
          "Install an iOS runtime in Xcode Settings > Components, "
          "or check IOS_SIMULATOR_UDID.", file=sys.stderr)
    sys.exit(1)
candidates.sort(key=lambda item: (item[0], item[1]), reverse=True)
print(candidates[0][2]["udid"])
' "$sdk"
