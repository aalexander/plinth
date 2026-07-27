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
# Config seats must surface even when no live transcript model exists.
printf '%s\n' \
  'spec_path = SPEC.md' \
  'reviewer_vendor = codex' \
  'reviewer_model_tier1 = gpt-t1' \
  'reviewer_model_tier2 = gpt-t2' \
  'audit_vendor = claude' \
  'audit_model = opus' \
  'advisor_vendor = claude' \
  'advisor_model = fable' \
  'advisor_model_max = fable-max' \
  > "$A/.plinth/config"
git -C "$A" checkout -qb feat/dash
echo x > "$A/f.txt"
git -C "$A" add -A
git -C "$A" commit -qm "work"
HEAD="$(git -C "$A" rev-parse --short HEAD)"
FULL="$(git -C "$A" rev-parse HEAD)"

NOW="$(date +%s)"
# Active-SID phase chain (event-gap heuristic):
# SessionStart → +10s UserPromptSubmit (gap → other) → +30s Edit (coding) →
# +20s Read (research) → other-sid noise → +30s advise Bash (advising).
jq -nc --argjson epoch "$((NOW - 100))" \
  '{ts:"2026-01-01T00:00:00Z",epoch:$epoch,event:"SessionStart",sid:"sid-smoke",transcript:null,tool:null,detail:null,rc:null}' \
  > "$A/.plinth/session/events.jsonl"
jq -nc --argjson epoch "$((NOW - 90))" \
  '{ts:"2026-01-01T00:00:10Z",epoch:$epoch,event:"UserPromptSubmit",sid:"sid-smoke",transcript:null,tool:null,detail:"smoke dashboard task",rc:null}' \
  >> "$A/.plinth/session/events.jsonl"
jq -nc --argjson epoch "$((NOW - 60))" \
  '{ts:"2026-01-01T00:00:40Z",epoch:$epoch,event:"PostToolUse",sid:"sid-smoke",transcript:null,tool:"Edit",detail:"f.txt",rc:0}' \
  >> "$A/.plinth/session/events.jsonl"
jq -nc --argjson epoch "$((NOW - 40))" \
  '{ts:"2026-01-01T00:01:00Z",epoch:$epoch,event:"PostToolUse",sid:"sid-smoke",transcript:null,tool:"Read",detail:"f.txt",rc:0}' \
  >> "$A/.plinth/session/events.jsonl"
# Noise SID must not pollute active phases
jq -nc --argjson epoch "$((NOW - 30))" \
  '{ts:"2026-01-01T00:01:10Z",epoch:$epoch,event:"PostToolUse",sid:"other-sid",transcript:null,tool:"Bash",detail:"gh pr view",rc:0}' \
  >> "$A/.plinth/session/events.jsonl"
# Return to active SID
jq -nc --argjson epoch "$((NOW - 10))" \
  '{ts:"2026-01-01T00:01:30Z",epoch:$epoch,event:"PostToolUse",sid:"sid-smoke",transcript:null,tool:"Bash",detail:"./plinth advise x",rc:0}' \
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
# ── Fixture C2: UNBOUND (pending Tier-2 confirmation) must NOT error the card ─
C2="$FIX/gamma-unbound"
mk_git "$C2"
git -C "$C2" checkout -qb feat/unbound
echo ub > "$C2/u.txt"
git -C "$C2" add -A
git -C "$C2" commit -qm "work"
UBSHA="$(git -C "$C2" rev-parse HEAD)"
mkdir -p "$C2/.plinth/session/review/feat-unbound"
jq -nc --arg sha "$UBSHA" \
  '{verdict:"UNBOUND",unbound_reason:"Tier-2 clean-slate confirmation not yet complete",sha:$sha,round:2,mode:"verify",model:"gpt-test"}' \
  > "$C2/.plinth/session/review/feat-unbound/verdict.json"
mkdir -p "$C2/.plinth/session"
printf '{"event":"SessionStart","sid":"s1","epoch":1}\n' > "$C2/.plinth/session/events.jsonl"

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

# ── Fixture L: stale verdict (SHA deliberately wrong but well-formed hex) ────
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

# ── Fixture L2: parseable-but-invalid verdict enum → error card ──────────────
L2="$FIX/mu-badenum"
mk_git "$L2"
git -C "$L2" checkout -qb feat/badenum
echo l2 > "$L2/l2.txt"
git -C "$L2" add -A
git -C "$L2" commit -qm "work"
mkdir -p "$L2/.plinth/session/review/feat-badenum"
jq -nc '{verdict:"NOT_A_VERDICT",round:1,sha:"abcdef0"}' \
  > "$L2/.plinth/session/review/feat-badenum/verdict.json"

# ── Fixture L3: missing verdict field → error ────────────────────────────────
L3="$FIX/mu-missingv"
mk_git "$L3"
git -C "$L3" checkout -qb feat/missv
echo l3 > "$L3/l3.txt"
git -C "$L3" add -A
git -C "$L3" commit -qm "work"
mkdir -p "$L3/.plinth/session/review/feat-missv"
jq -nc '{round:1,sha:"abcdef0123456789"}' \
  > "$L3/.plinth/session/review/feat-missv/verdict.json"

# ── Fixture L4: parseable event with bad epoch type → error ──────────────────
L4="$FIX/mu-badevent"
mk_git "$L4"
printf '%s\n' '{"event":"SessionStart","sid":"s","epoch":"not-a-number","transcript":null}' \
  > "$L4/.plinth/session/events.jsonl"

# ── Fixture L5: present verdict.json is JSON null → error ────────────────────
L5="$FIX/mu-nullverdict"
mk_git "$L5"
git -C "$L5" checkout -qb feat/nullv
echo l5 > "$L5/l5.txt"
git -C "$L5" add -A
git -C "$L5" commit -qm "work"
mkdir -p "$L5/.plinth/session/review/feat-nullv"
printf 'null\n' > "$L5/.plinth/session/review/feat-nullv/verdict.json"

# ── Fixture L6: event with non-string detail → error ─────────────────────────
L6="$FIX/mu-baddetail"
mk_git "$L6"
printf '%s\n' '{"event":"UserPromptSubmit","sid":"s","epoch":1,"detail":123}' \
  > "$L6/.plinth/session/events.jsonl"

# ── Fixture L7: unknown event name → error ───────────────────────────────────
L7="$FIX/mu-badevname"
mk_git "$L7"
printf '%s\n' '{"event":"TotallyUnknown","sid":"s","epoch":1}' \
  > "$L7/.plinth/session/events.jsonl"

# ── Fixture L8: multi-doc verdict (null then object) → error ──────────────────
L8="$FIX/mu-multiv"
mk_git "$L8"
git -C "$L8" checkout -qb feat/multiv
echo l8 > "$L8/l8.txt"
git -C "$L8" add -A
git -C "$L8" commit -qm "work"
mkdir -p "$L8/.plinth/session/review/feat-multiv"
printf 'null\n{"verdict":"APPROVED","sha":"abcdef0123456789","round":1}\n' \
  > "$L8/.plinth/session/review/feat-multiv/verdict.json"

# ── Fixture L9: present JSON false verdict → error ───────────────────────────
L9="$FIX/mu-falsev"
mk_git "$L9"
git -C "$L9" checkout -qb feat/falsev
echo l9 > "$L9/l9.txt"
git -C "$L9" add -A
git -C "$L9" commit -qm "work"
mkdir -p "$L9/.plinth/session/review/feat-falsev"
printf 'false\n' > "$L9/.plinth/session/review/feat-falsev/verdict.json"

# Multi-doc matrix: object then null/false; false then object
L10="$FIX/mu-objnull"; mk_git "$L10"
git -C "$L10" checkout -qb feat/objnull; echo x > "$L10/x"; git -C "$L10" add -A; git -C "$L10" commit -qm w
mkdir -p "$L10/.plinth/session/review/feat-objnull"
printf '{"verdict":"APPROVED","sha":"abcdef0123456789","round":1}\nnull\n' \
  > "$L10/.plinth/session/review/feat-objnull/verdict.json"
L11="$FIX/mu-objfalse"; mk_git "$L11"
git -C "$L11" checkout -qb feat/objfalse; echo x > "$L11/x"; git -C "$L11" add -A; git -C "$L11" commit -qm w
mkdir -p "$L11/.plinth/session/review/feat-objfalse"
printf '{"verdict":"APPROVED","sha":"abcdef0123456789","round":1}\nfalse\n' \
  > "$L11/.plinth/session/review/feat-objfalse/verdict.json"
L12="$FIX/mu-falseobj"; mk_git "$L12"
git -C "$L12" checkout -qb feat/falseobj; echo x > "$L12/x"; git -C "$L12" add -A; git -C "$L12" commit -qm w
mkdir -p "$L12/.plinth/session/review/feat-falseobj"
printf 'false\n{"verdict":"APPROVED","sha":"abcdef0123456789","round":1}\n' \
  > "$L12/.plinth/session/review/feat-falseobj/verdict.json"

# Missing event name / non-string event name / empty object
L13="$FIX/mu-noevent"; mk_git "$L13"
printf '%s\n' '{"sid":"s","epoch":1}' > "$L13/.plinth/session/events.jsonl"
L14="$FIX/mu-numevent"; mk_git "$L14"
printf '%s\n' '{"event":1,"sid":"s","epoch":1}' > "$L14/.plinth/session/events.jsonl"
L15="$FIX/mu-emptyobj"; mk_git "$L15"
printf '%s\n' '{}' > "$L15/.plinth/session/events.jsonl"

# Healthy guard_block + PreCompact + full allowlist must NOT fail the card
L16="$FIX/mu-healthyhooks"; mk_git "$L16"
NOW_H=$NOW
{
  jq -nc --argjson epoch "$NOW_H" \
    '{event:"SessionStart",sid:"sid-h",epoch:$epoch,transcript:null,tool:null,detail:null}'
  jq -nc --argjson epoch "$((NOW_H+1))" \
    '{event:"guard_block",sid:null,epoch:$epoch,tool:"Bash",detail:"blocked"}'
  jq -nc --argjson epoch "$((NOW_H+2))" \
    '{event:"PreToolUse",sid:"sid-h",epoch:$epoch,tool:"Bash",detail:null}'
  jq -nc --argjson epoch "$((NOW_H+3))" \
    '{event:"PostToolUse",sid:"sid-h",epoch:$epoch,tool:"Bash",detail:"ok",rc:0}'
  jq -nc --argjson epoch "$((NOW_H+4))" \
    '{event:"SubagentStop",sid:"sid-h",epoch:$epoch,transcript:null,tool:null,detail:null}'
  jq -nc --argjson epoch "$((NOW_H+5))" \
    '{event:"PreCompact",sid:"sid-h",epoch:$epoch,transcript:null,tool:null,detail:null}'
  jq -nc --argjson epoch "$((NOW_H+6))" \
    '{event:"Stop",sid:"sid-h",epoch:$epoch,transcript:null,tool:null,detail:null}'
  jq -nc --argjson epoch "$((NOW_H+7))" \
    '{event:"gate_release",sid:"sid-h",epoch:$epoch,tool:null,detail:"released"}'
  jq -nc --argjson epoch "$((NOW_H+8))" \
    '{event:"unknown",sid:"sid-h",epoch:$epoch,transcript:null,tool:null,detail:null}'
} > "$L16/.plinth/session/events.jsonl"

# SHA-256 object-format repo with APPROVED-at-HEAD (64-hex sha)
HAVE_SHA256=0
L17="$FIX/mu-sha256"
mkdir -p "$L17/.plinth/session"
printf 'spec_path = SPEC.md\n' > "$L17/.plinth/config"
if git -C "$L17" init -q --object-format=sha256 2>/dev/null; then
  git -C "$L17" config user.email "smoke@plinth.test"
  git -C "$L17" config user.name "plinth smoke"
  echo ok > "$L17/README"
  git -C "$L17" add -A && git -C "$L17" commit -qm "init"
  git -C "$L17" checkout -qb feat/sha256
  echo s > "$L17/s.txt"
  git -C "$L17" add -A && git -C "$L17" commit -qm "work"
  S256="$(git -C "$L17" rev-parse HEAD)"
  mkdir -p "$L17/.plinth/session/review/feat-sha256"
  jq -nc --arg sha "$S256" \
    '{verdict:"APPROVED",sha:$sha,round:1,mode:"fresh",model:"gpt-test",
      risk:{tier:1,files:1,reasons:["test"]},ts:"2026-01-01T00:00:00Z"}' \
    > "$L17/.plinth/session/review/feat-sha256/verdict.json"
  HAVE_SHA256=1
else
  rm -rf "$L17"
fi

# Extra protocol-shape rejects: scalar event, bad sid, bad transcript, empty verdict,
# non-string verdict enum, missing/non-string/non-hex sha
L18="$FIX/mu-scalarev"; mk_git "$L18"
printf '42\n' > "$L18/.plinth/session/events.jsonl"
L19="$FIX/mu-badsid"; mk_git "$L19"
printf '%s\n' '{"event":"SessionStart","sid":1,"epoch":1}' > "$L19/.plinth/session/events.jsonl"
L20="$FIX/mu-badtr"; mk_git "$L20"
printf '%s\n' '{"event":"SessionStart","sid":"s","epoch":1,"transcript":99}' > "$L20/.plinth/session/events.jsonl"
L21="$FIX/mu-emptyverdict"; mk_git "$L21"
git -C "$L21" checkout -qb feat/emptyv; echo e > "$L21/e"; git -C "$L21" add -A; git -C "$L21" commit -qm w
mkdir -p "$L21/.plinth/session/review/feat-emptyv"
: > "$L21/.plinth/session/review/feat-emptyv/verdict.json"
L22="$FIX/mu-numverdict"; mk_git "$L22"
git -C "$L22" checkout -qb feat/numv; echo e > "$L22/e"; git -C "$L22" add -A; git -C "$L22" commit -qm w
mkdir -p "$L22/.plinth/session/review/feat-numv"
printf '{"verdict":1,"sha":"abcdef0","round":1}\n' > "$L22/.plinth/session/review/feat-numv/verdict.json"
L23="$FIX/mu-nosha"; mk_git "$L23"
git -C "$L23" checkout -qb feat/nosha; echo e > "$L23/e"; git -C "$L23" add -A; git -C "$L23" commit -qm w
mkdir -p "$L23/.plinth/session/review/feat-nosha"
printf '{"verdict":"APPROVED","round":1}\n' > "$L23/.plinth/session/review/feat-nosha/verdict.json"
L24="$FIX/mu-numsha"; mk_git "$L24"
git -C "$L24" checkout -qb feat/numsha; echo e > "$L24/e"; git -C "$L24" add -A; git -C "$L24" commit -qm w
mkdir -p "$L24/.plinth/session/review/feat-numsha"
printf '{"verdict":"APPROVED","sha":1234567,"round":1}\n' > "$L24/.plinth/session/review/feat-numsha/verdict.json"
L25="$FIX/mu-badhex"; mk_git "$L25"
git -C "$L25" checkout -qb feat/badhex; echo e > "$L25/e"; git -C "$L25" add -A; git -C "$L25" commit -qm w
mkdir -p "$L25/.plinth/session/review/feat-badhex"
printf '{"verdict":"APPROVED","sha":"not-hex!!","round":1}\n' > "$L25/.plinth/session/review/feat-badhex/verdict.json"

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

# Never hit live vendor CLIs in smoke (quota is optional / cached separately).
export PLINTH_DASH_QUOTA=0
export PLINTH_DASH_ROOTS="$A:$B:$C:$C2:$D:$E:$F:$G:$H:$I:$J:$J2:$K:$L:$L2:$L3:$L4:$L5:$L6:$L7:$L8:$L9:$L10:$L11:$L12:$L13:$L14:$L15:$L16"
if [ "${HAVE_SHA256:-0}" = "1" ]; then
  export PLINTH_DASH_ROOTS="$PLINTH_DASH_ROOTS:$L17"
fi
export PLINTH_DASH_ROOTS="$PLINTH_DASH_ROOTS:$L18:$L19:$L20:$L21:$L22:$L23:$L24:$L25:$M:$N:$N2:$O:$P:$Q"
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
# Base 35 (incl. gamma-unbound) + 8 extra protocol fixtures (L18–L25) + optional sha256
EXPECTED_N=43
[ "${HAVE_SHA256:-0}" = "1" ] && EXPECTED_N=44
jq -e --argjson n "$EXPECTED_N" '(.projects | length) == $n' "$OUT" >/dev/null

# Top-level vendor quota: smoke disables probes; snapshot never spawns CLIs.
jq -e '
  .quota != null
  and .quota.available == false
  and (.quota.skipped == true or .quota.offline == true)
' "$OUT" >/dev/null

# Alpha assertions
jq -e --arg head "$HEAD" '
  .projects[] | select(.name == "alpha")
  | .branch == "feat/dash"
  and .head == $head
  and .feedless == false
  and .needs_human.open == 2
  and .needs_human.blocking == 1
  and (.needs_human.items | type == "array")
  and (.needs_human.items | length) == 2
  and (.needs_human.items | map(select(.blocking == true)) | length) == 1
  and .needs_human.truncated == false
  and .review.verdict == "CHANGES_NEEDED"
  and .review.round == 2
  and .review.stale == false
  and .review.running == false
  and .task == "smoke dashboard task"
  and .quota.available == false
  and (.quota.note | type == "string")
  and (.models.live | type == "object")
  and (.models.seats | type == "object")
  and .models.seats.reviewer_vendor == "codex"
  and .models.seats.reviewer_tier1 == "gpt-t1"
  and .models.seats.reviewer_tier2 == "gpt-t2"
  and .models.seats.audit_vendor == "claude"
  and .models.seats.audit_model == "opus"
  and .models.seats.advisor_vendor == "claude"
  and .models.seats.advisor_model == "fable"
  and .models.seats.advisor_model_max == "fable-max"
  # Live reviewer from verdict.model only (request has no model; not seat fallback).
  and .models.live.reviewer == "gpt-test"
  and .model_reviewer == "gpt-test"
  and .needs_human.source == ".plinth/NEEDS-HUMAN.md"
  and (.phases | type == "object")
  # Event-gap heuristic: Edit 30s (90→60), Read 20s (60→40); other-sid ignored;
  # return-to-active Bash advise credits the gap since last same-SID event (30s).
  and .phases.coding == 30
  and .phases.research == 20
  and .phases.advising == 30
  and ((.phases.ci // 0) == 0)
  and (.review_round_secs | type == "number")
  and ((.phases.other // 0) == 10)
  and (.activity_secs_ago != null)
  and (.activity_secs_ago | type == "number")
  and .activity_secs_ago >= 0
  and .activity_secs_ago < 120
  and (.error == null or .error == "")
' "$OUT" >/dev/null

# Quota: offline snapshot reads cache; probe path parses CLI with fake claude.
QFIX="$FIX/quota-cache.json"
NOWQ="$(date +%s)"
jq -nc --argjson now "$NOWQ" '{
  available:true, refreshed_at:$now,
  overall:{vendor:"claude",window:"week_all_models",used_pct:80,remaining_pct:20,
           reset_text:"Jul 30 at 9am",projected_100pct_at:($now+14400),rate_pct_per_hour:5},
  vendors:[{vendor:"claude",available:true,windows:[{window:"week_all_models",used_pct:80,reset_text:"Jul 30"}]}],
  history:[{t:($now-7200),week_all_models_pct:70},{t:$now,week_all_models_pct:80}]
}' > "$QFIX"
QOUT="$FIX/quota-out.json"
PLINTH_DASH_QUOTA_CACHE="$QFIX" PLINTH_DASH_QUOTA=1 \
  PLINTH_DASH_ROOTS="$B" "$PLINTH" dash --snapshot > "$QOUT"
jq -e '
  .quota.available == true
  and .quota.overall.used_pct == 80
  and .quota.overall.projected_100pct_at != null
  and (.quota.offline != true)
' "$QOUT" >/dev/null
# Snapshot must stay offline with empty cache (no CLI spawn)
PLINTH_DASH_QUOTA_CACHE="$FIX/no-such-quota.json" \
  PLINTH_DASH_QUOTA=1 PLINTH_DASH_ROOTS="$B" "$PLINTH" dash --snapshot \
  | jq -e '.quota.available == false and (.quota.offline == true or .quota.skipped == true)' >/dev/null
# Live probe: fake claude + history → parse week_all_models + project rate
QBIN="$FIX/qbin"; mkdir -p "$QBIN"
cat > "$QBIN/claude" <<'C'
#!/usr/bin/env python3
import json
print(json.dumps({"result":
"Current session: 3% used · resets Jul 27 at 11:20am (America/Puerto_Rico)\n"
"Current week (all models): 80% used · resets Jul 30 at 9am (America/Puerto_Rico)\n"}))
C
chmod +x "$QBIN/claude"
QHIST="$FIX/quota-hist.json"
jq -nc --argjson now "$NOWQ" '{
  available:false, refreshed_at:($now-10000),
  history:[{t:($now-7200),week_all_models_pct:70,reset_text:"Jul 30 at 9am (America/Puerto_Rico)"},{t:($now-3600),week_all_models_pct:75,reset_text:"Jul 30 at 9am (America/Puerto_Rico)"}],
  vendors:[]
}' > "$QHIST"
QPROBE="$FIX/quota-probe.json"
PATH="$QBIN:/usr/bin:/bin" PLINTH_DASH_QUOTA_CACHE="$QHIST" \
  PLINTH_DASH_QUOTA=1 PLINTH_DASH_QUOTA_TTL=0 \
  PLINTH_DASH_ROOTS="$B" "$PLINTH" dash --snapshot-with-quota > "$QPROBE"
jq -e '
  .quota.available == true
  and .quota.overall.used_pct == 80
  # Rate/projection tolerate a few seconds of setup clock skew on history ages.
  and (.quota.overall.rate_pct_per_hour | type == "number")
  and .quota.overall.rate_pct_per_hour >= 4
  and .quota.overall.rate_pct_per_hour <= 6
  and ((.quota.overall.projected_100pct_at - .quota.refreshed_at) >= 14000)
  and ((.quota.overall.projected_100pct_at - .quota.refreshed_at) <= 15000)
  and ([.quota.vendors[] | select(.vendor=="claude" and .available==true)] | length) == 1
' "$QPROBE" >/dev/null
# parse_failed: successful CLI, unmatchable text
cat > "$QBIN/claude" <<'C'
#!/usr/bin/env python3
import json
print(json.dumps({"result":"no usage numbers here"}))
C
chmod +x "$QBIN/claude"
PATH="$QBIN:/usr/bin:/bin" PLINTH_DASH_QUOTA_CACHE="$FIX/quota-empty2.json" \
  PLINTH_DASH_QUOTA=1 PLINTH_DASH_QUOTA_TTL=0 \
  PLINTH_DASH_ROOTS="$B" "$PLINTH" dash --snapshot-with-quota \
  | jq -e '[.quota.vendors[] | select(.vendor=="claude" and .error=="parse_failed")] | length == 1' >/dev/null
# parse_failed: empty stdout
cat > "$QBIN/claude" <<'C'
#!/bin/sh
exit 0
C
chmod +x "$QBIN/claude"
PATH="$QBIN:/usr/bin:/bin" PLINTH_DASH_QUOTA_CACHE="$FIX/quota-empty3.json" \
  PLINTH_DASH_QUOTA=1 PLINTH_DASH_QUOTA_TTL=0 \
  PLINTH_DASH_ROOTS="$B" "$PLINTH" dash --snapshot-with-quota \
  | jq -e '[.quota.vendors[] | select(.vendor=="claude" and .error=="parse_failed")] | length == 1' >/dev/null
# CLI timeout → cli_timeout
cat > "$QBIN/claude" <<'C'
#!/bin/sh
sleep 30
exit 0
C
chmod +x "$QBIN/claude"
PATH="$QBIN:/usr/bin:/bin" PLINTH_DASH_QUOTA_CACHE="$FIX/quota-to.json" \
  PLINTH_DASH_QUOTA=1 PLINTH_DASH_QUOTA_TTL=0 \
  PLINTH_DASH_QUOTA_TIMEOUT=1 PLINTH_DASH_ROOTS="$B" "$PLINTH" dash --snapshot-with-quota \
  | jq -e '[.quota.vendors[] | select(.vendor=="claude" and .error=="cli_timeout")] | length == 1' >/dev/null
# Offline snapshot must NOT spawn claude (sentinel file)
SENT="$FIX/claude-called"
rm -f "$SENT"
cat > "$QBIN/claude" <<C
#!/bin/sh
echo called > "$SENT"
exit 0
C
chmod +x "$QBIN/claude"
PATH="$QBIN:/usr/bin:/bin" PLINTH_DASH_QUOTA_CACHE="$FIX/quota-offline-sent.json" \
  PLINTH_DASH_QUOTA=1 PLINTH_DASH_ROOTS="$B" \
  "$PLINTH" dash --snapshot >/dev/null
[ ! -f "$SENT" ] || { echo "smoke-snapshot: offline snapshot spawned claude" >&2; exit 1; }

# Public --snapshot cannot be forced online via legacy/env knobs
PATH="$QBIN:/usr/bin:/bin" PLINTH_DASH_QUOTA_CACHE="$FIX/quota-forge.json" \
  PLINTH_DASH_QUOTA=1 PLINTH_DASH_QUOTA_PROBE=1 PLINTH_DASH_SERVE_CHILD=1 \
  _DASH_QUOTA_ALLOW_PROBE=1 PLINTH_DASH_ROOTS="$B" \
  "$PLINTH" dash --snapshot >/dev/null
[ ! -f "$SENT" ] || { echo "smoke-snapshot: public --snapshot spawned claude under env force" >&2; exit 1; }

# Legacy root NEEDS-HUMAN.md source label
LEGNH="$FIX/legacy-nh"
mk_git "$LEGNH"
printf '%s\n' '- [ ] legacy open item' > "$LEGNH/NEEDS-HUMAN.md"
export PLINTH_DASH_ROOTS="$LEGNH"
"$PLINTH" dash --snapshot | jq -e '
  .projects[] | select(.name == "legacy-nh")
  | .needs_human.open == 1
  and .needs_human.source == "NEEDS-HUMAN.md"
' >/dev/null
# >50 open items → truncated=true, items length 50
T50="$FIX/tau-nh50"
mk_git "$T50"
{
  echo '# Queue'
  i=1
  while [ "$i" -le 55 ]; do
    echo "- [ ] item number $i"
    i=$((i + 1))
  done
} > "$T50/.plinth/NEEDS-HUMAN.md"
export PLINTH_DASH_ROOTS="$T50"
"$PLINTH" dash --snapshot | jq -e '
  .projects[] | select(.name == "tau-nh50")
  | .needs_human.open == 55
  and .needs_human.truncated == true
  and (.needs_human.items | length) == 50
' >/dev/null
# CI classification + PreToolUse + large gap drop + planning + reviewing
PH2="$FIX/phi-phases"
mk_git "$PH2"
git -C "$PH2" checkout -qb feat/ph
echo p > "$PH2/p.txt"; git -C "$PH2" add -A; git -C "$PH2" commit -qm w
NOWP="$(date +%s)"
mkdir -p "$PH2/.plinth/session"
{
  jq -nc --argjson e "$((NOWP-4000))" '{epoch:$e,event:"SessionStart",sid:"s1",tool:null,detail:null}'
  # gap 4000s should drop (>=3600)
  jq -nc --argjson e "$((NOWP-100))" '{epoch:$e,event:"UserPromptSubmit",sid:"s1",tool:null,detail:"plan it"}'
  jq -nc --argjson e "$((NOWP-90))" '{epoch:$e,event:"PreToolUse",sid:"s1",tool:"Bash",detail:"gh pr view 1"}'
  jq -nc --argjson e "$((NOWP-70))" '{epoch:$e,event:"PostToolUse",sid:"s1",tool:"Bash",detail:"gh pr view 1",rc:0}'
  jq -nc --argjson e "$((NOWP-40))" '{epoch:$e,event:"PostToolUse",sid:"s1",tool:"Bash",detail:"./.plinth/review.sh",rc:0}'
} > "$PH2/.plinth/session/events.jsonl"
export PLINTH_DASH_ROOTS="$PH2"
"$PLINTH" dash --snapshot | jq -e '
  .projects[] | select(.name == "phi-phases")
  | ((.phases.other // 0) == 0)   # 4000s gap dropped
  and (.phases.planning == 10)    # prompt→PreToolUse
  and (.phases.ci == 20)          # Pre→Post Bash gh
  and (.phases.reviewing == 30)   # PostToolUse review.sh gap 70→40
' >/dev/null
# shell stage (plain Bash, not review/advise/gh)
SHP="$FIX/shell-phase"
mk_git "$SHP"
git -C "$SHP" checkout -qb feat/sh
echo s > "$SHP/s.txt"; git -C "$SHP" add -A; git -C "$SHP" commit -qm w
NOWS="$(date +%s)"
mkdir -p "$SHP/.plinth/session"
{
  jq -nc --argjson e "$((NOWS-40))" '{epoch:$e,event:"SessionStart",sid:"s",tool:null,detail:null}'
  jq -nc --argjson e "$((NOWS-10))" '{epoch:$e,event:"PostToolUse",sid:"s",tool:"Bash",detail:"ls -la",rc:0}'
} > "$SHP/.plinth/session/events.jsonl"
export PLINTH_DASH_ROOTS="$SHP"
"$PLINTH" dash --snapshot | jq -e '
  .projects[] | select(.name == "shell-phase") | .phases.shell == 30
' >/dev/null
# Reinstall successful weekly-usage claude (prior sentinel was empty stdout).
cat > "$QBIN/claude" <<'C'
#!/usr/bin/env python3
import json
print(json.dumps({"result":
"Current week (all models): 80% used · resets Jul 30 at 9am (America/Puerto_Rico)\n"}))
C
chmod +x "$QBIN/claude"
# Legacy reset-less history must not project across upgrade
QLEG="$FIX/quota-legacy.json"
jq -nc --argjson now "$NOWQ" '{
  available:false, refreshed_at:($now-10000),
  history:[
    {t:($now-7200),week_all_models_pct:10},
    {t:($now-3600),week_all_models_pct:20}
  ], vendors:[]
}' > "$QLEG"
PATH="$QBIN:/usr/bin:/bin" PLINTH_DASH_QUOTA_CACHE="$QLEG" \
  PLINTH_DASH_QUOTA=1 PLINTH_DASH_QUOTA_TTL=0 PLINTH_DASH_ROOTS="$B" \
  "$PLINTH" dash --snapshot-with-quota \
  | jq -e '
    .quota.available == true
    and .quota.overall.used_pct == 80
    and .quota.overall.projected_100pct_at == null
    and (.quota.history | length) == 1
    and .quota.history[0].reset_text != null
  ' >/dev/null
# Cross-reset history must not project from prior week
QXR="$FIX/quota-xreset.json"
jq -nc --argjson now "$NOWQ" '{
  available:false, refreshed_at:($now-10000),
  history:[
    {t:($now-7200),week_all_models_pct:10,reset_text:"Jul 23 at 9am (America/Puerto_Rico)"},
    {t:($now-3600),week_all_models_pct:20,reset_text:"Jul 23 at 9am (America/Puerto_Rico)"}
  ], vendors:[]
}' > "$QXR"
PATH="$QBIN:/usr/bin:/bin" PLINTH_DASH_QUOTA_CACHE="$QXR" \
  PLINTH_DASH_QUOTA=1 PLINTH_DASH_QUOTA_TTL=0 \
  PLINTH_DASH_ROOTS="$B" "$PLINTH" dash --snapshot-with-quota \
  | jq -e '
    .quota.available == true
    and .quota.overall.used_pct == 80
    and .quota.overall.projected_100pct_at == null
    and (.quota.history|length)==1
  ' >/dev/null
# Public --snapshot is always offline; only serve uses --snapshot-with-quota.

# review_round_secs: sum of request→findings mtimes across rounds
RR="$FIX/rho-review-secs"
mk_git "$RR"
git -C "$RR" checkout -qb feat/rr
echo z > "$RR/z.txt"; git -C "$RR" add -A; git -C "$RR" commit -qm w
mkdir -p "$RR/.plinth/session/review/feat-rr"
printf '{"round":1,"mode":"fresh"}\n' > "$RR/.plinth/session/review/feat-rr/request-1.json"
printf '{"verdict":"CHANGES_NEEDED","summary":"x","findings":[]}\n' \
  > "$RR/.plinth/session/review/feat-rr/findings-1.json"
printf '{"round":2,"mode":"resume"}\n' > "$RR/.plinth/session/review/feat-rr/request-2.json"
printf '{"verdict":"CHANGES_NEEDED","summary":"y","findings":[]}\n' \
  > "$RR/.plinth/session/review/feat-rr/findings-2.json"
python3 - <<PY
import os, time
base = time.time()
# round1: 12s, round2: 8s → sum ~20s
os.utime("$RR/.plinth/session/review/feat-rr/request-1.json", (base-30, base-30))
os.utime("$RR/.plinth/session/review/feat-rr/findings-1.json", (base-18, base-18))
os.utime("$RR/.plinth/session/review/feat-rr/request-2.json", (base-10, base-10))
os.utime("$RR/.plinth/session/review/feat-rr/findings-2.json", (base-2, base-2))
PY
export PLINTH_DASH_ROOTS="$RR"
RROUT="$FIX/rr.json"
"$PLINTH" dash --snapshot > "$RROUT"
jq -e '
  .projects[] | select(.name == "rho-review-secs")
  | .review_round_secs >= 18
  and .review_round_secs <= 22
  and ((.phases.reviewing // 0) == 0)
' "$RROUT" >/dev/null
# Fresh cache TTL suppresses CLI on --snapshot-with-quota
TTLDIR="$FIX/ttl"
mkdir -p "$TTLDIR"
SENT2="$FIX/claude-ttl-called"; rm -f "$SENT2"
cat > "$QBIN/claude" <<C
#!/bin/sh
echo called > "$SENT2"
exit 0
C
chmod +x "$QBIN/claude"
NOWQ2="$(date +%s)"
jq -nc --argjson now "$NOWQ2" '{
  available:true, refreshed_at:$now,
  overall:{vendor:"claude",window:"week_all_models",used_pct:50,remaining_pct:50,
           reset_text:"Jul 30",projected_100pct_at:null,rate_pct_per_hour:null},
  vendors:[{vendor:"claude",available:true,windows:[{window:"week_all_models",used_pct:50,reset_text:"Jul 30"}]}],
  history:[{t:$now,week_all_models_pct:50,reset_text:"Jul 30"}]
}' > "$TTLDIR/cache.json"
PATH="$QBIN:/usr/bin:/bin" PLINTH_DASH_QUOTA_CACHE="$TTLDIR/cache.json" \
  PLINTH_DASH_QUOTA=1 PLINTH_DASH_QUOTA_TTL=900 PLINTH_DASH_ROOTS="$B" \
  "$PLINTH" dash --snapshot-with-quota | jq -e '.quota.overall.used_pct == 50' >/dev/null
[ ! -f "$SENT2" ] || { echo "smoke-snapshot: fresh TTL still invoked claude" >&2; exit 1; }
# Successful probe persists refreshed history to the cache file
cat > "$QBIN/claude" <<'C'
#!/usr/bin/env python3
import json
print(json.dumps({"result":
"Current week (all models): 55% used · resets Jul 30 at 9am (America/Puerto_Rico)\n"}))
C
chmod +x "$QBIN/claude"
PCACHE="$FIX/persist-cache.json"
rm -f "$PCACHE"
PATH="$QBIN:/usr/bin:/bin" PLINTH_DASH_QUOTA_CACHE="$PCACHE" \
  PLINTH_DASH_QUOTA=1 PLINTH_DASH_QUOTA_TTL=0 PLINTH_DASH_ROOTS="$B" \
  "$PLINTH" dash --snapshot-with-quota | jq -e '.quota.overall.used_pct == 55' >/dev/null
[ -f "$PCACHE" ] || { echo "smoke-snapshot: probe did not persist cache file" >&2; exit 1; }
jq -e '
  .overall.used_pct == 55
  and (.history | length) >= 1
  and (.history[-1].week_all_models_pct == 55)
  and (.history[-1].reset_text != null)
' "$PCACHE" >/dev/null

# Beta feedless
jq -e '
  .projects[] | select(.name == "beta")
  | .feedless == true
  and .review == null
  and .activity_secs_ago == null
  and .quota.available == false
' "$OUT" >/dev/null

# Error-card constructor retains seats/phases/review_round_secs when only verdict is bad
EC="$FIX/err-keep"
mk_git "$EC"
git -C "$EC" checkout -qb feat/ek
echo e > "$EC/e.txt"; git -C "$EC" add -A; git -C "$EC" commit -qm w
printf '%s\n' 'spec_path = SPEC.md' 'reviewer_vendor = codex' 'reviewer_model_tier2 = gpt-t2' \
  'audit_vendor = claude' 'audit_model = opus' > "$EC/.plinth/config"
NOWE="$(date +%s)"
mkdir -p "$EC/.plinth/session/review/feat-ek"
# valid events → phases accrue; malformed verdict → error card
{
  jq -nc --argjson e "$((NOWE-60))" '{epoch:$e,event:"SessionStart",sid:"s",tool:null,detail:null}'
  jq -nc --argjson e "$((NOWE-30))" '{epoch:$e,event:"PostToolUse",sid:"s",tool:"Edit",detail:"e.txt",rc:0}'
} > "$EC/.plinth/session/events.jsonl"
printf 'not-json\n' > "$EC/.plinth/session/review/feat-ek/verdict.json"
printf '{"round":1,"mode":"fresh"}\n' > "$EC/.plinth/session/review/feat-ek/request-1.json"
printf '{"verdict":"CHANGES_NEEDED","summary":"x","findings":[]}\n' \
  > "$EC/.plinth/session/review/feat-ek/findings-1.json"
python3 - <<PY
import os, time
b=time.time()
os.utime("$EC/.plinth/session/review/feat-ek/request-1.json", (b-15, b-15))
os.utime("$EC/.plinth/session/review/feat-ek/findings-1.json", (b, b))
PY
export PLINTH_DASH_ROOTS="$EC"
"$PLINTH" dash --snapshot | jq -e '
  .projects[] | select(.name == "err-keep")
  | .error == "snapshot_render_failed"
  and .models.seats.reviewer_tier2 == "gpt-t2"
  and .models.seats.audit_model == "opus"
  and .phases.coding == 30
  and .review_round_secs >= 10
  and .review_round_secs <= 20
' >/dev/null
# jq-fallback constructor: parseable JSON object that fails protocol shape
# (verdict enum invalid) — still retains seats/phases/review_round_secs.
printf '{"verdict":"NOT_A_REAL_VERDICT","sha":"abcdef0","round":1}\n' \
  > "$EC/.plinth/session/review/feat-ek/verdict.json"
"$PLINTH" dash --snapshot | jq -e '
  .projects[] | select(.name == "err-keep")
  | .error == "snapshot_render_failed"
  and .models.seats.reviewer_tier2 == "gpt-t2"
  and .phases.coding == 30
  and .review_round_secs >= 10
' >/dev/null

# Detached HEAD finds verdict under "detached"
jq -e '
  .projects[] | select(.name == "gamma-detached")
  | .branch == "detached"
  and .review != null
  and .review.verdict == "APPROVED"
  and .review.stale == false
' "$OUT" >/dev/null

# UNBOUND (pending confirmation) is a valid enum — not snapshot_render_failed
jq -e '
  .projects[] | select(.name == "gamma-unbound")
  | (.error == null or .error == "")
  and .review != null
  and .review.verdict == "UNBOUND"
' "$OUT" >/dev/null
# statusline must label UNBOUND (not "CHANGES")
sl="$( "$PLINTH" statusline "$FIX/gamma-unbound" )"
printf '%s' "$sl" | grep -q 'UNBOUND' || { echo "smoke-snapshot: statusline missing UNBOUND (got: $sl)" >&2; exit 1; }
printf '%s' "$sl" | grep -q 'CHANGES' && { echo "smoke-snapshot: statusline mislabels UNBOUND as CHANGES (got: $sl)" >&2; exit 1; } || true

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

# Parseable-invalid verdict enum / missing fields / bad event types → error
jq -e '
  .projects[] | select(.name == "mu-badenum")
  | .error == "snapshot_render_failed"
' "$OUT" >/dev/null
jq -e '
  .projects[] | select(.name == "mu-missingv")
  | .error == "snapshot_render_failed"
' "$OUT" >/dev/null
jq -e '
  .projects[] | select(.name == "mu-badevent")
  | .error == "snapshot_render_failed"
' "$OUT" >/dev/null
jq -e '
  .projects[] | select(.name == "mu-nullverdict")
  | .error == "snapshot_render_failed"
' "$OUT" >/dev/null
jq -e '
  .projects[] | select(.name == "mu-baddetail")
  | .error == "snapshot_render_failed"
' "$OUT" >/dev/null
jq -e '
  .projects[] | select(.name == "mu-badevname")
  | .error == "snapshot_render_failed"
' "$OUT" >/dev/null
jq -e '
  .projects[] | select(.name == "mu-multiv")
  | .error == "snapshot_render_failed"
' "$OUT" >/dev/null
# Invalid verdict files (no events) preserve feedless:true
for badn in mu-falsev mu-objnull mu-objfalse mu-falseobj mu-nullverdict mu-multiv mu-badenum mu-missingv; do
  jq -e --arg n "$badn" '
    .projects[] | select(.name == $n)
    | .error == "snapshot_render_failed"
    and .feedless == true
  ' "$OUT" >/dev/null
done
# Malformed events files have a feed → feedless:false + error
for badn in mu-noevent mu-numevent mu-emptyobj mu-badevent mu-baddetail mu-badevname \
            mu-scalarev mu-badsid mu-badtr; do
  jq -e --arg n "$badn" '
    .projects[] | select(.name == $n)
    | .error == "snapshot_render_failed"
    and .feedless == false
  ' "$OUT" >/dev/null
done
# Invalid verdict shape (feedless projects)
for badn in mu-emptyverdict mu-numverdict mu-nosha mu-numsha mu-badhex; do
  jq -e --arg n "$badn" '
    .projects[] | select(.name == $n)
    | .error == "snapshot_render_failed"
    and .feedless == true
  ' "$OUT" >/dev/null
done
# Healthy real hook event names
jq -e '
  .projects[] | select(.name == "mu-healthyhooks")
  | (.error == null or .error == "")
  and .sid == "sid-h"
' "$OUT" >/dev/null

# SHA-256 object format APPROVED-at-HEAD
if [ "${HAVE_SHA256:-0}" = "1" ]; then
  jq -e '
    .projects[] | select(.name == "mu-sha256")
    | (.error == null or .error == "")
    and .review.verdict == "APPROVED"
    and .review.stale == false
  ' "$OUT" >/dev/null
fi

# Interleaved SIDs: active A keeps original task + ~500s session
jq -e '
  .projects[] | select(.name == "nu-interleave")
  | .task == "task from A"
  and .sid == "A"
  and .session_secs != null
  and .session_secs >= 400
  and .session_secs <= 600
' "$OUT" >/dev/null

# Same-SID SessionStart resume keeps the first t0 (not the resume time)
RES="$FIX/mu-resume"
mk_git "$RES"
{
  jq -nc --argjson epoch "$((NOW - 1000))" \
    '{event:"SessionStart",sid:"sid-r",epoch:$epoch,transcript:null}'
  jq -nc --argjson epoch "$((NOW - 10))" \
    '{event:"SessionStart",sid:"sid-r",epoch:$epoch,transcript:null}'
} > "$RES/.plinth/session/events.jsonl"
export PLINTH_DASH_ROOTS="$RES"
RES_OUT="$FIX/resume.json"
"$PLINTH" dash --snapshot > "$RES_OUT"
# session_secs ≈ 1000; allow drift equal to smoke wall-clock since NOW was set.
jq -e --argjson now "$NOW" '
  .projects[] | select(.name == "mu-resume")
  | .session_secs != null
  and .session_secs >= 990
  and .session_secs <= 1000 + 600
' "$RES_OUT" >/dev/null

# Missing round on verdict → error
MR="$FIX/mu-noround"
mk_git "$MR"
git -C "$MR" checkout -qb feat/noround
echo n > "$MR/n"; git -C "$MR" add -A; git -C "$MR" commit -qm w
mkdir -p "$MR/.plinth/session/review/feat-noround"
printf '{"verdict":"APPROVED","sha":"abcdef0123456789"}\n' \
  > "$MR/.plinth/session/review/feat-noround/verdict.json"
export PLINTH_DASH_ROOTS="$MR"
"$PLINTH" dash --snapshot | jq -e '
  .projects[] | select(.name == "mu-noround") | .error == "snapshot_render_failed"
' >/dev/null

# Request filename/body round mismatch → error (request-2.json with round 10)
MM="$FIX/mu-rqmismatch"
mk_git "$MM"
git -C "$MM" checkout -qb feat/rqm
echo m > "$MM/m"; git -C "$MM" add -A; git -C "$MM" commit -qm w
MFULL="$(git -C "$MM" rev-parse HEAD)"
mkdir -p "$MM/.plinth/session/review/feat-rqm"
jq -nc --arg sha "$MFULL" \
  '{verdict:"CHANGES_NEEDED",sha:$sha,round:1,mode:"fresh",model:"gpt-test",
    risk:{tier:1,files:1,reasons:["t"]},ts:"t"}' \
  > "$MM/.plinth/session/review/feat-rqm/verdict.json"
jq -nc '{round:10,mode:"resume"}' > "$MM/.plinth/session/review/feat-rqm/request-2.json"
export PLINTH_DASH_ROOTS="$MM"
"$PLINTH" dash --snapshot | jq -e '
  .projects[] | select(.name == "mu-rqmismatch") | .error == "snapshot_render_failed"
' >/dev/null
# Negative request round
MN="$FIX/mu-rqneg"
mk_git "$MN"
git -C "$MN" checkout -qb feat/rqneg
echo m > "$MN/m"; git -C "$MN" add -A; git -C "$MN" commit -qm w
mkdir -p "$MN/.plinth/session/review/feat-rqneg"
jq -nc '{round:-1}' > "$MN/.plinth/session/review/feat-rqneg/request-1.json"
export PLINTH_DASH_ROOTS="$MN"
"$PLINTH" dash --snapshot | jq -e '
  .projects[] | select(.name == "mu-rqneg") | .error == "snapshot_render_failed"
' >/dev/null
# Absent request round
MA="$FIX/mu-rqabsent"
mk_git "$MA"
git -C "$MA" checkout -qb feat/rqabs
echo m > "$MA/m"; git -C "$MA" add -A; git -C "$MA" commit -qm w
mkdir -p "$MA/.plinth/session/review/feat-rqabs"
jq -nc '{mode:"resume"}' > "$MA/.plinth/session/review/feat-rqabs/request-1.json"
export PLINTH_DASH_ROOTS="$MA"
"$PLINTH" dash --snapshot | jq -e '
  .projects[] | select(.name == "mu-rqabsent") | .error == "snapshot_render_failed"
' >/dev/null
# Fractional request round
MF="$FIX/mu-rqfrac"
mk_git "$MF"
git -C "$MF" checkout -qb feat/rqfrac
echo m > "$MF/m"; git -C "$MF" add -A; git -C "$MF" commit -qm w
mkdir -p "$MF/.plinth/session/review/feat-rqfrac"
jq -nc '{round:1.5}' > "$MF/.plinth/session/review/feat-rqfrac/request-1.json"
export PLINTH_DASH_ROOTS="$MF"
"$PLINTH" dash --snapshot | jq -e '
  .projects[] | select(.name == "mu-rqfrac") | .error == "snapshot_render_failed"
' >/dev/null

# --snapshot works without python3 (only bash+jq); serve fails without python3
PATH_SAVE="$PATH"
# Prefer a PATH that still has git/jq/bash but not python3
TMP_PATH="$FIX/bin"
mkdir -p "$TMP_PATH"
ln -sf "$(command -v bash)" "$TMP_PATH/bash"
ln -sf "$(command -v jq)" "$TMP_PATH/jq"
ln -sf "$(command -v git)" "$TMP_PATH/git"
ln -sf "$(command -v tail)" "$TMP_PATH/tail"
ln -sf "$(command -v mktemp)" "$TMP_PATH/mktemp"
ln -sf "$(command -v rm)" "$TMP_PATH/rm"
ln -sf "$(command -v cat)" "$TMP_PATH/cat"
ln -sf "$(command -v wc)" "$TMP_PATH/wc"
ln -sf "$(command -v tr)" "$TMP_PATH/tr"
ln -sf "$(command -v basename)" "$TMP_PATH/basename"
ln -sf "$(command -v dirname)" "$TMP_PATH/dirname"
ln -sf "$(command -v mkdir)" "$TMP_PATH/mkdir"
ln -sf "$(command -v printf)" "$TMP_PATH/printf"
ln -sf "$(command -v date)" "$TMP_PATH/date"
ln -sf "$(command -v sort)" "$TMP_PATH/sort"
ln -sf "$(command -v cut)" "$TMP_PATH/cut"
ln -sf "$(command -v grep)" "$TMP_PATH/grep"
ln -sf "$(command -v sed)" "$TMP_PATH/sed"
ln -sf "$(command -v head)" "$TMP_PATH/head"
ln -sf "$(command -v realpath)" "$TMP_PATH/realpath" 2>/dev/null || true
ln -sf "$(command -v stat)" "$TMP_PATH/stat"
ln -sf "$(command -v awk)" "$TMP_PATH/awk"
ln -sf "$(command -v shasum)" "$TMP_PATH/shasum" 2>/dev/null || true
export PLINTH_DASH_ROOTS="$B"
# Same-second last-error without python3 stays infra-error (whole-second -nt)
NP="$FIX/mu-nopy"
mk_git "$NP"
git -C "$NP" checkout -qb feat/nopy
echo n > "$NP/n"; git -C "$NP" add -A; git -C "$NP" commit -qm w
NFULL="$(git -C "$NP" rev-parse HEAD)"
mkdir -p "$NP/.plinth/session/review/feat-nopy"
jq -nc --arg sha "$NFULL" \
  '{verdict:"CHANGES_NEEDED",sha:$sha,round:1,mode:"fresh",model:"gpt-test",
    risk:{tier:1,files:1,reasons:["t"]},ts:"t"}' \
  > "$NP/.plinth/session/review/feat-nopy/verdict.json"
printf 'err\n' > "$NP/.plinth/session/review/feat-nopy/last-error"
jq -nc '{round:2,mode:"resume"}' > "$NP/.plinth/session/review/feat-nopy/request-2.json"
# equal second mtimes
touch -r "$NP/.plinth/session/review/feat-nopy/last-error" \
  "$NP/.plinth/session/review/feat-nopy/request-2.json"
export PLINTH_DASH_ROOTS="$NP"
# Force _dash_file_newer to use bash -nt by hiding python3 (restore PATH after).
PATH="$TMP_PATH" "$PLINTH" dash --snapshot > "$FIX/nopy.json"
jq -e '
  .projects[] | select(.name == "mu-nopy")
  | .review.running == false
  and .review.last_error == true
' "$FIX/nopy.json" >/dev/null
# serve mode requires python3
rc=0
PATH="$TMP_PATH" "$PLINTH" dash --port 18799 >/dev/null 2>"$FIX/nopy-serve.err" || rc=$?
[ "$rc" -ne 0 ] || { echo "smoke-snapshot: serve without python3 should fail" >&2; exit 1; }
grep -qi python "$FIX/nopy-serve.err" \
  || { echo "smoke-snapshot: serve without python3 should mention python3" >&2; cat "$FIX/nopy-serve.err" >&2; exit 1; }
# Restore full PATH for the rest of the smoke (node/curl/python3/etc.).
export PATH="${PATH_SAVE:-$PATH}"

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
  const o = {
    textContent: "", className: "", innerHTML: "",
    style: { display: "", cssText: "" },
    classList: { add() {}, remove() {}, contains() { return false; } },
    _listeners: {},
    addEventListener(type, fn) { o._listeners[type] = o._listeners[type] || []; o._listeners[type].push(fn); },
    removeEventListener() {},
    getAttribute(name) { return o._attrs && o._attrs[name] || null; },
    setAttribute(name, v) { o._attrs = o._attrs || {}; o._attrs[name] = v; },
    closest() { return null; },
  };
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
    _listeners: {},
    addEventListener(type, fn) {
      // `this` is the document stub (do not close over an unbound `document`).
      this._listeners = this._listeners || {};
      this._listeners[type] = this._listeners[type] || [];
      this._listeners[type].push(fn);
    },
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
["grid", "live-dot", "live-label", "gen-ago", "discovery", "count",
 "quota-bar", "nh-modal", "nh-panel", "nh-title", "nh-sub", "nh-list", "nh-close"
].forEach((id) => { elsById[id] = el(id); });
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
    // setTimeout runs outside the vm context — bind DOM stubs explicitly.
    const document = sandbox.document;
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
      models: {
        live: { driver: "claude-test", reviewer: "gpt-test", reviewer_vendor: "codex" },
        seats: {
          reviewer_vendor: "codex", reviewer_tier1: "gpt-t1", reviewer_tier2: "gpt-t2",
          audit_vendor: "claude", audit_model: "opus",
          advisor_vendor: "claude", advisor_model: "fable", advisor_model_max: "fable-max"
        }
      },
      phases: { coding: 120, reviewing: 60, research: 30 },
      review_round_secs: 42,
      needs_human: { open: 0, blocking: 0, items: [], truncated: false },
      review: { verdict: "CHANGES_NEEDED", round: 2, sha7: "abc1234",
                stale: false, running: false, mode: "fresh", tier: 1 },
      activity_secs_ago: 5, session_secs: 60,
    };
    const fullHtml = api.cardHTML(full);
    for (const needle of [
      "feat/dash", "abc1234", "CHANGES_NEEDED", "do the thing",
      "12/min", "1.5k recent", "r2", "claude-test", "gpt-test",
      "coding", "reviewing", "seats", "max=fable-max", "t2=gpt-t2",
      "wall 42s", "review wall",
    ]) {
      if (!fullHtml.includes(needle)) {
        console.error("cardHTML missing field representation:", needle);
        process.exit(1);
      }
    }
    // NEEDS-HUMAN drill-down chip carries data-nh
    const nhOnly = {
      name: "h", path: "/tmp/h", branch: "main", head: "abc",
      feedless: true, review: null,
      needs_human: {
        open: 2, blocking: 1, truncated: false,
        items: [{ text: "[BLOCKING] fix me", blocking: true },
                { text: "later", blocking: false }]
      }
    };
    const nhHtml = api.cardHTML(nhOnly);
    if (!nhHtml.includes('data-nh="/tmp/h"') || !nhHtml.includes('<button type="button"')) {
      console.error("NEEDS-HUMAN chip missing button/data-nh:", nhHtml.slice(0, 300));
      process.exit(1);
    }
    // Modal path: require seams (no silent skip)
    if (typeof api.openNeedsHuman !== "function" || typeof api.closeNeedsHuman !== "function"
        || typeof api.seedProjects !== "function") {
      console.error("missing openNeedsHuman/closeNeedsHuman/seedProjects seams");
      process.exit(1);
    }
    {
      const modal = elsById["nh-modal"];
      let open = false;
      modal.classList = {
        add(c) { if (c === "open") open = true; },
        remove(c) { if (c === "open") open = false; },
        contains(c) { return c === "open" ? open : false; },
      };
      api.seedProjects([{
        name: "h2", path: "/tmp/h2", branch: "main", head: "abc",
        feedless: true, review: null,
        needs_human: {
          open: 51, blocking: 1, truncated: true,
          source: "NEEDS-HUMAN.md",
          items: [{ text: "[BLOCKING] fix <me>", blocking: true },
                  { text: "later", blocking: false }]
        }
      }]);
      // Boot-time listeners were registered on pre-seeded nodes / document.
      const closeFns = (elsById["nh-close"]._listeners && elsById["nh-close"]._listeners.click) || [];
      const escFns = (document._listeners && document._listeners.keydown) || [];
      const modalFns = (modal._listeners && modal._listeners.click) || [];
      if (!closeFns.length) {
        console.error("nh-close click listener not registered at boot");
        process.exit(1);
      }
      if (!escFns.length) {
        console.error("document keydown (Escape) listener not registered at boot");
        process.exit(1);
      }
      api.openNeedsHuman("/tmp/h2");
      const listHtml = (elsById["nh-list"] && elsById["nh-list"].innerHTML) || "";
      if (!listHtml.includes("blocking") || !listHtml.includes("fix &lt;me&gt;")
          || !listHtml.includes("truncated") || !listHtml.includes("plinth queue")) {
        console.error("openNeedsHuman list missing blocking/escape/truncation:", listHtml);
        process.exit(1);
      }
      const subHtml = (elsById["nh-sub"] && elsById["nh-sub"].textContent) || "";
      if (!subHtml.includes("NEEDS-HUMAN.md")) {
        console.error("nh-sub missing source label:", subHtml);
        process.exit(1);
      }
      if (!modal.classList.contains("open")) {
        console.error("openNeedsHuman did not open modal");
        process.exit(1);
      }
      // Close button listener
      closeFns[0]({ target: elsById["nh-close"] });
      if (modal.classList.contains("open")) {
        console.error("Close button listener did not close modal");
        process.exit(1);
      }
      // Escape
      api.openNeedsHuman("/tmp/h2");
      escFns[0]({ key: "Escape" });
      if (modal.classList.contains("open")) {
        console.error("Escape listener did not close modal");
        process.exit(1);
      }
      // Backdrop click (target === modal) — required, not optional
      if (!modalFns.length) {
        console.error("modal backdrop click listener not registered at boot");
        process.exit(1);
      }
      api.openNeedsHuman("/tmp/h2");
      modalFns[0]({ target: modal });
      if (modal.classList.contains("open")) {
        console.error("backdrop click did not close modal");
        process.exit(1);
      }
      // Grid chip click wiring
      const gridFns = (elsById["grid"]._listeners && elsById["grid"]._listeners.click) || [];
      if (!gridFns.length) {
        console.error("grid click listener not registered for NEEDS-HUMAN chips");
        process.exit(1);
      }
      api.seedProjects([{
        name: "h2", path: "/tmp/h2", branch: "main", head: "abc",
        feedless: true, review: null,
        needs_human: {
          open: 1, blocking: 0, truncated: false,
          items: [{ text: "from chip", blocking: false }]
        }
      }]);
      const chip = { closest: (sel) => sel === "[data-nh]" ? { getAttribute: () => "/tmp/h2" } : null };
      gridFns[0]({ target: chip });
      if (!modal.classList.contains("open")) {
        console.error("chip click path did not open modal");
        process.exit(1);
      }
      const chipList = (elsById["nh-list"] && elsById["nh-list"].innerHTML) || "";
      if (!chipList.includes("from chip")) {
        console.error("chip click did not render items:", chipList);
        process.exit(1);
      }
    }
    // renderQuota available + unavailable (require seam)
    if (typeof api.renderQuota !== "function") {
      console.error("missing renderQuota seam");
      process.exit(1);
    }
    {
      api.renderQuota({
        available: true, refreshed_at: Math.floor(Date.now() / 1000),
        overall: {
          used_pct: 80, remaining_pct: 20, reset_text: "Jul 30 at 9am",
          projected_100pct_at: Math.floor(Date.now() / 1000) + 3600,
          rate_pct_per_hour: 5
        }
      });
      const qb = (elsById["quota-bar"] && elsById["quota-bar"].innerHTML) || "";
      if (!qb.includes("80%") || !qb.includes("WEEKLY") || !qb.includes("→100%")) {
        console.error("renderQuota available missing expected text:", qb);
        process.exit(1);
      }
      api.renderQuota({ available: false, note: "vendor plan unknown", vendors: [] });
      const qb2 = (elsById["quota-bar"] && elsById["quota-bar"].innerHTML) || "";
      if (!qb2.includes("unavailable")) {
        console.error("renderQuota unavailable missing text:", qb2);
        process.exit(1);
      }
      // Malformed vendors must not throw (Array.isArray guard)
      try {
        api.renderQuota({ available: false, note: "bad", vendors: {} });
      } catch (e) {
        console.error("renderQuota crashed on vendors:{}", e);
        process.exit(1);
      }
      const qb3 = (elsById["quota-bar"] && elsById["quota-bar"].innerHTML) || "";
      if (!qb3.includes("unavailable")) {
        console.error("renderQuota vendors:{} missing unavailable:", qb3);
        process.exit(1);
      }
    }
    // UNBOUND (pending Tier-2 confirmation): warn tone + yellow chip
    const unbound = {
      name: "ub", path: "/tmp/ub", branch: "feat/ub", head: "abcdef0",
      feedless: false, needs_human: { open: 0, blocking: 0 },
      review: { verdict: "UNBOUND", round: 2, sha7: "abcdef0",
                stale: false, running: false, mode: "verify", tier: 2 },
    };
    if (api.cardTone(unbound) !== "warn") {
      console.error("cardTone(UNBOUND) expected warn, got", api.cardTone(unbound));
      process.exit(1);
    }
    const ubHtml = api.cardHTML(unbound);
    if (!ubHtml.includes('class="card warn"')) {
      console.error("UNBOUND card missing tone class warn");
      process.exit(1);
    }
    if (!ubHtml.includes('chip yellow">UNBOUND')) {
      console.error("UNBOUND card missing yellow UNBOUND chip:", ubHtml.slice(0, 200));
      process.exit(1);
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
# Serve-mode must re-invoke dash --snapshot-with-quota (not public --snapshot).
# Observe via WRAP argv.
PROBE_SEEN="$FIX/probe-seen"
: > "$PROBE_SEEN"
cat > "$WRAP" <<WRAP
#!/usr/bin/env bash
printf '1\n' >> "$COUNT_FILE"
# Record argv so we can assert the serve child used --snapshot-with-quota.
printf '%s\n' "\$*" >> "$PROBE_SEEN"
sleep 0.4
exec "$PLINTH" "\$@"
WRAP
chmod +x "$WRAP"
if command -v setsid >/dev/null 2>&1; then
  setsid env PLINTH_DASH_SNAPSHOT_BIN="$WRAP" PLINTH_DASH_ROOTS="$A:$I" \
    PLINTH_DASH_QUOTA=0 \
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
    PLINTH_DASH_QUOTA=0 \
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
# Static UI (no curl|grep -q: under pipefail grep early-exit SIGPIPEs curl → false fail)
UI_BODY="$FIX/ui-body.html"
curl -sf --max-time 10 "http://127.0.0.1:${SRV_PORT}/" > "$UI_BODY" \
  || { echo "smoke-snapshot: / curl failed" >&2; exit 1; }
grep -q 'Plinth dashboard' "$UI_BODY" \
  || { echo "smoke-snapshot: / did not serve the UI" >&2; exit 1; }
# Serve path auto-enables snapshot-with-quota on the snapshot child
# (even when PLINTH_DASH_QUOTA=0 so no real CLI is spawned).
grep -q 'snapshot-with-quota' "$PROBE_SEEN" \
  || { echo "smoke-snapshot: serve child did not use --snapshot-with-quota (got: $(cat "$PROBE_SEEN"))" >&2; exit 1; }
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
