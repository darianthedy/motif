#!/usr/bin/env python3
"""iPhone Duo screenshot tests (D09): the screenshot coverage grid for the plan's §8.

    scripts/duo-capture-grid.py <captures dir> [device dir]

<captures dir> holds the downloaded `capture-<pose>` artifacts (each with a `<pose>/`
folder of `<cell>.png`, `unreached.txt`, `pose-before.json`), for the poses O, IL, IP,
FB, FT and iphone. [device dir] holds the device shots named `<config>-<cell>.png` (SVL, SVR).
Prints a markdown table: one row per state, one column per pose.
✓ captured · ✗ captured but the state wasn't reached · – not captured (not drawn in that pose).
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SUITE = os.path.join(HERE, "..", "iOS", "Motif", "MotifUITests", "DuoCaptureTests.swift")
POSES = ["O", "IL", "IP", "FB", "FT", "iphone"]


def states():
    text = open(SUITE).read()
    ids = re.findall(r'shot\("(S\d\d[a-z](?:-sidebar)?)"', text)
    # S17 is drawn on three hosts: shot("S17a-" + host, ...)
    banners = re.findall(r'shot\("(S17[a-z])-" \+ host', text)
    hosts = re.findall(r'\("(S\d\d)", (?:nil|"[^"]*"), \{', text)
    ids += [f"{b}-{h}" for b in banners for h in hosts]
    return ids


def captured(root, pose):
    folder = os.path.join(root, f"capture-{pose}", pose)
    if not os.path.isdir(folder):
        return None
    shots = {f[:-4] for f in os.listdir(folder) if f.endswith(".png")}
    missed = set()
    path = os.path.join(folder, "unreached.txt")
    if os.path.exists(path):
        missed = {line.split("\t")[0] for line in open(path) if line.strip()}
    pose_file = os.path.join(folder, "pose-before.json")
    state = json.load(open(pose_file)) if os.path.exists(pose_file) else {}
    return shots, missed, state


def main():
    root = sys.argv[1]
    device = sys.argv[2] if len(sys.argv) > 2 else None
    ids = states()
    columns = POSES
    data = {column: captured(root, column) for column in columns}
    sv = set()
    if device and os.path.isdir(device):
        sv = {f[4:-4] for f in os.listdir(device) if re.match(r"SV[LR]-", f)}

    header = ["State"] + columns + ["SV device"]
    print("| " + " | ".join(header) + " |")
    print("|" + "---|" * len(header))
    totals = {column: [0, 0] for column in columns}
    for state in ids:
        row = [state]
        for column in columns:
            found = data[column]
            if found is None:
                row.append("?"); continue
            shots, missed, _ = found
            if state not in shots:
                row.append("–")
            elif state in missed:
                row.append("✗"); totals[column][1] += 1
            else:
                row.append("✓"); totals[column][0] += 1
        cell = state.split("-")[0]
        row.append("✓" if cell in sv and "-" not in state else "–")
        print("| " + " | ".join(row) + " |")
    print()
    for column in columns:
        found = data[column]
        pose = found[2] if found else {}
        print(f"- **{column}**: {totals[column][0]} reached, {totals[column][1]} not reached; "
              f"pose {pose.get('hingeAngle', '?')}°, {pose.get('activeScreen', '?')} screen, "
              f"{pose.get('orientation', '?')}, {pose.get('sizePoints', '?')} pt")
    print(f"- **SV device**: {len(sv)} cells, both halves")


if __name__ == "__main__":
    main()
