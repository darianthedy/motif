# Motif on this Mac

P01 creates the native project shell. Follow `Motif - iOS Build Prompts.md`
in order and apply §4 of `Motif - iOS Mac Mode.md`. These prompts can be
implemented directly in a coding session; the Claude-based driver is optional.

The project has synchronized source folders for `Motif`, `MotifTests`, and
`MotifUITests`. Adding source files inside them needs no project-file edits.
The shared `Motif` scheme runs the unit suite; UI flows are added in P12.

## Open and verify

Open `iOS/Motif/Motif.xcodeproj` in Xcode 26.1 or later. Select the `Motif`
scheme and an iPhone simulator with iOS 26.1 or newer.

From the repository root:

```sh
fnm use
npm ci
scripts/ios-verify.sh
scripts/ios-screenshot.sh p01-dark
APPEARANCE=light scripts/ios-screenshot.sh p01-light
```

`.node-version` selects the installed Node 24.12.0. Without shell integration,
use `fnm exec --using=24.12.0 scripts/ios-verify.sh`.

The simulator scripts select a device by UDID, prefer the selected Xcode SDK's
runtime, and accept `IOS_SIMULATOR_UDID` to select a particular iPhone. Build
products and screenshots are saved in the ignored `build/` directory.

## Configuration

`Config/Base.xcconfig` leaves `NEON_BASE_URL` empty and optionally includes
the ignored `Config/Local.xcconfig`. `AppConfig.neonBaseURL` is `nil` without
a configured endpoint. The app is a placeholder until the later slices port
the backend and screens.

For a real endpoint, create `iOS/Motif/Config/Local.xcconfig`:

```xcconfig
NEON_BASE_URL = https:/$()/example.neon.tech/neondb
```

Simulator builds disable signing. Device builds use automatic signing with
team `F73L2977Q8`; select your account and device in Xcode.

## P01 checkpoint

The project shell passes 192 web tests and 7 simulator configuration tests.
The dark and light placeholder screenshots were inspected. CI, fastlane, and
TestFlight setup remain W1 work, as specified by Mac Mode.

ChessKit is pinned to exactly 0.17.0 and linked to the app target. Its adapter
and parity tests arrive in P02; only `Model/Board.swift` may import ChessKit.
Required read-only package downloads are authorized for this workflow.
GitHub publishing and CI remain disabled.
