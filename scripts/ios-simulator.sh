#!/usr/bin/env bash
#
# Print an available iPhone simulator UDID. Prefer the selected Xcode's SDK
# runtime; names alone are ambiguous when multiple iOS runtimes are installed.
# IOS_SIMULATOR_UDID may select a particular available iPhone explicitly.
# MOTIF_SIM picks a simulator by name or UDID (any device, e.g. "iPhone 17" or the
# capture script's "Motif Duo Capture"); MOTIF_RUNTIME (e.g. 26) prefers that iOS
# major version over the SDK's own. The choice is logged to stderr.

set -euo pipefail

sdk=$(xcrun --sdk iphonesimulator --show-sdk-version)
xcrun simctl list devices available --json | python3 -c '
import json, os, re, sys

preferred = "com.apple.CoreSimulator.SimRuntime.iOS-" + sys.argv[1].replace(".", "-")
requested = os.environ.get("IOS_SIMULATOR_UDID")
named = os.environ.get("MOTIF_SIM")
major = os.environ.get("MOTIF_RUNTIME")
candidates = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    match = re.search(r"\.iOS-(\d+(?:-\d+)*)$", runtime)
    if not match:
        continue
    version = tuple(int(part) for part in match[1].split("-"))
    if version < (26, 1):
        continue
    for device in devices:
        if not device.get("isAvailable"):
            continue
        if named:
            if named not in (device["name"], device["udid"]):
                continue
        elif not device["name"].startswith("iPhone"):
            continue
        candidates.append((bool(major) and str(version[0]) == major, runtime == preferred, version, device))
if requested:
    candidates = [item for item in candidates if item[3]["udid"] == requested]
if not candidates:
    print("No available iPhone simulator with iOS 26.1 or newer" + (" named " + named if named else "") + ". "
          "Install an iOS runtime in Xcode Settings > Components, "
          "or check IOS_SIMULATOR_UDID / MOTIF_SIM.", file=sys.stderr)
    sys.exit(1)
candidates.sort(key=lambda item: (item[0], item[1], item[2]), reverse=True)
device, version = candidates[0][3], candidates[0][2]
print("%s on iOS %s (%s)" % (device["name"], ".".join(map(str, version)), device["udid"]), file=sys.stderr)
print(device["udid"])
' "$sdk"
