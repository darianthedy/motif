#!/usr/bin/env bash
#
# run-ios-prompts.sh — drive the iOS build prompts (P01..P12) sequentially.
#
# Adapted from financial-management's driver. For each prompt:
#   1. a FRESH `claude -p` session implements that one slice on a branch;
#   2. the branch is pushed and a PR opened, and we wait for the `ios-ci` check
#      (simulator build + XCTest). Red => a fresh session fixes it ON THE SAME
#      branch from the failing log, and we wait again (bounded by
#      MAX_FIX_ATTEMPTS). There is no Mac, so this check is the compiler;
#   3. green => merge to `main`, then wait for the `iOS TestFlight` run that the
#      merge triggers. Red there => a fix branch, as in financial-management.
#      Set SKIP_TESTFLIGHT=1 until the one-time signing setup is done
#      (Motif - Tech Plan - iOS.md §14.3), since that run cannot pass before.
#
# WHY one session per prompt: the prompts doc requires it — a cold session
# re-reads the plan and keeps context tight; chaining slices in one session
# degrades quality.
#
# RUN THIS FROM A CLEAN, DEDICATED CHECKOUT ON `main` — NOT from a worktree you
# care about (it switches branches). Suggested:
#   git clone <repo> motif-pipeline && cd motif-pipeline && scripts/run-ios-prompts.sh
#
# Requires: claude CLI, gh (authed), git. macOS is NOT needed locally — the
# build happens on the GitHub macOS runner.
#
# Unattended-friendly: each slice auto-cleans a stale branch first, and if a
# session is aborted by the Claude usage limit the driver sleeps until the
# 5-hour window resets, then RESUMES that same Claude session (--resume) so it
# continues where it left off. Keep the terminal alive (e.g. tmux/nohup) since
# the wait can be hours. To restart at a given prompt:
# `scripts/run-ios-prompts.sh P05`.

set -euo pipefail

# --- config -----------------------------------------------------------------
# DOC, PROMPT_IDS, BRANCH_PREFIX and SPEC_RULE can be overridden from the
# environment so other prompt docs (e.g. the UI refresh) reuse this driver.
DOC="${DOC:-Motif - iOS Build Prompts.md}"
CI_WORKFLOW="ios-ci.yml"
WORKFLOW="ios-testflight.yml"
read -r -a PROMPTS <<< "${PROMPT_IDS:-P01 P02 P03 P04 P05 P06 P07 P08 P09 P10 P11 P12}"
BRANCH_PREFIX="${BRANCH_PREFIX:-ios/}"
SPEC_RULE="${SPEC_RULE:-The TypeScript in src/ is the spec; port it, do not redesign it.}"
MAX_FIX_ATTEMPTS=3
SKIP_TESTFLIGHT="${SKIP_TESTFLIGHT:-0}"
# Headless permissions. Sessions edit files + run git; for unattended runs this
# is the practical choice. Drop to --permission-mode acceptEdits to babysit.
CLAUDE_FLAGS=(--dangerously-skip-permissions)
START_AT="${1:-${PROMPTS[0]}}"   # optional: resume, e.g. `scripts/run-ios-prompts.sh P05`
# Before each slice, probe the Claude usage tier; if it isn't "allowed" (i.e.
# already at/near the limit) wait for the 5-hour reset instead of starting — so
# we don't burn a slice that would abort partway. Set 0 to disable.
# NOTE: the headless CLI exposes only a status tier + resetsAt, not a numeric %,
# so this fires on Claude's own near/at-limit signal, not a settable 90% line.
PREFLIGHT_USAGE_GATE="${PREFLIGHT_USAGE_GATE:-1}"

# --- helpers ----------------------------------------------------------------
log() { printf '\n\033[1;36m[%s] %s\033[0m\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '\n\033[1;31mABORT: %s\033[0m\n' "$*" >&2; exit 1; }
trap '[ -n "${RAW_LOG:-}" ] && rm -f "$RAW_LOG" 2>/dev/null' EXIT

# Live-format Claude's stream-json events into readable lines, so a long session
# isn't a silent black box: prints assistant text + each tool call as it happens.
# No jq needed; falls back to raw passthrough if python3 is missing.
read -r -d '' STREAM_FMT <<'PYEOF' || true
import sys, json, os
def out(s):
    print(s); sys.stdout.flush()
# Keep a raw copy of the stream so the driver can tell a usage-limit abort
# (wait + retry) from a genuine failure (stop).
_raw = open(os.environ["RAW_LOG"], "a", encoding="utf-8") if os.environ.get("RAW_LOG") else None
for line in iter(sys.stdin.readline, ""):   # readline (not "for line in stdin") => no read-ahead buffering
    line = line.strip()
    if not line:
        continue
    if _raw:
        _raw.write(line + "\n"); _raw.flush()
    try:
        ev = json.loads(line)
    except Exception:
        out(line); continue
    t = ev.get("type")
    if t == "system" and ev.get("subtype") == "init":
        out("  ▶ session started (model %s, perms %s)"
            % (ev.get("model", "?"), ev.get("permissionMode", "?")))
    elif t == "assistant":
        for b in ev.get("message", {}).get("content", []):
            bt = b.get("type")
            if bt == "text" and b.get("text", "").strip():
                out(b["text"].rstrip())
            elif bt == "thinking" and b.get("thinking", "").strip():
                out("  \U0001f4ad " + b["thinking"].strip().replace("\n", " ")[:140])
            elif bt == "tool_use":
                inp = b.get("input", {}) or {}
                hint = (inp.get("command") or inp.get("file_path")
                        or inp.get("pattern") or inp.get("description") or "")
                hint = str(hint).replace("\n", " ")
                if len(hint) > 100:
                    hint = hint[:100] + "…"
                out("  \U0001f527 %s: %s" % (b.get("name", "?"), hint))
    elif t == "result":
        if ev.get("is_error"):
            out("  ⚠️  result error: %s — %s"
                % (ev.get("subtype", ""), str(ev.get("result", ""))[:200]))
        else:
            out("  ✓ session done")
PYEOF

# Run a fresh headless Claude session with live, readable progress output.
# $1 = prompt. The pipeline's exit status is ignored on purpose — the real gate
# is "did the session commit?", checked by the caller.
#
# `< /dev/null` is REQUIRED: when claude -p's stdout is a pipe it assumes an
# `echo data | claude` pipeline and waits for stdin. Run interactively (TTY
# stdin) that wait never ends and the session hangs silently. /dev/null gives an
# immediate EOF so it proceeds.
run_claude() {
  local prompt="$1" mode="${2:-fresh}"
  [ -n "${RAW_LOG:-}" ] && rm -f "$RAW_LOG"
  RAW_LOG=$(mktemp)   # raw stream for usage-limit detection (see rate_limit_wake)
  local -a cmd=(claude)
  if [ "$mode" = resume ]; then
    cmd+=(--resume "$SESSION_ID")     # continue the interrupted session WITH its context + work so far
  else
    SESSION_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || python3 -c 'import uuid;print(uuid.uuid4())')
    cmd+=(--session-id "$SESSION_ID") # assign a known id up front so we can resume it after a limit
  fi
  cmd+=(-p "$prompt" "${CLAUDE_FLAGS[@]}" --output-format stream-json --verbose)
  if command -v python3 >/dev/null 2>&1; then
    "${cmd[@]}" < /dev/null | RAW_LOG="$RAW_LOG" python3 -u -c "$STREAM_FMT" || true
  else
    "${cmd[@]}" < /dev/null | tee "$RAW_LOG" || true
  fi
  read_usage "$RAW_LOG"   # keep the freshest usage signal for the next pre-flight
}

# If the most recent session aborted because of the Claude usage limit, echo the
# epoch second to wake at (the rate_limit_event's resetsAt + 60s buffer; falls
# back to now + 5h). Echoes nothing if the abort wasn't a usage limit — so the
# caller can tell "wait and retry" from "genuine failure, stop".
rate_limit_wake() {
  [ -f "${RAW_LOG:-}" ] || return 0
  python3 - "$RAW_LOG" <<'PY'
import sys, json, re, time
limited = False; reset = 0
# Anchored to the CLI's actual limit phrasing ("you've hit your session/usage
# limit", "… limit · resets …", "usage limit reached", a 429) so app code that
# merely mentions "limit" won't false-trigger.
pat = re.compile(r"hit your (?:session|usage) limit|(?:session|usage) limit\b.{0,40}reset|usage limit reached|rate.?limit reached|\b429\b", re.I)
try:
    for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
        line = line.strip()
        if not line:
            continue
        if pat.search(line):           # matches the limit message wherever it appears (assistant text/result)
            limited = True
        try:
            ev = json.loads(line)
        except Exception:
            continue
        if ev.get("type") == "rate_limit_event":
            info = ev.get("rate_limit_info", {}) or {}
            if str(info.get("status", "")).lower() not in ("", "allowed"):
                limited = True
            if info.get("resetsAt"):
                reset = max(reset, int(info["resetsAt"]))
except FileNotFoundError:
    pass
if limited:
    print(reset + 60 if reset else int(time.time()) + 5 * 3600 + 60)
PY
}

# Delete a leftover branch (local + remote) and close any open PR for it, so a
# resumed or retried slice can recreate it cleanly. No-op if nothing exists.
cleanup_branch() {
  local branch="$1" pr
  git switch main >/dev/null 2>&1 || true
  git branch -D "$branch" >/dev/null 2>&1 || true
  git push origin --delete "$branch" >/dev/null 2>&1 || true
  pr=$(gh pr list --head "$branch" --state open --json number -q '.[0].number' 2>/dev/null || true)
  [ -n "$pr" ] && gh pr close "$pr" >/dev/null 2>&1 || true
  return 0
}

# Parse a raw stream log into the usage globals: USAGE_STATUS (the last
# rate_limit_event's status, or "none" if absent) and USAGE_RESET (its resetsAt
# epoch, or 0). Lets the driver gate on the freshest signal it has.
read_usage() {
  local f="$1"
  USAGE_STATUS="none"; USAGE_RESET=0
  [ -f "$f" ] || return 0
  read -r USAGE_STATUS USAGE_RESET < <(python3 - "$f" <<'PY'
import sys, json, re
status = ""; reset = 0; limited = False
pat = re.compile(r"hit your (?:session|usage) limit|(?:session|usage) limit\b.{0,40}reset|usage limit reached|rate.?limit reached|\b429\b", re.I)
try:
    for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
        line = line.strip()
        if not line:
            continue
        if pat.search(line):
            limited = True
        try:
            ev = json.loads(line)
        except Exception:
            continue
        if ev.get("type") == "rate_limit_event":
            info = ev.get("rate_limit_info", {}) or {}
            if info.get("status"):
                status = str(info["status"])
            if info.get("resetsAt"):
                reset = int(info["resetsAt"])
except FileNotFoundError:
    pass
# A limit message anywhere => treat as a limit tier so pre-flight waits.
if limited and status in ("", "none", "allowed"):
    status = "rejected"
print(status or "none", reset)
PY
)
  : "${USAGE_STATUS:=none}" "${USAGE_RESET:=0}"
}

# Probe current usage with a minimal session, into the usage globals.
probe_usage() {
  local f; f=$(mktemp)
  claude -p "ok" "${CLAUDE_FLAGS[@]}" --output-format stream-json --verbose < /dev/null >"$f" 2>/dev/null || true
  read_usage "$f"; rm -f "$f"
}

# Before starting a slice: if usage is already at a limit tier (status not
# "allowed"/"none"), sleep until the reset rather than starting work. Re-probes
# after each wait. Capped so an odd status can't loop forever.
preflight_wait() {
  [ "$PREFLIGHT_USAGE_GATE" = 1 ] || return 0
  local waits=0 now secs
  [ -n "${USAGE_STATUS:-}" ] || probe_usage      # first slice: no prior signal yet
  while [ "${USAGE_STATUS:-none}" != "allowed" ] && [ "${USAGE_STATUS:-none}" != "none" ]; do
    waits=$((waits+1)); [ "$waits" -gt 6 ] && die "usage still limited ('$USAGE_STATUS') after 6 pre-flight waits"
    now=$(date +%s); secs=$(( USAGE_RESET - now )); [ "$secs" -lt 60 ] && secs=60
    log "Pre-flight: usage tier '$USAGE_STATUS' (at/near limit) — not starting; sleeping ~$((secs/60)) min until $(date -d "@$USAGE_RESET" '+%a %H:%M') reset…"
    sleep "$secs"
    probe_usage
  done
}

# Implement a slice in a fresh session on a fresh branch off main, then merge.
# $1 = branch name   $2 = full prompt text for claude
# Returns the merge SHA in the global MERGE_SHA — NOT on stdout. (Using
# command substitution here would capture stdout and swallow all of the live
# session output, so the run would look silent.)
# Run a session until it has committed on the current branch. A usage-limit
# abort is waited out and the SAME session resumed, keeping its work so far;
# finishing without a commit for any other reason is a genuine failure.
# $1 = label for messages   $2 = prompt
run_until_committed() {
  local label="$1" prompt="$2" base waits=0 wake now secs
  base=$(git rev-parse HEAD)
  run_claude "$prompt" fresh
  while [ "$(git rev-parse HEAD)" = "$base" ]; do
    wake=$(rate_limit_wake)
    [ -n "$wake" ] || die "$label produced no commits"
    waits=$((waits+1)); [ "$waits" -gt 6 ] && die "$label: still usage-limited after 6 resumes"
    now=$(date +%s); secs=$(( wake - now )); [ "$secs" -lt 60 ] && secs=60
    log "Usage limit mid-session. Sleeping ~$((secs/60)) min until $(date -d "@$wake" '+%a %H:%M'), then RESUMING session ${SESSION_ID:0:8} (keeping work so far)…"
    sleep "$secs"
    run_claude "You were interrupted by a usage limit partway through this task. Continue exactly where you left off — do NOT start over — finish it, then commit all changes." resume
  done
}

# Fresh branch off main, implement, push, open a PR.
# $1 = branch   $2 = prompt
implement_and_open_pr() {
  local branch="$1" prompt="$2"
  preflight_wait
  cleanup_branch "$branch"                                   # clear any stale branch/PR (resume/retry)
  git switch main >/dev/null                || die "switch main failed"
  git pull --ff-only origin main >/dev/null || die "pull main failed"
  git switch -c "$branch" >/dev/null        || die "create $branch failed"
  run_until_committed "$branch" "$prompt"
  git push -u origin "$branch" >/dev/null   || die "push $branch failed"
  gh pr create --base main --head "$branch" --fill >/dev/null || die "pr create failed"
}

# Block until the given workflow's run for a commit finishes.
# $1 = workflow file   $2 = sha   Returns 0 on success, 1 on failure.
# Sets RUN_ID to the run watched.
wait_for_run() {
  local workflow="$1" sha="$2" tries=0
  RUN_ID=""
  log "Waiting for $workflow run on ${sha:0:8} ..."
  # The run can take a moment to register after the push.
  while [ -z "$RUN_ID" ]; do
    RUN_ID=$(gh run list --workflow "$workflow" \
          --json databaseId,headSha -L 30 \
          --jq "[.[] | select(.headSha==\"$sha\")][0].databaseId // empty" 2>/dev/null || true)
    [ -n "$RUN_ID" ] && break
    tries=$((tries+1)); [ "$tries" -gt 40 ] && die "no $workflow run appeared for ${sha:0:8}"
    sleep 15
  done
  gh run watch "$RUN_ID" --exit-status --interval 30 >/dev/null
}

failed_log() {
  gh run view "$1" --log-failed 2>/dev/null | tail -200 || echo "(log unavailable)"
}

# Wait for ios-ci on the PR branch; on red, fix on the same branch and retry.
# $1 = prompt id   $2 = branch
ci_until_green() {
  local P="$1" branch="$2" attempt=0 sha
  sha=$(git rev-parse HEAD)
  until wait_for_run "$CI_WORKFLOW" "$sha"; do
    attempt=$((attempt+1))
    [ "$attempt" -gt "$MAX_FIX_ATTEMPTS" ] && die "$P: ios-ci still failing after $MAX_FIX_ATTEMPTS fixes (PR left open on $branch)"
    log "=== $P : ios-ci FAILED — fix attempt $attempt (same branch) ==="
    preflight_wait
    run_until_committed "$branch-fix$attempt" "You are on branch \`$branch\`, which implements prompt $P of \"$DOC\". \
Its PR check \`ios-ci\` (simulator build + XCTest) FAILED. Read that prompt for the intended \
scope, then fix the failure below — fix the cause, never weaken or delete a ported test to \
get past it. Commit; do not push.

--- failing ios-ci log (tail) ---
$(failed_log "$RUN_ID")"
    git push origin "$branch" >/dev/null || die "push $branch failed"
    sha=$(git rev-parse HEAD)
  done
  log "=== $P : ios-ci GREEN ✅ ==="
}

merge_pr() {
  local branch="$1"
  gh pr merge "$branch" --merge --delete-branch >/dev/null || die "pr merge failed"
  git switch main >/dev/null                || die "switch main failed"
  git pull --ff-only origin main >/dev/null || die "pull main failed"
  MERGE_SHA=$(git rev-parse HEAD)
}

# --- main loop --------------------------------------------------------------
started=0
for P in "${PROMPTS[@]}"; do
  [ "$P" = "$START_AT" ] && started=1
  [ "$started" = 1 ] || { log "skip $P (resuming at $START_AT)"; continue; }

  log "=== $P : implementing ==="
  base_prompt="In this repo, read \"$DOC\", find prompt $P, and follow its \
**Run** line exactly — read the §refs it cites and implement ONLY the $P slice, \
no more, no less. $SPEC_RULE \
Ignore the Run line's instruction to push and watch CI yourself: this driver pushes \
the branch, runs ios-ci and sends you back any failure. When finished, commit all \
changes with a clear message. Do not push or open a PR."

  branch="$BRANCH_PREFIX$P"
  implement_and_open_pr "$branch" "$base_prompt"
  ci_until_green "$P" "$branch"
  merge_pr "$branch"; sha="$MERGE_SHA"

  if [ "$SKIP_TESTFLIGHT" = 1 ]; then
    log "=== $P : merged (TestFlight skipped) ==="
    continue
  fi

  attempt=0
  until wait_for_run "$WORKFLOW" "$sha"; do
    attempt=$((attempt+1))
    [ "$attempt" -gt "$MAX_FIX_ATTEMPTS" ] && die "$P: TestFlight still failing after $MAX_FIX_ATTEMPTS fixes"
    log "=== $P : TestFlight FAILED — fix attempt $attempt ==="
    fix_branch="$BRANCH_PREFIX$P-tf-fix$attempt"
    implement_and_open_pr "$fix_branch" "The iOS TestFlight build on \`main\` for prompt $P of \"$DOC\" \
FAILED, though the simulator check passed — so look first at signing, archiving and \
Release-only settings. Fix only what's needed to make \`fastlane beta\` (scheme Motif) \
build, sign and upload. Commit; do not push.

--- failing TestFlight log (tail) ---
$(failed_log "$RUN_ID")"
    ci_until_green "$P" "$fix_branch"
    merge_pr "$fix_branch"; sha="$MERGE_SHA"
  done

  log "=== $P : TestFlight GREEN ✅ ==="
done

log "All prompts complete. 🎉"
