#!/usr/bin/env bash
#
# Print an available iPhone simulator UDID. Prefer the selected Xcode's SDK
# runtime; names alone are ambiguous when multiple iOS runtimes are installed.
# IOS_SIMULATOR_UDID may select a particular available iPhone explicitly.
# MOTIF_SIM picks a simulator by name or UDID (any device, e.g. "iPhone 17" or the
# capture script's "Motif Duo Capture"), or by a name prefix when no name matches
# exactly ("iPad Pro 11-inch" finds "iPad Pro 11-inch (M5)"); MOTIF_RUNTIME (e.g. 26) prefers that iOS
# major version over the SDK's own. The choice is logged to stderr.

set -euo pipefail

sdk=$(xcrun --sdk iphonesimulator --show-sdk-version)
# Runtime versions come from simctl's runtime list; the identifier's spelling is only a
# fallback, since not every runtime's identifier ends in its version (ios-ci's IL
# destination found no "Motif Duo Capture" by identifier alone).
runtimes=$(xcrun simctl list runtimes --json)
xcrun simctl list devices available --json | python3 -c '
import json, os, re, sys

versions = {r["identifier"]: r["version"] for r in json.loads(sys.argv[2])["runtimes"]
            if r.get("platform", "iOS") == "iOS" and r.get("version")}
preferred = "com.apple.CoreSimulator.SimRuntime.iOS-" + sys.argv[1].replace(".", "-")
requested = os.environ.get("IOS_SIMULATOR_UDID")
named = os.environ.get("MOTIF_SIM")
major = os.environ.get("MOTIF_RUNTIME")
candidates = []
listed = json.load(sys.stdin)["devices"]
for runtime, devices in listed.items():
    match = re.search(r"\.iOS-(\d+(?:-\d+)*)$", runtime)
    if runtime in versions:
        version = tuple(int(part) for part in re.findall(r"\d+", versions[runtime]))
    elif match:
        version = tuple(int(part) for part in match[1].split("-"))
    else:
        continue
    if version < (26, 1):
        continue
    for device in devices:
        # The list is already filtered to available devices.
        if not device.get("isAvailable", True):
            continue
        exact = not named or named in (device["name"], device["udid"])
        if named:
            if not exact and not device["name"].startswith(named):
                continue
        elif not device["name"].startswith("iPhone"):
            continue
        candidates.append((exact, bool(major) and str(version[0]) == major, runtime == preferred, version, device))
if requested:
    candidates = [item for item in candidates if item[4]["udid"] == requested]
if not candidates:
    print("No available simulator with iOS 26.1 or newer" + (" named " + named if named else "") + ". "
          "Install an iOS runtime in Xcode Settings > Components, "
          "or check IOS_SIMULATOR_UDID / MOTIF_SIM.", file=sys.stderr)
    for runtime, devices in listed.items():
        for device in devices:
            if named and (named in (device["name"], device["udid"]) or device["name"].startswith(named)):
                print("  seen on %s (version %s): %s" % (runtime, versions.get(runtime, "unknown"), device), file=sys.stderr)
    sys.exit(1)
candidates.sort(key=lambda item: (item[0], item[1], item[2], item[3]), reverse=True)
device, version = candidates[0][4], candidates[0][3]
print("%s on iOS %s (%s)" % (device["name"], ".".join(map(str, version)), device["udid"]), file=sys.stderr)
print(device["udid"])
' "$sdk" "$runtimes"
