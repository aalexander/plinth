#!/usr/bin/env bash
# Dashboard smoke for `plinth dash` (canary CI). Covers:
#   1. Offline --snapshot fixture matrix (tilde, detached, core.abbrev,
#      multi-digit request rounds, completed NEEDS-HUMAN, render failure,
#      discovery modes, burn, port validation).
#   2. Pure UI card render via node + globalThis.__plinthDash (error tone,
#      no-review suppression).
#   3. Short-lived loopback HTTP server (/, /api/snapshot, POST 405, 404),
#      with process-group cleanup so the python child cannot leak.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLINTH="${ROOT}/bin/plinth"
[ -x "$PLINTH" ] || { echo "smoke-snapshot: missing $PLINTH" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "smoke-snapshot: jq required" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "smoke-snapshot: node required for UI card unit test" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "smoke-snapshot: curl required for server check" >&2; exit 1; }

FIX="$(mktemp -d "${TMPDIR:-/tmp}/plinth-dash-smoke.XXXXXX")"
cleanup() { rm -rf "$FIX"; }
trap cleanup EXIT

mk_git() {
  local d="$1"
  mkdir -p "$d/.plinth/session"
  printf 'spec_path = SPEC.md\n' > "$d/.plinth/config"
  git -C "$d" init -q
  git -C "$d" config user.email "smoke@plinth.test"
  git -C "$d" config user.name "plinth smoke"
  echo ok > "$d/README"
  git -C "$d" add -A
  git -C "$d" commit -qm "init"
}

# ── Fixture A: active session + verdict + NEEDS-HUMAN open + events ──────────
A="$FIX/alpha"
mk_git "$A"
git -C "$A" checkout -qb feat/dash
echo x > "$A/f.txt"
git -C "$A" add -A
git -C "$A" commit -qm "work"
HEAD="$(git -C "$A" rev-parse --short HEAD)"
FULL="$(git -C "$A" rev-parse HEAD)"

NOW="$(date +%s)"
jq -nc --argjson epoch "$NOW" \
  '{ts:"2026-01-01T00:00:00Z",epoch:$epoch,event:"SessionStart",sid:"sid-smoke",transcript:null,tool:null,detail:null,rc:null}' \
  > "$A/.plinth/session/events.jsonl"
jq -nc --argjson epoch "$((NOW - 10))" \
  '{ts:"2026-01-01T00:00:10Z",epoch:$epoch,event:"UserPromptSubmit",sid:"sid-smoke",transcript:null,tool:null,detail:"smoke dashboard task",rc:null}' \
  >> "$A/.plinth/session/events.jsonl"

mkdir -p "$A/.plinth/session/review/feat-dash"
jq -nc --arg sha "$FULL" \
  '{verdict:"CHANGES_NEEDED",sha:$sha,round:2,mode:"fresh",model:"gpt-test",
    risk:{tier:1,files:1,reasons:["test"]},ts:"2026-01-01T00:00:00Z"}' \
  > "$A/.plinth/session/review/feat-dash/verdict.json"

printf '%s\n' '# Queue' '- [ ] [BLOCKING] need human decision' '- [ ] optional follow-up' \
  > "$A/.plinth/NEEDS-HUMAN.md"

# ── Fixture B: feedless project (config only, no events) ─────────────────────
B="$FIX/beta"
mk_git "$B"

# ── Fixture C: detached HEAD with APPROVED under slug "detached" ─────────────
C="$FIX/gamma-detached"
mk_git "$C"
git -C "$C" checkout -qb feat/tmp
echo y > "$C/y.txt"
git -C "$C" add -A
git -C "$C" commit -qm "work"
CFULL="$(git -C "$C" rev-parse HEAD)"
git -C "$C" checkout -q --detach HEAD
mkdir -p "$C/.plinth/session/review/detached"
jq -nc --arg sha "$CFULL" \
  '{verdict:"APPROVED",sha:$sha,round:1,mode:"fresh",model:"gpt-test",
    risk:{tier:1,files:1,reasons:["test"]},ts:"2026-01-01T00:00:00Z"}' \
  > "$C/.plinth/session/review/detached/verdict.json"

# ── Fixture D: core.abbrev=12 must not false-stale a matching full SHA ───────
D="$FIX/delta-abbrev"
mk_git "$D"
git -C "$D" checkout -qb feat/abbrev
echo z > "$D/z.txt"
git -C "$D" add -A
git -C "$D" commit -qm "work"
git -C "$D" config core.abbrev 12
DFULL="$(git -C "$D" rev-parse HEAD)"
mkdir -p "$D/.plinth/session/review/feat-abbrev"
jq -nc --arg sha "$DFULL" \
  '{verdict:"APPROVED",sha:$sha,round:1,mode:"fresh",model:"gpt-test",
    risk:{tier:1,files:1,reasons:["test"]},ts:"2026-01-01T00:00:00Z"}' \
  > "$D/.plinth/session/review/feat-abbrev/verdict.json"

# ── Fixture E: path with '-' + request-2 + request-10 → newest is round 10 ───
E="$FIX/epsilon-hyphen"
mk_git "$E"
git -C "$E" checkout -qb feat/req
echo e > "$E/e.txt"
git -C "$E" add -A
git -C "$E" commit -qm "work"
EFULL="$(git -C "$E" rev-parse HEAD)"
mkdir -p "$E/.plinth/session/review/feat-req"
jq -nc --arg sha "$EFULL" \
  '{verdict:"CHANGES_NEEDED",sha:$sha,round:1,mode:"fresh",model:"gpt-test",
    risk:{tier:1,files:1,reasons:["test"]},ts:"2026-01-01T00:00:00Z"}' \
  > "$E/.plinth/session/review/feat-req/verdict.json"
jq -nc '{round:2,mode:"resume",model:"gpt-test"}' \
  > "$E/.plinth/session/review/feat-req/request-2.json"
jq -nc '{round:10,mode:"resume",model:"gpt-test"}' \
  > "$E/.plinth/session/review/feat-req/request-10.json"

# ── Fixture F: completed NEEDS-HUMAN (checked only) → open 0 ─────────────────
F="$FIX/zeta-done"
mk_git "$F"
printf '%s\n' '# Queue' '- [x] already done' '- [x] also done' \
  > "$F/.plinth/NEEDS-HUMAN.md"

# ── Fixture G: unused/malformed usage.jsonl is ignored (not read) ────────────
G="$FIX/eta-badusage"
mk_git "$G"
git -C "$G" checkout -qb feat/bad
echo g > "$G/g.txt"
git -C "$G" add -A
git -C "$G" commit -qm "work"
GFULL="$(git -C "$G" rev-parse HEAD)"
mkdir -p "$G/.plinth/session/review/feat-bad"
jq -nc --arg sha "$GFULL" \
  '{verdict:"APPROVED",sha:$sha,round:1,mode:"fresh",model:"gpt-test",
    risk:{tier:1,files:1,reasons:["test"]},ts:"2026-01-01T00:00:00Z"}' \
  > "$G/.plinth/session/review/feat-bad/verdict.json"
printf 'not-json{\n' > "$G/.plinth/session/review/feat-bad/usage.jsonl"
printf '%s\n' '- [ ] [BLOCKING] still open after bad usage' \
  > "$G/.plinth/NEEDS-HUMAN.md"

# ── Fixture H: transcript burn (all token categories + tail bound) ───────────
H="$FIX/theta-burn"
mk_git "$H"
git -C "$H" checkout -qb feat/burn
echo h > "$H/h.txt"
git -C "$H" add -A
git -C "$H" commit -qm "work"
HTR="$H/.plinth/session/transcript.jsonl"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
# 350 lines: first 50 are OLD noise that must be tailed away; last has real usage
# including non-zero cache_creation so dropping that category fails the assert.
python3 - "$HTR" "$TS" <<'PY'
import json, sys
path, ts = sys.argv[1], sys.argv[2]
with open(path, "w") as f:
    for i in range(350):
        if i < 50:
            usage = {"input_tokens": 9999, "output_tokens": 0,
                     "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}
        elif i == 349:
            usage = {"input_tokens": 100, "output_tokens": 50,
                     "cache_creation_input_tokens": 25, "cache_read_input_tokens": 10000}
        else:
            usage = {"input_tokens": 0, "output_tokens": 0,
                     "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}
        f.write(json.dumps({
            "type": "assistant", "timestamp": ts,
            "message": {"model": "claude-test", "usage": usage},
        }) + "\n")
PY
jq -nc --argjson epoch "$NOW" --arg tr "$HTR" \
  '{ts:"2026-01-01T00:00:00Z",epoch:$epoch,event:"SessionStart",sid:"sid-burn",transcript:$tr,tool:null,detail:null,rc:null}' \
  > "$H/.plinth/session/events.jsonl"

# ── Fixture I: malformed verdict → real snapshot_render_failed, NH preserved ─
I="$FIX/iota-badverdict"
mk_git "$I"
git -C "$I" checkout -qb feat/badv
echo i > "$I/i.txt"
git -C "$I" add -A
git -C "$I" commit -qm "work"
mkdir -p "$I/.plinth/session/review/feat-badv"
printf 'not-json{\n' > "$I/.plinth/session/review/feat-badv/verdict.json"
printf '%s\n' '- [ ] [BLOCKING] keep me through render failure' \
  > "$I/.plinth/NEEDS-HUMAN.md"

# ── Fixture J: long session within the 10k window (task + ~10000s age) ───────
J="$FIX/kappa-long"
mk_git "$J"
git -C "$J" checkout -qb feat/long
echo j > "$J/j.txt"
git -C "$J" add -A
git -C "$J" commit -qm "work"
J_T0=$((NOW - 10000))
{
  jq -nc --argjson epoch "$J_T0" \
    '{ts:"2026-01-01T00:00:00Z",epoch:$epoch,event:"SessionStart",sid:"sid-long",transcript:null,tool:null,detail:null,rc:null}'
  jq -nc --argjson epoch "$((J_T0 + 1))" \
    '{ts:"2026-01-01T00:00:01Z",epoch:$epoch,event:"UserPromptSubmit",sid:"sid-long",transcript:null,tool:null,detail:"long session task",rc:null}'
  # 600 tool events after the prompt — still inside the 10k window.
  n=0
  while [ "$n" -lt 600 ]; do
    jq -nc --argjson epoch "$((J_T0 + 2 + n))" --argjson n "$n" \
      '{ts:"2026-01-01T00:00:00Z",epoch:$epoch,event:"PostToolUse",sid:"sid-long",transcript:null,tool:"Bash",detail:("tool-"+($n|tostring)),rc:0}'
    n=$((n + 1))
  done
} > "$J/.plinth/session/events.jsonl"

# ── Fixture J2: SessionStart older than 10k-line window → session_secs null ──
# (task may still appear if a later prompt is in the window; here only tools)
J2="$FIX/kappa-cap"
mk_git "$J2"
{
  jq -nc --argjson epoch "$((NOW - 50000))" \
    '{epoch:$epoch,event:"SessionStart",sid:"sid-cap",transcript:null,tool:null,detail:null,rc:null}'
  jq -nc --argjson epoch "$((NOW - 49999))" \
    '{epoch:$epoch,event:"UserPromptSubmit",sid:"sid-cap",transcript:null,tool:null,detail:"ancient task",rc:null}'
  # 10001 tool-only lines so SessionStart + prompt fall outside the tail window.
  # Use a compact python writer (shell jq loop would be too slow).
  python3 - "$((NOW - 49998))" <<'PY'
import json, sys
base = int(sys.argv[1])
for n in range(10001):
    print(json.dumps({
        "epoch": base + n, "event": "PostToolUse", "sid": "sid-cap",
        "transcript": None, "tool": "Bash", "detail": "t%d" % n, "rc": 0,
    }))
PY
} > "$J2/.plinth/session/events.jsonl"

# ── Fixture K: last-error means NOT running despite newer request ────────────
K="$FIX/lambda-err"
mk_git "$K"
git -C "$K" checkout -qb feat/err
echo k > "$K/k.txt"
git -C "$K" add -A
git -C "$K" commit -qm "work"
KFULL="$(git -C "$K" rev-parse HEAD)"
mkdir -p "$K/.plinth/session/review/feat-err"
jq -nc --arg sha "$KFULL" \
  '{verdict:"CHANGES_NEEDED",sha:$sha,round:1,mode:"fresh",model:"gpt-test",
    risk:{tier:1,files:1,reasons:["test"]},ts:"2026-01-01T00:00:00Z"}' \
  > "$K/.plinth/session/review/feat-err/verdict.json"
jq -nc '{round:2,mode:"resume",model:"gpt-test"}' \
  > "$K/.plinth/session/review/feat-err/request-2.json"
printf '2026-01-01T00:00:00Z reviewer CLI missing\n' \
  > "$K/.plinth/session/review/feat-err/last-error"

# ── Fixture L: stale verdict (SHA deliberately wrong) ────────────────────────
L="$FIX/mu-stale"
mk_git "$L"
git -C "$L" checkout -qb feat/stale
echo l > "$L/l.txt"
git -C "$L" add -A
git -C "$L" commit -qm "work"
mkdir -p "$L/.plinth/session/review/feat-stale"
jq -nc \
  '{verdict:"APPROVED",sha:"0000000000000000000000000000000000000000",round:1,mode:"fresh",model:"gpt-test",
    risk:{tier:1,files:1,reasons:["test"]},ts:"2026-01-01T00:00:00Z"}' \
  > "$L/.plinth/session/review/feat-stale/verdict.json"

# ── Fixture M: interleaved SIDs — later A event must not reset A's task/t0 ───
M="$FIX/nu-interleave"
mk_git "$M"
{
  jq -nc --argjson epoch "$((NOW - 500))" \
    '{epoch:$epoch,event:"SessionStart",sid:"A",transcript:null,tool:null,detail:null,rc:null}'
  jq -nc --argjson epoch "$((NOW - 499))" \
    '{epoch:$epoch,event:"UserPromptSubmit",sid:"A",transcript:null,tool:null,detail:"task from A",rc:null}'
  jq -nc --argjson epoch "$((NOW - 100))" \
    '{epoch:$epoch,event:"SessionStart",sid:"B",transcript:null,tool:null,detail:null,rc:null}'
  # Interleaved late event for A after B started — last sid is still A if we append A last
  jq -nc --argjson epoch "$((NOW - 50))" \
    '{epoch:$epoch,event:"PostToolUse",sid:"A",transcript:null,tool:"Bash",detail:"late-A",rc:0}'
} > "$M/.plinth/session/events.jsonl"
# Active sid is A (last event); task and ~500s session must survive the B interleave.

# ── Fixture N: malformed events.jsonl → snapshot_render_failed ───────────────
N="$FIX/xi-badev"
mk_git "$N"
printf 'not-json{\n' > "$N/.plinth/session/events.jsonl"
printf '%s\n' '- [ ] [BLOCKING] open through bad events' > "$N/.plinth/NEEDS-HUMAN.md"

# ── Fixture N2: empty events.jsonl is healthy-but-empty (not error) ──────────
N2="$FIX/xi-empty"
mk_git "$N2"
: > "$N2/.plinth/session/events.jsonl"

# ── Fixture O: first-round last-error (no verdict yet) ───────────────────────
O="$FIX/omicron-firsterr"
mk_git "$O"
git -C "$O" checkout -qb feat/firsterr
echo o > "$O/o.txt"
git -C "$O" add -A
git -C "$O" commit -qm "work"
mkdir -p "$O/.plinth/session/review/feat-firsterr"
jq -nc '{round:1,mode:"fresh",model:"gpt-test"}' \
  > "$O/.plinth/session/review/feat-firsterr/request-1.json"
printf '2026-01-01T00:00:00Z reviewer missing\n' \
  > "$O/.plinth/session/review/feat-firsterr/last-error"
# last-error strictly newer than request → stuck error, not running
python3 - "$O/.plinth/session/review/feat-firsterr/request-1.json" \
  "$O/.plinth/session/review/feat-firsterr/last-error" <<'PY'
import os, sys, time
base = time.time() - 10
os.utime(sys.argv[1], (base, base))
os.utime(sys.argv[2], (base + 5, base + 5))
PY

# ── Fixture P: last-error then NEWER request → RUNNING (retry in flight) ─────
P="$FIX/pi-retry"
mk_git "$P"
git -C "$P" checkout -qb feat/retry
echo p > "$P/p.txt"
git -C "$P" add -A
git -C "$P" commit -qm "work"
PFULL="$(git -C "$P" rev-parse HEAD)"
mkdir -p "$P/.plinth/session/review/feat-retry"
jq -nc --arg sha "$PFULL" \
  '{verdict:"CHANGES_NEEDED",sha:$sha,round:1,mode:"fresh",model:"gpt-test",
    risk:{tier:1,files:1,reasons:["test"]},ts:"2026-01-01T00:00:00Z"}' \
  > "$P/.plinth/session/review/feat-retry/verdict.json"
printf 'old infra error\n' > "$P/.plinth/session/review/feat-retry/last-error"
jq -nc '{round:2,mode:"resume",model:"gpt-test"}' \
  > "$P/.plinth/session/review/feat-retry/request-2.json"
# Pin mtimes: error older, request strictly newer (no sleep race).
python3 - "$P/.plinth/session/review/feat-retry/last-error" \
  "$P/.plinth/session/review/feat-retry/request-2.json" <<'PY'
import os, sys, time
base = time.time() - 10
os.utime(sys.argv[1], (base, base))
os.utime(sys.argv[2], (base + 5, base + 5))
PY
# Same-second equal mtimes must NOT flip to RUNNING (error wins when not -nt).
Q="$FIX/rho-samesec"
mk_git "$Q"
git -C "$Q" checkout -qb feat/samesec
echo q > "$Q/q.txt"
git -C "$Q" add -A
git -C "$Q" commit -qm "work"
QFULL="$(git -C "$Q" rev-parse HEAD)"
mkdir -p "$Q/.plinth/session/review/feat-samesec"
jq -nc --arg sha "$QFULL" \
  '{verdict:"CHANGES_NEEDED",sha:$sha,round:1,mode:"fresh",model:"gpt-test",
    risk:{tier:1,files:1,reasons:["test"]},ts:"2026-01-01T00:00:00Z"}' \
  > "$Q/.plinth/session/review/feat-samesec/verdict.json"
printf 'infra error\n' > "$Q/.plinth/session/review/feat-samesec/last-error"
jq -nc '{round:2,mode:"resume",model:"gpt-test"}' \
  > "$Q/.plinth/session/review/feat-samesec/request-2.json"
python3 - "$Q/.plinth/session/review/feat-samesec/last-error" \
  "$Q/.plinth/session/review/feat-samesec/request-2.json" <<'PY'
import os, sys, time
t = time.time() - 3
os.utime(sys.argv[1], (t, t))
os.utime(sys.argv[2], (t, t))  # equal age → stuck error, not RUNNING
PY

export PLINTH_DASH_ROOTS="$A:$B:$C:$D:$E:$F:$G:$H:$I:$J:$J2:$K:$L:$M:$N:$N2:$O:$P:$Q"
OUT="$FIX/out.json"
"$PLINTH" dash --snapshot > "$OUT"
# Alias parity: `dashboard` must accept --snapshot the same way.
ALIAS_OUT="$FIX/alias.json"
"$PLINTH" dashboard --snapshot > "$ALIAS_OUT"
ac="$(jq '.projects | length' "$OUT")"
bc="$(jq '.projects | length' "$ALIAS_OUT")"
[ "$ac" = "$bc" ] || { echo "smoke-snapshot: dashboard alias project count $bc != dash $ac" >&2; exit 1; }

echo "smoke-snapshot: snapshot written ($OUT)"
jq -e . "$OUT" >/dev/null

# Top-level shape
jq -e 'has("generated_at") and has("discovery") and has("projects")' "$OUT" >/dev/null
jq -e '.discovery == "env:PLINTH_DASH_ROOTS"' "$OUT" >/dev/null
jq -e '(.projects | length) == 19' "$OUT" >/dev/null

# Alpha assertions
jq -e --arg head "$HEAD" '
  .projects[] | select(.name == "alpha")
  | .branch == "feat/dash"
  and .head == $head
  and .feedless == false
  and .needs_human.open == 2
  and .needs_human.blocking == 1
  and .review.verdict == "CHANGES_NEEDED"
  and .review.round == 2
  and .review.stale == false
  and .review.running == false
  and .task == "smoke dashboard task"
  and .quota.available == false
  and (.quota.note | type == "string")
  and (.activity_secs_ago != null)
  and (.activity_secs_ago | type == "number")
  and .activity_secs_ago >= 0
  and .activity_secs_ago < 120
  and (.error == null or .error == "")
' "$OUT" >/dev/null

# Beta feedless
jq -e '
  .projects[] | select(.name == "beta")
  | .feedless == true
  and .review == null
  and .activity_secs_ago == null
  and .quota.available == false
' "$OUT" >/dev/null

# Detached HEAD finds verdict under "detached"
jq -e '
  .projects[] | select(.name == "gamma-detached")
  | .branch == "detached"
  and .review != null
  and .review.verdict == "APPROVED"
  and .review.stale == false
' "$OUT" >/dev/null

# core.abbrev=12: matching full SHA is not stale
jq -e '
  .projects[] | select(.name == "delta-abbrev")
  | .review.verdict == "APPROVED"
  and .review.stale == false
' "$OUT" >/dev/null

# Multi-digit request: round 10 wins over round 2 (path has hyphen)
jq -e '
  .projects[] | select(.name == "epsilon-hyphen")
  | .review.running == true
  and .review.round == 10
' "$OUT" >/dev/null

# Completed queue → open 0 (not headings/checked lines)
jq -e '
  .projects[] | select(.name == "zeta-done")
  | .needs_human.open == 0
  and .needs_human.blocking == 0
' "$OUT" >/dev/null

# Malformed unused usage must not break a healthy card
jq -e '
  .projects[] | select(.name == "eta-badusage")
  | .needs_human.open == 1
  and .needs_human.blocking == 1
  and .review.verdict == "APPROVED"
  and (.error == null or .error == "")
' "$OUT" >/dev/null

# Transcript burn: tail drops the 9999-noise prefix; all categories including
# cache_creation(25)+cache_read(10000)+in(100)+out(50)=10175
jq -e '
  .projects[] | select(.name == "theta-burn")
  | .tokens_total == 10175
  and .tokens_window == "recent_transcript_tail"
  and .burn_per_min == 2035
  and .model_driver == "claude-test"
' "$OUT" >/dev/null

# Real render failure: error field set, NH counts preserved, project not dropped
jq -e '
  .projects[] | select(.name == "iota-badverdict")
  | .error == "snapshot_render_failed"
  and .needs_human.open == 1
  and .needs_human.blocking == 1
  and .review == null
' "$OUT" >/dev/null

# Long session within window: task + ~10000s session
jq -e --argjson now "$NOW" --argjson t0 "$J_T0" '
  .projects[] | select(.name == "kappa-long")
  | .task == "long session task"
  and .session_secs != null
  and (((.session_secs - ($now - $t0)) | if . < 0 then -. else . end) <= 5)
' "$OUT" >/dev/null

# Cap boundary: SessionStart outside 10k window → session_secs null (not fabricated)
jq -e '
  .projects[] | select(.name == "kappa-cap")
  | .session_secs == null
  and (.task == null or .task == "")
  and .sid == "sid-cap"
' "$OUT" >/dev/null

# last-error: request outruns verdict but NOT running
jq -e '
  .projects[] | select(.name == "lambda-err")
  | .review.running == false
  and .review.last_error == true
  and .review.verdict == "CHANGES_NEEDED"
' "$OUT" >/dev/null

# Explicit stale=true
jq -e '
  .projects[] | select(.name == "mu-stale")
  | .review.stale == true
  and .review.verdict == "APPROVED"
' "$OUT" >/dev/null

# Interleaved SIDs: active A keeps original task + ~500s session
jq -e '
  .projects[] | select(.name == "nu-interleave")
  | .task == "task from A"
  and .sid == "A"
  and .session_secs != null
  and .session_secs >= 400
  and .session_secs <= 600
' "$OUT" >/dev/null

# Malformed events → error card with NH preserved
jq -e '
  .projects[] | select(.name == "xi-badev")
  | .error == "snapshot_render_failed"
  and .needs_human.open == 1
  and .needs_human.blocking == 1
' "$OUT" >/dev/null

# Empty events.jsonl is healthy (not snapshot_render_failed)
jq -e '
  .projects[] | select(.name == "xi-empty")
  | (.error == null or .error == "")
  and .feedless == false
  and .task == null
  and .session_secs == null
' "$OUT" >/dev/null

# First-round last-error (no prior verdict)
jq -e '
  .projects[] | select(.name == "omicron-firsterr")
  | .review != null
  and .review.running == false
  and .review.last_error == true
  and .review.verdict == null
' "$OUT" >/dev/null

# Retry: request strictly newer than last-error → RUNNING
jq -e '
  .projects[] | select(.name == "pi-retry")
  | .review.running == true
  and .review.round == 2
  and .review.last_error == false
' "$OUT" >/dev/null

# Same-second request/error mtimes → stuck error (not RUNNING)
jq -e '
  .projects[] | select(.name == "rho-samesec")
  | .review.running == false
  and .review.last_error == true
' "$OUT" >/dev/null

# Subsecond later request within the same wall-clock second → RUNNING (-nt)
R="$FIX/sigma-subsec"
mk_git "$R"
git -C "$R" checkout -qb feat/subsec
echo r > "$R/r.txt"
git -C "$R" add -A
git -C "$R" commit -qm "work"
RFULL="$(git -C "$R" rev-parse HEAD)"
mkdir -p "$R/.plinth/session/review/feat-subsec"
jq -nc --arg sha "$RFULL" \
  '{verdict:"CHANGES_NEEDED",sha:$sha,round:1,mode:"fresh",model:"gpt-test",
    risk:{tier:1,files:1,reasons:["test"]},ts:"2026-01-01T00:00:00Z"}' \
  > "$R/.plinth/session/review/feat-subsec/verdict.json"
printf 'infra error\n' > "$R/.plinth/session/review/feat-subsec/last-error"
jq -nc '{round:2,mode:"resume",model:"gpt-test"}' \
  > "$R/.plinth/session/review/feat-subsec/request-2.json"
python3 - "$R/.plinth/session/review/feat-subsec/last-error" \
  "$R/.plinth/session/review/feat-subsec/request-2.json" <<'PY'
import os, sys
# Same integer second, request 50ms later (nanosecond utime).
sec = 1_700_000_000
os.utime(sys.argv[1], ns=(sec * 10**9, sec * 10**9))
os.utime(sys.argv[2], ns=(sec * 10**9 + 50_000_000, sec * 10**9 + 50_000_000))
PY
export PLINTH_DASH_ROOTS="$R"
SUB="$FIX/subsec.json"
"$PLINTH" dash --snapshot > "$SUB"
jq -e '
  .projects[] | select(.name == "sigma-subsec")
  | .review.running == true
  and .review.last_error == false
  and .review.round == 2
' "$SUB" >/dev/null

# ── Pure UI card render (node + __plinthDash seam) ───────────────────────────
# Fails if error tone or no-review suppression is broken — not just source greps.
UI_OUT="$FIX/ui-unit.out"
PLINTH_DASH_HTML="$ROOT/shared/dashboard/index.html" node <<'NODE' >"$UI_OUT"

const fs = require("fs");
const vm = require("vm");
const path = process.env.PLINTH_DASH_HTML;
const html = fs.readFileSync(path, "utf8");
const m = html.match(/<script>\s*([\s\S]*?)\s*<\/script>\s*<\/body>/i);
if (!m) { console.error("no script block"); process.exit(2); }
const elsById = Object.create(null);
const el = (id) => {
  const o = { textContent: "", className: "", innerHTML: "", style: { display: "", cssText: "" } };
  // Honor real selectors used by the UI: .card after successful render.
  o.querySelector = (sel) => {
    if (sel === ".card" && typeof o.innerHTML === "string" && o.innerHTML.includes("class=\"card")) {
      return el(); // non-null sentinel: cards present
    }
    return null;
  };
  let _id = id || "";
  Object.defineProperty(o, "id", {
    get() { return _id; },
    set(v) { _id = v; if (v) elsById[v] = o; },
  });
  if (id) elsById[id] = o;
  return o;
};
let pending = 0;
let fetchStarts = 0;
const resolvers = [];
const sandbox = {
  console,
  Date, Math, String, Number, JSON, Array, Object, parseInt, isNaN,
  // Capture interval callbacks + delays so the harness can assert the 2s poll.
  __intervals: [],
  setInterval: (fn, ms) => {
    sandbox.__intervals.push({ fn, ms });
    return sandbox.__intervals.length;
  },
  clearInterval: () => {},
  fetch: () => {
    fetchStarts += 1;
    pending += 1;
    return new Promise((resolve) => {
      resolvers.push((body) => {
        pending -= 1;
        resolve({
          ok: true,
          json: async () => body || {
            generated_at: 1, discovery: "t",
            projects: [{
              name: "alpha", path: "/a", branch: "feat/dash", head: "abc1234",
              feedless: false, task: "do the thing", burn_per_min: 12,
              tokens_total: 100, needs_human: { open: 0, blocking: 0 },
              review: { verdict: "CHANGES_NEEDED", round: 2, sha7: "abc1234",
                        stale: false, running: false, mode: "fresh", tier: 1 },
            }],
          },
        });
      });
    });
  },
  document: {
    // Unknown IDs return null so production create/insert path runs for #poll-error.
    getElementById: (id) => (Object.prototype.hasOwnProperty.call(elsById, id) ? elsById[id] : null),
    createElement: () => el(),
    querySelector: (sel) => {
      if (sel === "header") {
        return {
          parentNode: {
            insertBefore: (node) => {
              if (node && node.id) elsById[node.id] = node;
            },
          },
        };
      }
      return null;
    },
  },
};
// Pre-seed only the IDs present in the static HTML (not poll-error).
["grid", "live-dot", "live-label", "gen-ago", "discovery", "count"].forEach((id) => { elsById[id] = el(id); });
sandbox.globalThis = sandbox;
sandbox.window = sandbox;
vm.createContext(sandbox);
vm.runInContext(m[1], sandbox);
const api = sandbox.__plinthDash;
if (!api || typeof api.cardHTML !== "function" || typeof api.cardTone !== "function") {
  console.error("missing __plinthDash.cardHTML/cardTone");
  process.exit(2);
}
// Must register a 2000ms poll interval (not only the 1000ms clock).
const pollTimers = sandbox.__intervals.filter((i) => i.ms === 2000);
const clockTimers = sandbox.__intervals.filter((i) => i.ms === 1000);
if (pollTimers.length !== 1) {
  console.error("expected exactly one 2000ms poll interval, got", pollTimers.length,
    "intervals=", sandbox.__intervals.map((i) => i.ms));
  process.exit(1);
}
if (clockTimers.length < 1) {
  console.error("expected a 1000ms clock interval");
  process.exit(1);
}
const pollTick = pollTimers[0].fn;
// Initial poll() from the IIFE started one fetch.
if (fetchStarts !== 1 || pending !== 1) {
  console.error("expected 1 in-flight fetch after boot, got starts=", fetchStarts, "pending=", pending);
  process.exit(1);
}
// Fire the 2s poll callback twice while still pending — must not start another fetch.
pollTick();
pollTick();
if (fetchStarts !== 1 || pending !== 1) {
  console.error("overlapping poll via 2000ms timer: starts=", fetchStarts, "pending=", pending);
  process.exit(1);
}
// Explicit concurrent poll() calls must no-op while in flight.
api.poll();
api.poll();
if (fetchStarts !== 1) {
  console.error("explicit poll overlap: starts=", fetchStarts);
  process.exit(1);
}
// Complete the first fetch; the next 2000ms tick (not a manual api.poll) starts #2.
resolvers[0]();
// Allow microtasks
setTimeout(() => {
  if (api.getPollState().inFlight) {
    console.error("poll still inFlight after resolve");
    process.exit(1);
  }
  pollTick(); // automatic 2s interval drives the next fetch
  if (fetchStarts !== 2 || pending !== 1) {
    console.error("2000ms tick after idle failed: starts=", fetchStarts, "pending=", pending);
    process.exit(1);
  }
  // Overlap still blocked on the second fetch.
  pollTick();
  if (fetchStarts !== 2) {
    console.error("second in-flight overlapped via timer");
    process.exit(1);
  }
  resolvers[1]();
  setTimeout(() => {
    // Error card
    const errProj = {
      error: "snapshot_render_failed",
      name: "iota", path: "/tmp/iota", branch: "feat/badv", head: "abc1234",
      needs_human: { open: 1, blocking: 1 },
      feedless: false, review: null,
    };
    if (api.cardTone(errProj) !== "bad") {
      console.error("cardTone(error) expected bad, got", api.cardTone(errProj));
      process.exit(1);
    }
    const htmlCard = api.cardHTML(errProj);
    if (!htmlCard.includes('class="card bad"')) {
      console.error("error card missing tone class bad");
      process.exit(1);
    }
    if (!htmlCard.includes("error: snapshot_render_failed")) {
      console.error("error chip missing from cardHTML");
      process.exit(1);
    }
    if (htmlCard.includes("no review")) {
      console.error("error card must not show 'no review'");
      process.exit(1);
    }
    if (!htmlCard.includes("NEEDS-HUMAN ×1")) {
      console.error("error card must still show NEEDS-HUMAN");
      process.exit(1);
    }
    // Full field card: branch/head/review/burn/task
    const full = {
      name: "alpha", path: "/tmp/alpha", branch: "feat/dash", head: "abc1234",
      feedless: false, task: "do the thing", burn_per_min: 12, tokens_total: 1500,
      model_driver: "claude-test", model_reviewer: "gpt-test",
      needs_human: { open: 0, blocking: 0 },
      review: { verdict: "CHANGES_NEEDED", round: 2, sha7: "abc1234",
                stale: false, running: false, mode: "fresh", tier: 1 },
      activity_secs_ago: 5, session_secs: 60,
    };
    const fullHtml = api.cardHTML(full);
    for (const needle of [
      "feat/dash", "abc1234", "CHANGES_NEEDED", "do the thing",
      "12/min", "1.5k recent", "r2",
    ]) {
      if (!fullHtml.includes(needle)) {
        console.error("cardHTML missing field representation:", needle);
        process.exit(1);
      }
    }
    // Healthy idle: no review chip present, tone idle
    const idle = {
      name: "beta", path: "/tmp/beta", branch: "main", head: "deadbee",
      feedless: true, review: null, needs_human: { open: 0, blocking: 0 },
    };
    if (api.cardTone(idle) !== "idle") {
      console.error("cardTone(idle) expected idle");
      process.exit(1);
    }
    const idleHtml = api.cardHTML(idle);
    if (!idleHtml.includes("no review")) {
      console.error("idle card should show no review");
      process.exit(1);
    }
    // last_error chip (infra failure presentation)
    const errRev = {
      name: "x", path: "/x", branch: "b", head: "abc",
      needs_human: { open: 0, blocking: 0 },
      review: { last_error: true, running: false, round: 1, verdict: null },
    };
    const errHtml = api.cardHTML(errRev);
    if (!errHtml.includes("review infra error")) {
      console.error("last_error card missing infra-error chip");
      process.exit(1);
    }
    if (!errHtml.includes('class="card bad"')) {
      console.error("last_error cardTone should be bad");
      process.exit(1);
    }
    if (api.cardTone(errRev) !== "bad") {
      console.error("cardTone(last_error) expected bad");
      process.exit(1);
    }
    if (errHtml.includes("RUNNING")) {
      console.error("last_error card must not show RUNNING");
      process.exit(1);
    }
    // Steady-state failure: after cards exist, a non-OK fetch must surface detail.
    // Drive poll() with a failing fetch once cards are present.
    resolvers.length = 0;
    fetchStarts = 0;
    pending = 0;
    // Seed a successful state by resolving any prior — force poll with OK then fail.
    let failPhase = 0;
    sandbox.fetch = () => {
      fetchStarts += 1;
      return Promise.resolve({
        ok: failPhase === 0,
        status: failPhase === 0 ? 200 : 500,
        json: async () => failPhase === 0
          ? { generated_at: 2, discovery: "t", projects: [{
              name: "alpha", path: "/a", branch: "main", head: "abc",
              feedless: true, needs_human: { open: 0, blocking: 0 }, review: null,
            }] }
          : { error: "snapshot_failed", detail: "builder boom detail" },
      });
    };
    // Clear inFlight if stuck
    if (api.getPollState && api.getPollState().inFlight) {
      // allow next poll by waiting prior finally
    }
    api.poll();
    setTimeout(() => {
      const grid = sandbox.document.getElementById("grid");
      if (!grid || !grid.querySelector(".card")) {
        console.error("expected cards after successful poll before failure path");
        process.exit(1);
      }
      const cardsHtml = grid.innerHTML;
      failPhase = 1;
      api.poll();
      setTimeout(() => {
        const banner = sandbox.document.getElementById("poll-error");
        if (!banner) {
          console.error("poll-error banner was not created/inserted");
          process.exit(1);
        }
        const text = banner.textContent || "";
        if (!String(text).includes("builder boom detail")) {
          console.error("steady-state failure must show detail in banner, got:", text);
          process.exit(1);
        }
        if (banner.style.display === "none" || banner.style.display === "") {
          // production sets display:block on failure
          if (banner.style.display !== "block") {
            console.error("poll-error banner must be visible on failure, display=", banner.style.display);
            process.exit(1);
          }
        }
        // Stale cards must remain (not replaced by empty error-only grid).
        if (grid.innerHTML !== cardsHtml || !grid.querySelector(".card")) {
          console.error("steady-state failure must keep existing cards");
          process.exit(1);
        }
        // Recovery: successful poll clears the banner.
        failPhase = 0;
        api.poll();
        setTimeout(() => {
          if (banner.style.display !== "none" || (banner.textContent || "") !== "") {
            console.error("successful poll must hide and clear poll-error banner");
            process.exit(1);
          }
          // XSS escape
          const xss = api.esc('<script>"x"');
          if (xss.includes("<") || xss.includes('"')) {
            console.error("esc failed:", xss);
            process.exit(1);
          }
          console.log("ui-card-unit: OK");
        }, 0);
      }, 0);
    }, 0);
  }, 0);
}, 0);
NODE
grep -q 'ui-card-unit: OK' "$UI_OUT" \
  || { echo "smoke-snapshot: node UI unit did not print success marker" >&2; cat "$UI_OUT" >&2; exit 1; }
cat "$UI_OUT"

# Empty roots still valid JSON
export PLINTH_DASH_ROOTS="/nonexistent/path/nope"
EMPTY="$FIX/empty.json"
"$PLINTH" dash --snapshot > "$EMPTY"
jq -e '.projects == [] and has("generated_at")' "$EMPTY" >/dev/null

# ── Config-file discovery + ~/ expansion ─────────────────────────────────────
unset PLINTH_DASH_ROOTS
CFG_HOME="$FIX/home"
mkdir -p "$CFG_HOME/.config/plinth" "$FIX/Dev/tilde-proj"
# Real project under a path we will reference via ~/Dev/tilde-proj
mk_git "$FIX/Dev/tilde-proj"
# Point HOME at our fixture so ~/.config and ~/ expand into FIX.
export HOME="$CFG_HOME"
# Create a symlink so ~/Dev resolves into FIX/Dev
ln -sfn "$FIX/Dev" "$CFG_HOME/Dev"
printf '%s\n' '# comment' '~/Dev/tilde-proj' > "$CFG_HOME/.config/plinth/dashboard-projects"
CFG_OUT="$FIX/cfg.json"
"$PLINTH" dash --snapshot > "$CFG_OUT"
jq -e '.discovery == "config:~/.config/plinth/dashboard-projects"' "$CFG_OUT" >/dev/null
jq -e '(.projects | length) == 1 and .projects[0].name == "tilde-proj"' "$CFG_OUT" >/dev/null

# Default discovery via PLINTH_DASH_DEV_ROOT
rm -f "$CFG_HOME/.config/plinth/dashboard-projects"
export PLINTH_DASH_DEV_ROOT="$FIX/Dev"
DEF_OUT="$FIX/def.json"
"$PLINTH" dash --snapshot > "$DEF_OUT"
jq -e '.discovery == "default:~/Dev/*/.plinth/config"' "$DEF_OUT" >/dev/null
jq -e '(.projects | length) >= 1 and ([.projects[].name] | index("tilde-proj") != null)' "$DEF_OUT" >/dev/null

# First-match precedence: PLINTH_DASH_ROOTS wins over config file when both set.
printf '%s\n' '~/Dev/tilde-proj' > "$CFG_HOME/.config/plinth/dashboard-projects"
export PLINTH_DASH_ROOTS="$A"
PREC_OUT="$FIX/prec.json"
"$PLINTH" dash --snapshot > "$PREC_OUT"
jq -e '
  .discovery == "env:PLINTH_DASH_ROOTS"
  and (.projects | length) == 1
  and .projects[0].name == "alpha"
' "$PREC_OUT" >/dev/null
unset PLINTH_DASH_ROOTS
# Config wins over default scan (restore config; default root still set).
PREC2_OUT="$FIX/prec2.json"
"$PLINTH" dash --snapshot > "$PREC2_OUT"
jq -e '
  .discovery == "config:~/.config/plinth/dashboard-projects"
  and (.projects | length) == 1
  and .projects[0].name == "tilde-proj"
' "$PREC2_OUT" >/dev/null
rm -f "$CFG_HOME/.config/plinth/dashboard-projects"

# Glob metacharacters in PLINTH_DASH_ROOTS must not pathname-expand.
GLOB_PROJ="$FIX/proj[1]"
mk_git "$GLOB_PROJ"
export PLINTH_DASH_ROOTS="$GLOB_PROJ"
GLOB_OUT="$FIX/glob.json"
"$PLINTH" dash --snapshot > "$GLOB_OUT"
jq -e '(.projects | length) == 1 and .projects[0].name == "proj[1]"' "$GLOB_OUT" >/dev/null
# A bare glob that would expand to many paths must not pull in siblings.
export PLINTH_DASH_ROOTS="$FIX/proj*"
GLOB2="$FIX/glob2.json"
"$PLINTH" dash --snapshot > "$GLOB2"
# With set -f the literal "proj*" is not a directory → zero projects (not expanded).
jq -e '.projects == []' "$GLOB2" >/dev/null
unset PLINTH_DASH_ROOTS

# Port range validation (serve path — fails before bind with the intended
# diagnostic, not via bash "integer expression expected" / Python OverflowError).
assert_port_reject() {
  local label="$1"; shift
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || { echo "smoke-snapshot: $label should fail" >&2; exit 1; }
  printf '%s' "$out" | grep -q 'port out of range\|bad port' \
    || { echo "smoke-snapshot: $label missing clean port diagnostic:" >&2; printf '%s\n' "$out" >&2; exit 1; }
  printf '%s' "$out" | grep -qiE 'integer expression expected|OverflowError|Traceback' \
    && { echo "smoke-snapshot: $label leaked internal error:" >&2; printf '%s\n' "$out" >&2; exit 1; }
  printf '%s' "$out" | grep -q 'plinth dash: http://' \
    && { echo "smoke-snapshot: $label must not start the server:" >&2; printf '%s\n' "$out" >&2; exit 1; }
  return 0
}
assert_port_reject "--port 0" "$PLINTH" dash --port 0
assert_port_reject "--port 70000" "$PLINTH" dash --port 70000
assert_port_reject "--port oversized" "$PLINTH" dash --port 99999999999999999999999
assert_port_reject "PLINTH_DASH_PORT=0" env PLINTH_DASH_PORT=0 "$PLINTH" dash
assert_port_reject "PLINTH_DASH_PORT=notaport" env PLINTH_DASH_PORT=notaport "$PLINTH" dash
assert_port_reject "PLINTH_DASH_PORT=oversized" env PLINTH_DASH_PORT=99999999999999999999999 "$PLINTH" dash

# ── Short-lived server: loopback HTTP + single-flight / TTL ──────────────────
# Counting wrapper as PLINTH_DASH_SNAPSHOT_BIN so we can assert builder fan-in.
export PLINTH_DASH_ROOTS="$A:$I"
export HOME="$CFG_HOME"
COUNT_FILE="$FIX/snap.count"
: > "$COUNT_FILE"
WRAP="$FIX/count-plinth"
# Slow builder so concurrent GETs overlap on the single-flight lock.
cat > "$WRAP" <<WRAP
#!/usr/bin/env bash
printf '1\n' >> "$COUNT_FILE"
sleep 0.4
exec "$PLINTH" "\$@"
WRAP
chmod +x "$WRAP"
export PLINTH_DASH_SNAPSHOT_BIN="$WRAP"
SRV_PORT=18734
for try in 18734 18735 18736 18737 18738 18739 18740; do
  SRV_PORT="$try"
  if command -v lsof >/dev/null 2>&1; then
    if lsof -nP -iTCP:"$SRV_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
      continue
    fi
  fi
  break
done
if command -v setsid >/dev/null 2>&1; then
  setsid env PLINTH_DASH_SNAPSHOT_BIN="$WRAP" PLINTH_DASH_ROOTS="$A:$I" \
    "$PLINTH" dash --port "$SRV_PORT" >"$FIX/srv.out" 2>"$FIX/srv.err" &
  SRV_PID=$!
  srv_cleanup() {
    kill -TERM -"$SRV_PID" 2>/dev/null || true
    kill -TERM "$SRV_PID" 2>/dev/null || true
    wait "$SRV_PID" 2>/dev/null || true
    if command -v lsof >/dev/null 2>&1; then
      local p; p="$(lsof -tiTCP:"$SRV_PORT" -sTCP:LISTEN 2>/dev/null || true)"
      [ -n "$p" ] && kill -TERM $p 2>/dev/null || true
    fi
  }
else
  env PLINTH_DASH_SNAPSHOT_BIN="$WRAP" PLINTH_DASH_ROOTS="$A:$I" \
    "$PLINTH" dash --port "$SRV_PORT" >"$FIX/srv.out" 2>"$FIX/srv.err" &
  SRV_PID=$!
  srv_cleanup() {
    local kids
    kids="$(pgrep -P "$SRV_PID" 2>/dev/null || true)"
    [ -n "$kids" ] && kill -TERM $kids 2>/dev/null || true
    kill -TERM "$SRV_PID" 2>/dev/null || true
    wait "$SRV_PID" 2>/dev/null || true
    if command -v lsof >/dev/null 2>&1; then
      local p; p="$(lsof -tiTCP:"$SRV_PORT" -sTCP:LISTEN 2>/dev/null || true)"
      [ -n "$p" ] && kill -TERM $p 2>/dev/null || true
    fi
  }
fi
trap 'srv_cleanup; cleanup' EXIT
ready=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if curl -sf "http://127.0.0.1:${SRV_PORT}/api/snapshot" >/dev/null 2>&1; then
    ready=1; break
  fi
  if ! kill -0 "$SRV_PID" 2>/dev/null; then
    echo "smoke-snapshot: server exited early:" >&2
    cat "$FIX/srv.err" >&2 || true
    exit 1
  fi
  sleep 0.15
done
[ "$ready" = 1 ] || { echo "smoke-snapshot: server did not become ready on :$SRV_PORT" >&2; cat "$FIX/srv.err" >&2; exit 1; }
# Expire the warm-up TTL (2.5s), then assert concurrent + within-TTL share one build.
sleep 3
: > "$COUNT_FILE"
# Concurrent requests after expiry → exactly one builder invocation.
# Wait only on the curl PIDs — bare `wait` would also wait for the server job.
# Require each curl to succeed (no || true on failures).
curl -sf --max-time 60 "http://127.0.0.1:${SRV_PORT}/api/snapshot" -o "$FIX/c1.json" & c1=$!
curl -sf --max-time 60 "http://127.0.0.1:${SRV_PORT}/api/snapshot" -o "$FIX/c2.json" & c2=$!
curl -sf --max-time 60 "http://127.0.0.1:${SRV_PORT}/api/snapshot" -o "$FIX/c3.json" & c3=$!
wait "$c1" || { echo "smoke-snapshot: concurrent curl 1 failed" >&2; exit 1; }
wait "$c2" || { echo "smoke-snapshot: concurrent curl 2 failed" >&2; exit 1; }
wait "$c3" || { echo "smoke-snapshot: concurrent curl 3 failed" >&2; exit 1; }
for f in "$FIX/c1.json" "$FIX/c2.json" "$FIX/c3.json"; do
  jq -e 'has("projects")' "$f" >/dev/null \
    || { echo "smoke-snapshot: concurrent response not JSON: $f" >&2; exit 1; }
done
# One more within TTL should still hit cache (no second builder call)
curl -sf --max-time 60 "http://127.0.0.1:${SRV_PORT}/api/snapshot" > "$FIX/api.json" \
  || { echo "smoke-snapshot: follow-up curl failed" >&2; exit 1; }
hits="$(wc -l < "$COUNT_FILE" | tr -d ' ')"
[ "$hits" = "1" ] || { echo "smoke-snapshot: expected 1 builder call within TTL, got $hits" >&2; exit 1; }
jq -e '
  (.projects | length) == 2
  and ([.projects[] | select(.name == "iota-badverdict")
        | .error == "snapshot_render_failed"
        and .needs_human.open == 1] | any)
' "$FIX/api.json" >/dev/null
# Static UI
curl -sf "http://127.0.0.1:${SRV_PORT}/" | grep -q 'Plinth dashboard' \
  || { echo "smoke-snapshot: / did not serve the UI" >&2; exit 1; }
# Read-only
post_code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:${SRV_PORT}/" || true)"
[ "$post_code" = "405" ] || { echo "smoke-snapshot: POST should be 405, got $post_code" >&2; exit 1; }
# Unknown path
nf_code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${SRV_PORT}/nope" || true)"
[ "$nf_code" = "404" ] || { echo "smoke-snapshot: unknown path should be 404, got $nf_code" >&2; exit 1; }
# Banner claims loopback
grep -q '127.0.0.1' "$FIX/srv.out" \
  || { echo "smoke-snapshot: server banner missing 127.0.0.1" >&2; exit 1; }
# Behavioral bind: listener is on 127.0.0.1, not 0.0.0.0 / *
if command -v lsof >/dev/null 2>&1; then
  bind_info="$(lsof -nP -iTCP:"$SRV_PORT" -sTCP:LISTEN 2>/dev/null || true)"
  printf '%s\n' "$bind_info" | grep -q "127.0.0.1:${SRV_PORT}" \
    || { echo "smoke-snapshot: listener not on 127.0.0.1:$SRV_PORT:" >&2; printf '%s\n' "$bind_info" >&2; exit 1; }
  if printf '%s\n' "$bind_info" | grep -qE "0\\.0\\.0\\.0:${SRV_PORT}|\\*:${SRV_PORT}"; then
    echo "smoke-snapshot: listener appears non-loopback:" >&2
    printf '%s\n' "$bind_info" >&2
    exit 1
  fi
fi
# DNS-rebinding: hostile Host rejected; documented loopback Host forms accepted.
host_code="$(curl -s -o /dev/null -w '%{http_code}' \
  -H "Host: attacker.example:${SRV_PORT}" \
  "http://127.0.0.1:${SRV_PORT}/api/snapshot" || true)"
[ "$host_code" = "400" ] || { echo "smoke-snapshot: hostile Host should be 400, got $host_code" >&2; exit 1; }
for okhost in "127.0.0.1:${SRV_PORT}" "localhost:${SRV_PORT}" "[::1]:${SRV_PORT}" "[::1]"; do
  hc="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: ${okhost}" \
    "http://127.0.0.1:${SRV_PORT}/api/snapshot" || true)"
  [ "$hc" = "200" ] || { echo "smoke-snapshot: Host $okhost should be 200, got $hc" >&2; exit 1; }
done
for badhost in "[::1]attacker.example" "[::1]@evil.example" "[::1]:notaport" "127.0.0.1:abc"; do
  bc="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: ${badhost}" \
    "http://127.0.0.1:${SRV_PORT}/api/snapshot" || true)"
  [ "$bc" = "400" ] || { echo "smoke-snapshot: Host $badhost should be 400, got $bc" >&2; exit 1; }
done
# Failing builder surfaces detail and shares one flight (count invocations)
FAIL_COUNT="$FIX/fail.count"
: > "$FAIL_COUNT"
FAIL_WRAP="$FIX/fail-plinth"
cat > "$FAIL_WRAP" <<FAIL
#!/usr/bin/env bash
printf '1\n' >> "$FAIL_COUNT"
echo "builder boom detail" >&2
exit 7
FAIL
chmod +x "$FAIL_WRAP"
FAIL_PORT=$((SRV_PORT + 1))
env PLINTH_DASH_SNAPSHOT_BIN="$FAIL_WRAP" PLINTH_DASH_ROOTS="$A" \
  "$PLINTH" dash --port "$FAIL_PORT" >"$FIX/fail.out" 2>"$FIX/fail.err" &
FAIL_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:${FAIL_PORT}/" 2>/dev/null || true)"
  [ "$code" = "200" ] && break
  kill -0 "$FAIL_PID" 2>/dev/null || break
  sleep 0.15
done
: > "$FAIL_COUNT"
ferr1="$(curl -s --max-time 30 "http://127.0.0.1:${FAIL_PORT}/api/snapshot" || true)"
ferr2="$(curl -s --max-time 30 "http://127.0.0.1:${FAIL_PORT}/api/snapshot" || true)"
printf '%s' "$ferr1" | jq -e '.error == "snapshot_failed" and (.detail | test("boom"))' >/dev/null \
  || { echo "smoke-snapshot: fail detail missing: $ferr1" >&2; exit 1; }
printf '%s' "$ferr2" | jq -e '.error == "snapshot_failed"' >/dev/null \
  || { echo "smoke-snapshot: second fail response bad: $ferr2" >&2; exit 1; }
fhits="$(wc -l < "$FAIL_COUNT" | tr -d ' ')"
[ "$fhits" = "1" ] || { echo "smoke-snapshot: expected 1 fail-builder call (shared err TTL), got $fhits" >&2; exit 1; }
kill "$FAIL_PID" 2>/dev/null || true
wait "$FAIL_PID" 2>/dev/null || true
# Also terminate any leftover fail-port listener from this smoke only
if command -v lsof >/dev/null 2>&1; then
  fp="$(lsof -tiTCP:"$FAIL_PORT" -sTCP:LISTEN 2>/dev/null || true)"
  [ -n "$fp" ] && kill -TERM $fp 2>/dev/null || true
fi
srv_cleanup
if command -v lsof >/dev/null 2>&1; then
  if lsof -nP -iTCP:"$SRV_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "smoke-snapshot: server still listening on :$SRV_PORT after cleanup" >&2
    exit 1
  fi
fi
trap cleanup EXIT

echo "smoke-snapshot: OK"
