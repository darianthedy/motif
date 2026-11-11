#!/usr/bin/env bash
#
# Set every tracked file's mtime to the time of the last commit that touched it.
# A fresh checkout stamps everything "now", so Xcode would treat a cached
# DerivedData as stale and rebuild it all; with commit times an unchanged file
# keeps the mtime it had when the cache was built, and a changed one doesn't.
# Needs the full history (actions/checkout with fetch-depth: 0). Used by ios-ci.

set -euo pipefail
cd "$(dirname "$0")/.."

git log --pretty=format:@%ct --name-only HEAD | python3 -c '
import os, subprocess, sys
tracked = set(subprocess.run(["git", "ls-files", "-z"], capture_output=True, check=True)
              .stdout.decode().split("\0")) - {""}
seen, when = 0, None
for line in sys.stdin:
    line = line.rstrip("\n")
    if line.startswith("@"):
        when = int(line[1:])
    elif line in tracked:
        tracked.discard(line); seen += 1
        os.utime(line, (when, when))
print(f"== restored commit mtimes on {seen} files ({len(tracked)} left as checked out)")
'
