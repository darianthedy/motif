#!/usr/bin/env bash
# Build, sign and upload the iOS app to TestFlight from this Mac
# (replaces the old ios-testflight.yml GitHub workflow).
#
# Usage: scripts/ios-release/testflight.sh
#
# This is `bundle exec fastlane beta` plus the NNUE fetch and cleanup. The Fastfile
# loads its own config: signing from ~/.config/ios-signing/signing.env (shared by all
# apps, see ~/.config/ios-signing/README.md) and NEON_BASE_URL from the repo's
# git-ignored .env (VITE_NEON_BASE_URL). Build numbers are YYYYMMDDHHMM timestamps.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root/iOS/Motif"

# The lane switches the app target to manual signing by editing the pbxproj;
# undo that afterwards. Refuse to start if the pbxproj already has local edits,
# so restoring it can't throw away your work.
pbxproj=Motif.xcodeproj/project.pbxproj
if ! git diff --quiet HEAD -- "$pbxproj"; then
  echo "error: $pbxproj has uncommitted changes; commit or stash them first" >&2
  exit 1
fi
trap 'git checkout -- "$pbxproj"' EXIT

# The Stockfish nets the app bundles; the lane checks the IPA carries them.
"$root/scripts/fetch-nnue.sh"

export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
bundle install --quiet
bundle exec fastlane beta
