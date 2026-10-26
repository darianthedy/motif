# Motif — iOS Mac Mode

> How to build the iOS app on a **borrowed Mac, locally only**: no pushes to
> GitHub, no CI, no TestFlight. The Mac exists to turn P01–P12 of
> `Motif - iOS Build Prompts.md` into a working app as fast as possible, with
> every slice compiled, tested and screenshotted on the Mac itself. Polishing
> and publishing happen afterwards in WSL, as the rest of the plan describes.
>
> This document **overrides** the Build Prompts' CI instructions while on the
> Mac. Everything else — the Tech Plan, the rules in §0, each slice's scope —
> stays as written.

---

## 1. The shape of it

```
WSL                         Mac (temporary)                         WSL
───                         ───────────────                         ───
commit plan docs   ──►  clone, set up  ──►  P01…P12 locally   ──►  git bundle
                                            (build + test +         │
                                             screenshot each)       ▼
                                                               fetch bundle → review
                                                               → W1 pipeline (CI + fastlane)
                                                               → push → ios-ci → TestFlight
                                                               → polish via TestFlight
```

- **Nothing leaves the Mac except through a git bundle.** No `git push`, no
  `gh`, no PRs. Each slice is a local branch merged locally into `main`.
- **CI files are not written on the Mac.** The pipeline (`ios-ci.yml`,
  `ios-testflight.yml`, fastlane, `README-TestFlight.md`) moves out of P01
  into a WSL step, **W1** (§6), so nothing lands untested.
- **The Mac verifies every slice itself**: `scripts/ios-verify.sh` (`npm test`
  + `xcodebuild test` on a simulator) must pass before a slice merges, and UI
  slices also check simulator screenshots.

---

## 2. Setup

### 2.1 Before you get the Mac (in WSL)

1. Commit the plan (`Motif - Tech Plan - iOS.md`, `Motif - iOS Build Prompts.md`,
   this file, `scripts/ios-*.sh`, `scripts/run-ios-prompts-mac.sh`) on a branch
   and get it onto the Mac — either push that one branch from WSL (simplest; it
   is only docs and scripts) or `git bundle create motif.bundle --all` and copy
   the file over.
2. Have ready: your Apple ID for the developer team (`F73L2977Q8`), your
   Claude login, and the Neon base URL from `.env` (only if you want the app to
   talk to the real database on the Mac — §2.4).

### 2.2 The Mac

| What | Why / notes |
|---|---|
| **Apple Silicon**, macOS that the current **Xcode 26.x** supports (Sequoia 15.6 or later — check the App Store listing) | Deployment target is iOS 26.1, which needs Xcode 26.1+. Intel works but simulators are slow. |
| **~60 GB free disk** | Xcode (~15 GB), iOS 26 simulator runtime (~8 GB), DerivedData, Node modules. |
| **Xcode** from the App Store, opened once | Accept the licence, let it install components. Then `sudo xcode-select -s /Applications/Xcode.app` and `xcodebuild -runFirstLaunch`. |
| **iOS 26 simulator runtime** | Xcode → Settings → Components, or `xcodebuild -downloadPlatform iOS`. Check: `xcrun simctl list devices available \| grep iPhone`. |
| **Homebrew** | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| **Node 24 + npm** | `brew install node@24` — the fixture exporter and `npm test` (P02 onward) run on the Mac too. |
| **git** | Comes with Xcode's command-line tools. |
| **python3** | Comes with the command-line tools; the driver's log formatter uses it. |
| **Claude Code** | `npm install -g @anthropic-ai/claude-code`, then `claude` once to log in. |
| *(optional)* `xcbeautify` | `brew install xcbeautify` — shorter, readable build logs; `ios-verify.sh` uses it when present. |

**Not needed on the Mac:** `gh`, Ruby, fastlane, any GitHub secrets, the
App Store Connect API key, the match repo. Those are for publishing, in WSL.

### 2.3 Signing for the simulator and your iPhone

- **Simulator**: no signing needed. Everything in §4 runs on the simulator.
- **Your iPhone** (to try the board's feel and haptics during the run):
  1. Xcode → Settings → Accounts → **+** → sign in with your Apple ID; the team
     `F73L2977Q8` appears.
  2. The project's **Debug** configuration uses **automatic signing** with
     `DEVELOPMENT_TEAM = F73L2977Q8` (P01 sets this). Xcode creates a
     *development* certificate on this Mac and registers your iPhone. It does
     **not** touch the *distribution* certificate that fastlane match keeps in
     `ios-certificates` — publishing is unaffected.
  3. iPhone: connect by cable once, tap **Trust**, then Settings → Privacy &
     Security → **Developer Mode** → on (it restarts).
  4. Open `iOS/Motif/Motif.xcodeproj`, pick your iPhone, **Run** (⌘R). After
     the first cable run you can enable Wi-Fi debugging in Xcode → Devices.

### 2.4 Pointing the app at the real database (optional)

By default (no URL) the app uses the in-memory dev backend — any email and
password signs in, as `npm run dev` does on the web. Tests and screenshots
always use it. To try the real account on the Mac or your phone:

```
echo 'NEON_BASE_URL = https:/$()/<endpoint>.<region>.aws.neon.tech/neondb' > iOS/Motif/Config/Local.xcconfig
```

`Local.xcconfig` is git-ignored and pulled in by `Config/Base.xcconfig` with
`#include? "Local.xcconfig"` (P01 creates both). The `/$()/` is not a typo:
xcconfig treats `//` as the start of a comment, and an empty `$()` between the
slashes is the standard way round it.

### 2.5 Clone and smoke-test

```
git clone https://github.com/darianthedy/motif.git && cd motif   # or: git clone motif.bundle motif
git switch <plan-branch> && git switch -c main-mac                # see §3: main-mac is the Mac's trunk
npm ci && npm test                                                # the web suite must pass here first
xcrun simctl list devices available | grep iPhone                 # at least one iPhone simulator
claude --version
```

---

## 3. Running it

```
scripts/run-ios-prompts-mac.sh          # P01…P12
scripts/run-ios-prompts-mac.sh P05      # restart at P05
```

The UI refresh slices (U01–U10 of `Motif - iOS UI Refresh Plan.md`) run through
the same driver with `scripts/run-ios-ui-prompts-mac.sh`; §8 of that plan has
the differences.

For each prompt the driver:

1. branches `ios/Pxx` off the trunk `main-mac`;
2. runs a fresh `claude -p` session with the prompt's **Run** line plus the
   **Mac-mode override** (§4);
3. runs `scripts/ios-verify.sh` itself — it trusts the result, not the
   session's report;
4. red → a fresh fix session on the same branch with the failing log tail
   (up to 3 times); still red → stops, leaving the branch for you;
5. green → merges into `main-mac` with `--no-ff`, deletes the branch, and
   writes a backup bundle to `~/motif-backups/motif-<Pxx>.bundle`.

`main-mac` rather than `main`: the Mac's trunk never pretends to be GitHub's
`main`, so bringing it back (§5) is an explicit merge. The driver also sets
`remote.origin.pushurl` to an invalid value in the clone, so an accidental
`git push` fails instead of publishing.

Logs go to `~/motif-backups/logs/<Pxx>.log`. Keep the terminal alive (tmux)
and the Mac awake (`caffeinate -dimsu` in another tab).

Sessions run with `--dangerously-skip-permissions`, as in Financial
Management's driver. On a borrowed machine, keep nothing else of yours on it
(§7).

---

## 4. Mac-mode override (appended to every prompt by the driver)

> **Mac mode.** You are on a Mac with Xcode, building locally. **Never run
> `git push`, `gh`, or anything that contacts GitHub.** Ignore the prompt's
> instructions to push or wait for `ios-ci`; instead:
>
> - Verify with `scripts/ios-verify.sh` (runs `npm test` and `xcodebuild test`
>   on an iPhone simulator). The slice is done only when it exits 0. Iterate
>   locally until it does.
> - For any slice that adds or changes UI (P06–P12), also run
>   `scripts/ios-screenshot.sh <name> [launch args…]` for each screen you
>   touched, **look at the PNGs** (read them), and fix what is visibly wrong:
>   clipped text, overlapping views, wrong colours in dark and light mode,
>   anything that doesn't match the web screen's behaviour.
> - **P01 in Mac mode** builds only the project shell (`Motif.xcodeproj`, scheme,
>   app, test targets, `Config/Base.xcconfig` with `#include? "Local.xcconfig"`
>   and Debug automatic signing on team `F73L2977Q8`) and makes
>   `scripts/ios-verify.sh` and `scripts/ios-screenshot.sh` work. **Skip** the
>   workflows, fastlane, Gemfile and `README-TestFlight.md` — those are step W1,
>   done later in WSL.
> - **P06 in Mac mode** also adds the Debug-only screenshot hooks
>   (`-MotifSeedSamples YES` loads `samples/*.json` into the memory backend;
>   `-MotifRoute <route>` opens a screen directly, e.g. `session:all`,
>   `game:<first>`), so later slices can screenshot any screen without tapping.
>
> When finished, commit all changes with a clear message. Do not push.

---

## 5. Leaving the Mac — bringing the work to WSL

On the Mac, after P12 is green:

```
git bundle create ~/motif-ios.bundle main-mac
git bundle verify ~/motif-ios.bundle
```

Copy `motif-ios.bundle` to WSL (USB stick, cloud drive, `scp`). Then in WSL:

```
cd ~/projects/motif
git fetch ~/motif-ios.bundle main-mac:ios-mac
git log --oneline main..ios-mac        # review what came back
```

Keep a copy of the latest `~/motif-backups/*.bundle` too, in case the final
one is missing a step.

---

## 6. Back in WSL

1. **W1 — Pipeline.** A session on `ios-mac` does the part of P01 that Mac mode
   skipped: `ios-ci.yml`, `ios-testflight.yml`, `Gemfile`, `fastlane/*`,
   `iOS/README-TestFlight.md` (Tech Plan §14). Fastlane flips signing to manual
   / Apple Distribution at CI time, as in Financial Management, so the Debug
   automatic-signing settings from the Mac stay.
2. Push `ios-mac`, open a PR, get `ios-ci` green (the first CI run of code that
   was only ever built on the Mac — expect small fixes, e.g. a simulator name).
3. Do the one-time setup (Tech Plan §14.3), merge, and let `ios-testflight`
   upload. Expect about an hour of first-time signing fixes for the new bundle
   ID; Financial Management's gotchas are already built in.
4. Polish from WSL through TestFlight, as the original plan describes.

---

## 7. Before you hand the Mac back

- Bundle created, copied off, and fetched into WSL (§5) — check `git log` in
  WSL shows P12 before deleting anything.
- Delete the clone and `~/motif-backups`.
- `claude` → `/logout`; remove `~/.claude`.
- Xcode → Settings → Accounts → remove your Apple ID. In Keychain Access,
  delete the "Apple Development" certificate and its private key; optionally
  revoke it at developer.apple.com → Certificates.
- `xcrun simctl erase all` (simulators hold the dev backend's data and, if you
  used §2.4, a Neon session cookie).
- Delete `iOS/Motif/Config/Local.xcconfig` if you made one (goes with the clone).
- On your iPhone the dev build keeps working until its profile expires; delete
  it once TestFlight builds arrive.
