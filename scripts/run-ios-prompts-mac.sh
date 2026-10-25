#!/usr/bin/env bash
#
# run-ios-prompts-mac.sh — build the iOS prompts (P01..P12) locally on a Mac.
#
# Mac mode ("Motif - iOS Mac Mode.md"): no GitHub, no CI. For each prompt:
#   1. branch ios/Pxx off the local trunk `main-mac`;
#   2. a FRESH `claude -p` session implements the slice, with the Mac-mode
#      override appended (verify locally, screenshot UI, never push);
#   3. this driver runs scripts/ios-verify.sh itself. Red => a fresh fix session
#      on the same branch with the log tail, up to MAX_FIX_ATTEMPTS; still red
#      => stop and leave the branch for a human;
#   4. green => merge --no-ff into main-mac and write a backup bundle.
#
#   scripts/run-ios-prompts-mac.sh          # from P01
#   scripts/run-ios-prompts-mac.sh P05      # restart at P05
#
# Written for macOS's bash 3.2 and BSD tools: no associative arrays, no
# `date -d`, no /proc.

set -euo pipefail
cd "$(dirname "$0")/.."

# --- config -----------------------------------------------------------------
DOC="Motif - iOS Build Prompts.md"
MAC_DOC="Motif - iOS Mac Mode.md"
TRUNK="main-mac"
PROMPTS="P01 P02 P03 P04 P05 P06 P07 P08 P09 P10 P11 P12"
MAX_FIX_ATTEMPTS=3
BACKUPS="$HOME/motif-backups"
CLAUDE_FLAGS="--dangerously-skip-permissions"
START_AT="${1:-P01}"

# --- helpers ----------------------------------------------------------------
log() { printf '\n\033[1;36m[%s] %s\033[0m\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '\n\033[1;31mSTOP: %s\033[0m\n' "$*" >&2; exit 1; }

mkdir -p "$BACKUPS/logs"

# Live-format Claude's stream-json into readable lines (assistant text + each
# tool call), so a long session isn't a silent black box.
read -r -d '' STREAM_FMT <<'PYEOF' || true
import sys, json
for line in iter(sys.stdin.readline, ""):
    line = line.strip()
    if not line:
        continue
    try:
        ev = json.loads(line)
    except Exception:
        print(line, flush=True); continue
    t = ev.get("type")
    if t == "system" and ev.get("subtype") == "init":
        print("  > session started (model %s)" % ev.get("model", "?"), flush=True)
    elif t == "assistant":
        for b in ev.get("message", {}).get("content", []):
            if b.get("type") == "text" and b.get("text", "").strip():
                print(b["text"].rstrip(), flush=True)
            elif b.get("type") == "tool_use":
                inp = b.get("input", {}) or {}
                hint = str(inp.get("command") or inp.get("file_path") or inp.get("description") or "").replace("\n", " ")
                print("  * %s: %s" % (b.get("name", "?"), hint[:100]), flush=True)
    elif t == "result":
        print("  ! result error: %s" % str(ev.get("result", ""))[:200] if ev.get("is_error") else "  = session done", flush=True)
PYEOF

# The override every session gets: §4 of the Mac Mode doc, quoted there in full.
OVERRIDE="Mac mode: read section 4 of \"$MAC_DOC\" and follow it — it overrides the \
prompt's CI instructions. Never run git push, gh, or anything that contacts GitHub. \
Verify with scripts/ios-verify.sh until it exits 0; for UI slices also screenshot \
each touched screen with scripts/ios-screenshot.sh and look at the images. \
Commit all changes with a clear message when finished. Do not push."

# $1 = prompt text, $2 = log file. Exit status ignored on purpose: the gate is
# "did it commit, and does verify pass", checked by the caller.
run_claude() {
  # < /dev/null: with a piped stdout, claude -p would otherwise wait on stdin.
  claude -p "$1" $CLAUDE_FLAGS --output-format stream-json --verbose < /dev/null \
    | python3 -u -c "$STREAM_FMT" | tee -a "$2" || true
}

verify() {  # $1 = log file
  log "Verifying (scripts/ios-verify.sh) …"
  scripts/ios-verify.sh > "$1.verify" 2>&1
}

# --- preflight --------------------------------------------------------------
command -v claude >/dev/null  || die "claude CLI not found"
command -v xcodebuild >/dev/null || die "Xcode not found"
command -v npm >/dev/null     || die "npm not found"
[ -z "$(git status --porcelain)" ] || die "working tree not clean"
git rev-parse --verify "$TRUNK" >/dev/null 2>&1 || die "no $TRUNK branch — see §2.5 of \"$MAC_DOC\""
# Belt and braces: make an accidental push fail rather than publish.
git config remote.origin.pushurl "DISABLED-in-mac-mode" 2>/dev/null || true

# --- main loop --------------------------------------------------------------
started=0
for P in $PROMPTS; do
  [ "$P" = "$START_AT" ] && started=1
  [ "$started" = 1 ] || { log "skip $P (starting at $START_AT)"; continue; }

  branch="ios/$P"
  logf="$BACKUPS/logs/$P.log"
  : > "$logf"

  log "=== $P : implementing ==="
  git switch "$TRUNK" >/dev/null
  git branch -D "$branch" >/dev/null 2>&1 || true
  git switch -c "$branch" >/dev/null
  base=$(git rev-parse HEAD)

  run_claude "In this repo, read \"$DOC\", find prompt $P, and follow its **Run** line — \
read the §refs it cites and implement ONLY the $P slice, no more, no less. The TypeScript \
in src/ is the spec; port it, don't redesign it. $OVERRIDE" "$logf"

  [ "$(git rev-parse HEAD)" != "$base" ] || die "$P produced no commits (log: $logf)"
  [ -z "$(git status --porcelain)" ] || { git add -A && git commit -qm "$P: uncommitted leftovers"; }

  attempt=0
  until verify "$logf"; do
    attempt=$((attempt+1))
    [ "$attempt" -le "$MAX_FIX_ATTEMPTS" ] || die "$P still fails verify after $MAX_FIX_ATTEMPTS fixes — branch $branch left as is (log: $logf.verify)"
    log "=== $P : verify FAILED — fix attempt $attempt ==="
    before=$(git rev-parse HEAD)
    run_claude "You are on branch $branch, which implements prompt $P of \"$DOC\". \
scripts/ios-verify.sh FAILED. Read that prompt for the intended scope, then fix the failure \
below — fix the cause; never weaken, skip or delete a ported test to get past it. \
$OVERRIDE

--- failing scripts/ios-verify.sh output (tail) ---
$(tail -150 "$logf.verify")" "$logf"
    [ "$(git rev-parse HEAD)" != "$before" ] || [ -n "$(git status --porcelain)" ] || die "$P fix attempt $attempt changed nothing"
    [ -z "$(git status --porcelain)" ] || { git add -A && git commit -qm "$P: fix verify (attempt $attempt)"; }
  done

  git switch "$TRUNK" >/dev/null
  git merge --no-ff -q -m "Merge $branch" "$branch"
  git branch -d "$branch" >/dev/null
  git bundle create "$BACKUPS/motif-$P.bundle" "$TRUNK" >/dev/null 2>&1
  log "=== $P : GREEN, merged into $TRUNK, backup at $BACKUPS/motif-$P.bundle ==="
done

log "All prompts complete. Next: §5 of \"$MAC_DOC\" — bundle $TRUNK and bring it to WSL."
