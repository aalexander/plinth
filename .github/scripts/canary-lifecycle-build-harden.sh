#!/usr/bin/env bash
# Canary: default-build Stop + harden Stop + ship gate unchanged (no network).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/shared/.claude/hooks/review-gate.sh"
PLINTH="$ROOT/bin/plinth"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

# Minimal fake project with git + session baseline
setup_proj() {
  local d="$1"
  mkdir -p "$d/.plinth/session" "$d/.git"
  git -C "$d" init -q
  git -C "$d" config user.email t@t
  git -C "$d" config user.name t
  echo x > "$d/f"
  git -C "$d" add f && git -C "$d" commit -qm init
  git -C "$d" checkout -qb feat/canary
  echo y >> "$d/f"
  git -C "$d" add f && git -C "$d" commit -qm work
  # SessionStart baseline = parent so HEAD looks like session made commits
  local parent
  parent=$(git -C "$d" rev-parse HEAD~1)
  echo "$parent" > "$d/.plinth/session/start-head-canary"
}

run_gate() {
  local d="$1" phase_msg
  CLAUDE_PROJECT_DIR="$d" bash "$GATE" <<'JSON'
{"session_id":"canary"}
JSON
}

# --- default build: gate exits 0, logs build_defer ---
setup_proj "$TMP/p1"
# Ensure no harden phase
rm -f "$TMP/p1/.plinth/session/phase-"*.json
if ! run_gate "$TMP/p1" >/dev/null 2>"$TMP/e1"; then
  fail "default build Stop should allow (exit 0); stderr=$(cat "$TMP/e1")"
fi
grep -q build_defer "$TMP/p1/.plinth/session/events.jsonl" 2>/dev/null \
  || fail "expected build_defer event"
pass "default build defers Stop without APPROVED"

# --- harden: gate blocks without APPROVED ---
"$PLINTH" harden "$TMP/p1" >/dev/null
set +e
run_gate "$TMP/p1" >/dev/null 2>"$TMP/e2"
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "harden Stop should block (exit 2), got $rc stderr=$(cat "$TMP/e2")"
grep -qi HARDEN "$TMP/e2" || fail "harden block message should mention HARDEN"
pass "harden Stop blocks without APPROVED"

# --- APPROVED@HEAD allows under harden ---
head=$(git -C "$TMP/p1" rev-parse HEAD)
slug=feat-canary
mkdir -p "$TMP/p1/.plinth/session/review/$slug"
jq -n --arg s "$head" '{verdict:"APPROVED",sha:$s,round:1}' \
  > "$TMP/p1/.plinth/session/review/$slug/verdict.json"
if ! run_gate "$TMP/p1" >/dev/null 2>"$TMP/e3"; then
  fail "APPROVED@HEAD should allow under harden; stderr=$(cat "$TMP/e3")"
fi
pass "harden + APPROVED@HEAD allows Stop"

# --- plinth build returns to defer ---
"$PLINTH" build "$TMP/p1" >/dev/null
phase=$("$PLINTH" phase "$TMP/p1" | sed -n 's/^phase:[[:space:]]*//p')
[ "$phase" = "build" ] || fail "expected phase build, got $phase"
if ! run_gate "$TMP/p1" >/dev/null 2>"$TMP/e4"; then
  fail "after plinth build, Stop should allow"
fi
pass "plinth build restores build_defer"

# --- handoff writes file ---
"$PLINTH" handoff "$TMP/p1" >/dev/null
[ -f "$TMP/p1/CHECKPOINT.md" ] || fail "CHECKPOINT.md missing"
[ -f "$TMP/p1/HANDOFF.md" ] || fail "HANDOFF.md pointer missing"
# Canonical resume is CHECKPOINT.md; HANDOFF.md is a pointer (v5.0.6+).
grep -q 'Restart prompt' "$TMP/p1/CHECKPOINT.md" || fail "CHECKPOINT missing restart section"
grep -q 'CHECKPOINT.md' "$TMP/p1/HANDOFF.md" || fail "HANDOFF pointer missing CHECKPOINT.md"
pass "plinth handoff/checkpoint writes CHECKPOINT.md + HANDOFF pointer"

# --- harden refuses main ---
git -C "$TMP/p1" checkout -q main 2>/dev/null || git -C "$TMP/p1" checkout -qb main
set +e
"$PLINTH" harden "$TMP/p1" >/dev/null 2>"$TMP/e5"
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "harden on main should refuse"
pass "harden refuses base branch"

# --- plinth plan (light) scaffolds PLAN.md ---
setup_proj "$TMP/p2"
rm -f "$TMP/p2/PLAN.md"
"$PLINTH" plan "$TMP/p2" >/dev/null
[ -f "$TMP/p2/PLAN.md" ] || fail "plinth plan should write PLAN.md"
grep -q '## Acceptance criteria' "$TMP/p2/PLAN.md" || fail "PLAN scaffold missing AC section"
# second call does not clobber
echo "marker" >> "$TMP/p2/PLAN.md"
"$PLINTH" plan "$TMP/p2" >/dev/null
grep -q marker "$TMP/p2/PLAN.md" || fail "plinth plan must not overwrite existing PLAN.md"
pass "plinth plan light scaffolds without clobber"

# --- snapshot includes lifecycle ---
# Minimal plinth project shape for dash snapshot_one
mkdir -p "$TMP/p2/.plinth"
echo "spec_path = MANUAL.md" > "$TMP/p2/.plinth/config"
# source snapshot via plinth dash --snapshot is heavy; unit-test phase field via jq on phase file
"$PLINTH" harden "$TMP/p2" >/dev/null
ph=$("$PLINTH" phase "$TMP/p2" | sed -n 's/^phase:[[:space:]]*//p')
[ "$ph" = "harden" ] || fail "phase harden expected"
pass "phase status after harden"

# --- plinth next ---
setup_proj "$TMP/p3"
"$PLINTH" handoff "$TMP/p3" >/dev/null
# inject a next line
if ! grep -q '## Next' "$TMP/p3/CHECKPOINT.md"; then fail "checkpoint missing Next"; fi
# next should return work
set +e
out=$("$PLINTH" next "$TMP/p3" 2>&1)
rc=$?
set -e
echo "$out" | grep -q 'status: work' || fail "plinth next expected status work: $out"
[ "$rc" -eq 0 ] || fail "plinth next exit 0 expected, got $rc"
pass "plinth next returns work"

# human blocked
mkdir -p "$TMP/p3/.plinth"
printf '%s\n' '# NH' '- [ ] [BLOCKING] need secret from human' > "$TMP/p3/.plinth/NEEDS-HUMAN.md"
set +e
out=$("$PLINTH" next "$TMP/p3" 2>&1)
rc=$?
set -e
echo "$out" | grep -q human_blocked || fail "expected human_blocked: $out"
[ "$rc" -eq 2 ] || fail "plinth next exit 2 for blocking, got $rc"
pass "plinth next human_blocked"

# --- migrate open review → harden (production CLI, not a simplified copy) ---
setup_proj "$TMP/p4"
slug=feat%2Fcanary
mkdir -p "$TMP/p4/.plinth/session/review/$slug"
head=$(git -C "$TMP/p4" rev-parse HEAD)
jq -n --arg s "$head" '{verdict:"CHANGES_NEEDED",sha:$s,round:1}' \
  > "$TMP/p4/.plinth/session/review/$slug/verdict.json"
"$PLINTH" lifecycle-migrate "$TMP/p4" >/dev/null
# Encoded slug feat/canary → feat%2Fcanary (legacy feat-canary still readable)
phf=$(ls "$TMP/p4/.plinth/session"/phase-*.json 2>/dev/null | head -1)
[ -n "$phf" ] && [ "$(jq -r .phase "$phf")" = "harden" ] \
  || fail "lifecycle-migrate should set harden for open CHANGES_NEEDED (got $phf)"
pass "lifecycle migrate open review → harden"

# corrupt phase without matching review dir still repaired by migrate
setup_proj "$TMP/p4b"
echo 'not-json' > "$TMP/p4b/.plinth/session/phase-feat%2Fcanary.json"
"$PLINTH" lifecycle-migrate "$TMP/p4b" >/dev/null
phf=$(ls "$TMP/p4b/.plinth/session"/phase-*.json 2>/dev/null | head -1)
[ -n "$phf" ] && [ "$(jq -r .phase "$phf")" = "harden" ] \
  || fail "lifecycle-migrate should rewrite corrupt phase without review/"
ph=$("$PLINTH" phase "$TMP/p4b" | sed -n 's/^phase:[[:space:]]*//p')
[ "$ph" = "harden" ] || fail "phase status after corrupt migrate expected harden, got $ph"
pass "lifecycle-migrate repairs orphan corrupt phase; phase CLI fail-closed"

# corrupt phase → gate treats as harden
setup_proj "$TMP/p5"
echo 'not-json' > "$TMP/p5/.plinth/session/phase-feat%2Fcanary.json"
export CLAUDE_PROJECT_DIR="$TMP/p5"
set +e
printf '%s' '{"session_id":"canary"}' | bash "$GATE" >"$TMP/g5.out" 2>"$TMP/g5.err"
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "corrupt phase should block as harden, got $rc err=$(cat "$TMP/g5.err")"
grep -qi HARDEN "$TMP/g5.err" || grep -qi corrupt "$TMP/g5.err" || fail "expected harden/corrupt message"
pass "corrupt phase fail-closed as harden"

# --- next: stale APPROVED under harden must not report done ---
setup_proj "$TMP/p6"
"$PLINTH" harden "$TMP/p6" >/dev/null
# wipe auto next lines so we hit the harden verdict path
printf '%s\n' '# Handoff' '## Next' '' > "$TMP/p6/HANDOFF.md"
slug=feat%2Fcanary
mkdir -p "$TMP/p6/.plinth/session/review/$slug"
old=$(git -C "$TMP/p6" rev-parse HEAD~1)
jq -n --arg s "$old" '{verdict:"APPROVED",sha:$s,round:1}' \
  > "$TMP/p6/.plinth/session/review/$slug/verdict.json"
set +e
out=$("$PLINTH" next "$TMP/p6" 2>&1)
rc=$?
set -e
echo "$out" | grep -q 'status: work' || fail "stale APPROVED must be work not done: $out"
echo "$out" | grep -qi 'review' || fail "stale APPROVED should route to re-review: $out"
[ "$rc" -eq 0 ] || fail "stale APPROVED next exit 0, got $rc"
echo "$out" | grep -q 'status: done' && fail "stale APPROVED must not be done: $out"
pass "plinth next: stale APPROVED → re-review (not done)"

# --- ship tripwire still blocks gh pr create|merge without APPROVED (criterion 4) ---
GUARD="$ROOT/shared/.claude/hooks/guard.sh"
setup_proj "$TMP/p7"
# No APPROVED verdict — guard must block ship command at command position.
set +e
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title t --body b"}}' \
  | CLAUDE_PROJECT_DIR="$TMP/p7" bash "$GUARD" >"$TMP/g7.out" 2>"$TMP/g7.err"
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "gh pr create without APPROVED should block (exit 2), got $rc err=$(cat "$TMP/g7.err")"
grep -qiE 'APPROVED|ship|pr create|blocked' "$TMP/g7.err" \
  || fail "ship block message expected: $(cat "$TMP/g7.err")"
pass "guard blocks gh pr create without APPROVED@HEAD"
set +e
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --merge"}}' \
  | CLAUDE_PROJECT_DIR="$TMP/p7" bash "$GUARD" >"$TMP/g7m.out" 2>"$TMP/g7m.err"
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "gh pr merge without APPROVED should block (exit 2), got $rc err=$(cat "$TMP/g7m.err")"
grep -qiE 'APPROVED|ship|pr merge|blocked' "$TMP/g7m.err" \
  || fail "ship merge block message expected: $(cat "$TMP/g7m.err")"
pass "guard blocks gh pr merge without APPROVED@HEAD"
# plinth#49: bare `gh pr merge` (no number/URL) always blocked — even with APPROVED@HEAD
head=$(git -C "$TMP/p7" rev-parse HEAD)
slug=feat-canary
mkdir -p "$TMP/p7/.plinth/session/review/$slug"
jq -n --arg s "$head" '{verdict:"APPROVED",sha:$s,round:1}' \
  > "$TMP/p7/.plinth/session/review/$slug/verdict.json"
set +e
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --merge"}}' \
  | CLAUDE_PROJECT_DIR="$TMP/p7" bash "$GUARD" >"$TMP/g7bare.out" 2>"$TMP/g7bare.err"
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "bare gh pr merge should block even with APPROVED (exit 2), got $rc err=$(cat "$TMP/g7bare.err")"
grep -qiE 'bare|repository/head-bound|match-head-commit|blocked' "$TMP/g7bare.err" \
  || fail "bare merge block should explain head-bound form: $(cat "$TMP/g7bare.err")"
pass "guard blocks bare gh pr merge even with APPROVED@HEAD (plinth#49)"

# --- sticky ledger: production jq from shared/.plinth/review.sh (not a toy reimpl) ---
STICKY_SRC="$ROOT/shared/.plinth/review.sh"
# Extract sticky_process_findings body is heavy; unit the normdesc + base_id contract
# and a two-round AUTO-STICKY strip via the same jq defs shipped in review.sh.
python3 - <<'PY' || fail "sticky unit"
import base64, re, json, subprocess, tempfile, os, textwrap

# Contract: strip AUTO-STICKY before punctuation normalize.
def strip_sticky(desc: str) -> str:
    return re.sub(r" \[AUTO-STICKY:[^\]]*\]", "", desc or "")

def normdesc(desc: str) -> str:
    s = strip_sticky(desc).lower()
    s = re.sub(r"[^a-z0-9]+", " ", s).strip()
    return s

def base_id(file, sev, desc):
    raw = f"{file}|{sev}|{normdesc(desc)}".encode()
    return base64.b64encode(raw).decode()

d0 = "bug about X " + "x" * 40 + " site A"
d1 = d0 + " [AUTO-STICKY: reopened without file blob change — treated resolved]"
assert normdesc(d0) == normdesc(d1), "AUTO-STICKY marker must not change desc_norm"
assert base_id("a.sh", "major", d0) == base_id("a.sh", "major", d1)
a = base_id("a.sh", "major", d0)
b = base_id("a.sh", "major", "bug about X " + "x" * 40 + " site B")
assert a != b, "sibling sites must differ"
# Simulate ledger round-2: after auto-resolve, desc_norm has no marker residue
assert "auto sticky" not in normdesc(d1)
print("sticky unit ok")
PY
pass "sticky id uniqueness / AUTO-STICKY strip / fail-closed identity unit"

# handoff Next: harden→build→harden keeps current-state action first, no obsolete stack
setup_proj "$TMP/p8"
"$PLINTH" harden "$TMP/p8" >/dev/null
"$PLINTH" build "$TMP/p8" >/dev/null
"$PLINTH" harden "$TMP/p8" >/dev/null
next_block=$(awk '/^## Next/{p=1;next} p&&/^## /{exit} p' "$TMP/p8/CHECKPOINT.md")
first=$(printf '%s\n' "$next_block" | sed -n '1p' | sed -E 's/^[[:space:]]*[0-9]+[.)]*[[:space:]]*//')
printf '%s\n' "$first" | grep -qi 'review' \
  || fail "after final harden, first Next should be review: $next_block"
printf '%s\n' "$next_block" | grep -qiE 'continue build|Continue implementation' \
  && fail "obsolete build action must be purged: $next_block"
n_review=$(printf '%s\n' "$next_block" | grep -c 'review\.sh' || true)
[ "$n_review" -le 1 ] || fail "handoff Next stacked review hints ($n_review): $next_block"
pass "handoff Next prioritizes current harden action"

# Invoke production sticky_process_findings (source the function from review.sh)
# Must use a REAL tracked file: AUTO-STICKY refuses absent blobs (fail-closed).
setup_proj "$TMP/p9"
SDIR="$TMP/p9/.plinth/session/review/feat-canary"
mkdir -p "$SDIR"
printf 'echo ok\n' > "$TMP/p9/a.sh"
git -C "$TMP/p9" add a.sh
git -C "$TMP/p9" -c user.email=t@t -c user.name=t commit -qm 'add a.sh for sticky blob'
export SDIR
bash -c '
  set -euo pipefail
  SDIR="'"$SDIR"'"
  eval "$(sed -n "/^sticky_process_findings()/,/^}/p" "'"$ROOT"'/shared/.plinth/review.sh")"
  f="$SDIR/findings-test.json"
  # AUTO-STICKY only for thrash classes (coverage-gap, …) — not arbitrary majors.
  thrash_desc="Coverage remains incomplete despite canary"
  jq -n --arg d "$thrash_desc" "{verdict:\"CHANGES_NEEDED\",summary:\"t\",findings:[
    {file:\"a.sh\",line:1,severity:\"major\",description:\$d,status:\"open\"},
    {file:\"a.sh\",line:2,severity:\"major\",description:\$d,status:\"open\"}
  ]}" > "$f"
  cd "'"$TMP/p9"'"
  sticky_process_findings "$f"
  id1=$(jq -r ".findings[0].id" "$f")
  id2=$(jq -r ".findings[1].id" "$f")
  [ -n "$id1" ] && [ "$id1" = "$id2" ] || { echo "expected shared base id, got $id1 vs $id2"; exit 1; }
  jq ".findings[].status=\"resolved\"" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  sticky_process_findings "$f"
  jq -n --arg d "$thrash_desc" "{verdict:\"CHANGES_NEEDED\",summary:\"t\",findings:[
    {file:\"a.sh\",line:1,severity:\"major\",description:\$d,status:\"open\"}
  ]}" > "$f"
  sticky_process_findings "$f"
  st=$(jq -r ".findings[0].status" "$f")
  [ "$st" = "resolved" ] || { echo "expected AUTO-STICKY resolve on thrash class, got $st"; jq . "$f"; exit 1; }
  # Non-thrash major must NOT auto-resolve
  jq -n "{verdict:\"CHANGES_NEEDED\",summary:\"t\",findings:[
    {file:\"a.sh\",line:1,severity:\"major\",description:\"real null deref on path X\",status:\"open\"}
  ]}" > "$f"
  sticky_process_findings "$f"
  jq ".findings[].status=\"resolved\"" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  sticky_process_findings "$f"
  jq -n "{verdict:\"CHANGES_NEEDED\",summary:\"t\",findings:[
    {file:\"a.sh\",line:1,severity:\"major\",description:\"real null deref on path X\",status:\"open\"}
  ]}" > "$f"
  sticky_process_findings "$f"
  stn=$(jq -r ".findings[0].status" "$f")
  [ "$stn" = "open" ] || { echo "non-thrash major must stay open, got $stn"; exit 1; }
  # Blob change must keep thrash reopen open
  printf "echo changed\n" > a.sh
  git add a.sh && git -c user.email=t@t -c user.name=t commit -qm "mutate a.sh"
  jq -n --arg d "$thrash_desc" "{verdict:\"CHANGES_NEEDED\",summary:\"t\",findings:[
    {file:\"a.sh\",line:1,severity:\"major\",description:\$d,status:\"open\"}
  ]}" > "$f"
  sticky_process_findings "$f"
  # First write resolved with old blob was lost — ledger may have absent. Force resolve+reopen path:
  jq ".findings[].status=\"resolved\"" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  sticky_process_findings "$f"
  jq -n --arg d "$thrash_desc" "{verdict:\"CHANGES_NEEDED\",summary:\"t\",findings:[
    {file:\"a.sh\",line:1,severity:\"major\",description:\$d,status:\"open\"}
  ]}" > "$f"
  sticky_process_findings "$f"
  st2=$(jq -r ".findings[0].status" "$f")
  [ "$st2" = "resolved" ] || { echo "same blob thrash should sticky-resolve after re-ledger, got $st2"; exit 1; }
  printf "echo again\n" > a.sh
  git add a.sh && git -c user.email=t@t -c user.name=t commit -qm "mutate2"
  jq -n --arg d "$thrash_desc" "{verdict:\"CHANGES_NEEDED\",summary:\"t\",findings:[
    {file:\"a.sh\",line:1,severity:\"major\",description:\$d,status:\"open\"}
  ]}" > "$f"
  sticky_process_findings "$f"
  st2b=$(jq -r ".findings[0].status" "$f")
  [ "$st2b" = "open" ] || { echo "expected open after blob change, got $st2b"; exit 1; }
  # Absent path must never AUTO-STICKY
  jq -n --arg d "$thrash_desc" "{verdict:\"CHANGES_NEEDED\",summary:\"t\",findings:[
    {file:\"no-such-file.sh\",line:1,severity:\"major\",description:\$d,status:\"open\"}
  ]}" > "$f"
  sticky_process_findings "$f"
  jq ".findings[].status=\"resolved\"" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  sticky_process_findings "$f"
  jq -n --arg d "$thrash_desc" "{verdict:\"CHANGES_NEEDED\",summary:\"t\",findings:[
    {file:\"no-such-file.sh\",line:1,severity:\"major\",description:\$d,status:\"open\"}
  ]}" > "$f"
  sticky_process_findings "$f"
  st3=$(jq -r ".findings[0].status" "$f")
  [ "$st3" = "open" ] || { echo "expected open on absent path, got $st3"; exit 1; }
  echo "sticky production ok"
' || fail "production sticky_process_findings unit"
pass "production sticky_process_findings (thrash-only AUTO-STICKY + blob fail-closed)"

# Explicit colliding reviewer ids get unique suffixes
bash -c '
  set -euo pipefail
  SDIR="'"$TMP"'/p9b/.plinth/session/review/x"
  mkdir -p "$SDIR" "'"$TMP"'/p9b"
  git -C "'"$TMP"'/p9b" init -q 2>/dev/null || true
  eval "$(sed -n "/^sticky_process_findings()/,/^}/p" "'"$ROOT"'/shared/.plinth/review.sh")"
  f="$SDIR/findings-test.json"
  jq -n "{verdict:\"CHANGES_NEEDED\",summary:\"t\",findings:[
    {id:\"dup\",file:\"a.sh\",line:1,severity:\"major\",description:\"one\",status:\"open\"},
    {id:\"dup\",file:\"a.sh\",line:2,severity:\"major\",description:\"two\",status:\"open\"}
  ]}" > "$f"
  cd "'"$TMP"'/p9b"
  sticky_process_findings "$f"
  id1=$(jq -r ".findings[0].id" "$f")
  id2=$(jq -r ".findings[1].id" "$f")
  [ "$id1" = "dup" ] || { echo "first explicit id should stay dup, got $id1"; exit 1; }
  [ "$id2" != "dup" ] && [ "$id1" != "$id2" ] || { echo "ids must be unique, got $id1 vs $id2"; exit 1; }
' || fail "explicit sticky id collision suffix"
pass "sticky suffixes colliding explicit reviewer ids"

# review_phase_for_round: corrupt phase → hardening (hermetic: unset ambient override)
env -u PLINTH_REVIEW_PHASE bash -c '
  set -euo pipefail
  d="'"$TMP"'/p10"
  mkdir -p "$d/.plinth/session"
  git -C "$d" init -q
  git -C "$d" checkout -qb feat/rp 2>/dev/null || git -C "$d" checkout -b feat/rp
  # Legacy slug (tr / → -) and encoded slug both accepted by review_phase_for_round.
  echo not-json > "$d/.plinth/session/phase-feat-rp.json"
  eval "$(sed -n "/^review_phase_for_round()/,/^}/p" "'"$ROOT"'/shared/.plinth/review.sh")"
  cd "$d"
  p=$(review_phase_for_round)
  [ "$p" = "hardening" ] || { echo "expected hardening for corrupt phase, got $p"; exit 1; }
' || fail "review_phase_for_round corrupt → hardening"
pass "review_phase_for_round fail-closed on corrupt phase"

# Operator Next line "Fix [Windows]…" preserved across harden refresh
setup_proj "$TMP/p11"
printf '%s\n' '# H' '## Next' '1. Fix [Windows] packaging regression' '2. custom operator note' \
  > "$TMP/p11/CHECKPOINT.md"
"$PLINTH" harden "$TMP/p11" >/dev/null
grep -F 'Fix [Windows] packaging regression' "$TMP/p11/CHECKPOINT.md" \
  || fail "operator Fix [Windows] line must be preserved"
grep -F 'custom operator note' "$TMP/p11/CHECKPOINT.md" \
  || fail "operator note must be preserved"
pass "handoff preserves operator-authored Next lines"

# Handoff preserves Goal/Evidence freeform + pre-archive
setup_proj "$TMP/p12"
printf '%s\n' '# H' '## Goal' 'Operator custom goal text keep me' '## Next' '1. do thing' \
  '## Evidence' '- my evidence note' '## Risks / Noticed' '- my risk' \
  > "$TMP/p12/CHECKPOINT.md"
"$PLINTH" build "$TMP/p12" >/dev/null
grep -F 'Operator custom goal text keep me' "$TMP/p12/CHECKPOINT.md" \
  || fail "Goal freeform must survive refresh"
grep -F 'my evidence note' "$TMP/p12/CHECKPOINT.md" \
  || fail "Evidence freeform must survive refresh"
grep -F 'my risk' "$TMP/p12/CHECKPOINT.md" \
  || fail "Risks freeform must survive refresh"
ls "$TMP/p12/.plinth/session"/handoff-*-pre-*.md >/dev/null 2>&1 \
  || fail "pre-overwrite archive must exist"
pass "handoff preserves Goal/Evidence/Risks + pre-archive"

# Phase slug: feat/a-b vs feat/a/b do not collide
setup_proj "$TMP/p13"
git -C "$TMP/p13" checkout -qb feat/a-b
"$PLINTH" harden "$TMP/p13" >/dev/null
f1=$(ls "$TMP/p13/.plinth/session"/phase-*.json)
git -C "$TMP/p13" checkout -qb feat/a/b
"$PLINTH" build "$TMP/p13" >/dev/null
f2=$(ls "$TMP/p13/.plinth/session"/phase-*.json | tr '\n' ' ')
# Two distinct phase files; feat/a-b still harden, feat/a/b build
[ "$(echo "$f2" | wc -w | tr -d ' ')" -ge 2 ] || fail "expected distinct phase files, got $f2"
ph_ab=$(jq -r .phase "$TMP/p13/.plinth/session/phase-feat%2Fa-b.json" 2>/dev/null || echo missing)
ph_aslash=$(jq -r .phase "$TMP/p13/.plinth/session/phase-feat%2Fa%2Fb.json" 2>/dev/null || echo missing)
[ "$ph_ab" = "harden" ] || fail "feat/a-b should stay harden, got $ph_ab"
[ "$ph_aslash" = "build" ] || fail "feat/a/b should be build, got $ph_aslash"
pass "lifecycle phase slug does not collide feat/a-b vs feat/a/b"

# Latest findings sort: findings-10 beats findings-2 under hyphenated path
setup_proj "$TMP/p14"
slug=feat%2Fcanary
mkdir -p "$TMP/p14/.plinth/session/review/$slug"
echo '{"findings":[]}' > "$TMP/p14/.plinth/session/review/$slug/findings-2.json"
echo '{"findings":[{"file":"x","line":1,"severity":"major","description":"r10","status":"open"}]}' \
  > "$TMP/p14/.plinth/session/review/$slug/findings-10.json"
# shellcheck source=/dev/null
eval "$(sed -n '/^_latest_findings_json()/,/^}/p' "$PLINTH")"
lat=$(_latest_findings_json "$TMP/p14/.plinth/session/review/$slug")
echo "$lat" | grep -q 'findings-10.json' || fail "expected findings-10, got $lat"
pass "latest findings uses basename numeric sort"

# thrash_policy: demote coverage; never demote auth bypass; docs/*.py stays major
THRASH_FN="$TMP/thrash_fn.sh"
sed -n '/^thrash_policy_process_findings()/,/^review_phase_for_round()/p' \
  "$ROOT/shared/.plinth/review.sh" | sed '$d' > "$THRASH_FN"
# shellcheck disable=SC1090
. "$THRASH_FN"
f=$(mktemp)
jq -n '{verdict:"CHANGES_NEEDED",summary:"t",findings:[
  {file:"x.sh",line:1,severity:"major",description:"Coverage remains incomplete despite canary",status:"open"},
  {file:"auth.py",line:2,severity:"major",description:"auth bypass on login route",status:"open"},
  {file:"README.md",line:3,severity:"major",description:"awkward wording in residual",status:"open"},
  {file:"docs/build.py",line:4,severity:"major",description:"crash on empty input",status:"open"},
  {file:"CHANGELOG.md",line:5,severity:"major",description:"missing release notes for v5",status:"open"},
  {file:"a.py",line:6,severity:"major",description:"unauthenticated access on /api",status:"open"},
  {file:"b.sh",line:7,severity:"major",description:"Still untested: plinth plan --deep merge path",status:"open"}
]}' > "$f"
scope=$(printf "%s\n" "x.sh" "auth.py" "README.md" "docs/build.py" "CHANGELOG.md" "a.py" "b.sh")
thrash_policy_process_findings "$f" build "$scope" "" "MANUAL.md" "fresh"
s0=$(jq -r ".findings[0].severity" "$f")
s1=$(jq -r ".findings[1].severity" "$f")
s2=$(jq -r ".findings[2].severity" "$f")
s3=$(jq -r ".findings[3].severity" "$f")
s4=$(jq -r ".findings[4].severity" "$f")
s5=$(jq -r ".findings[5].severity" "$f")
s6=$(jq -r ".findings[6].severity" "$f")
[ "$s0" = "minor" ] || fail "coverage should demote, got $s0"
[ "$s1" = "major" ] || fail "auth bypass must stay major, got $s1"
[ "$s2" = "minor" ] || fail "README prose should demote, got $s2"
[ "$s3" = "major" ] || fail "docs/build.py must stay major, got $s3"
[ "$s4" = "major" ] || fail "CHANGELOG must stay major, got $s4"
[ "$s5" = "major" ] || fail "unauthenticated must stay major, got $s5"
[ "$s6" = "major" ] || fail "plan --deep test gap must stay major, got $s6"
rm -f "$f"
pass "thrash_policy demotes coverage/README; keeps security + CHANGELOG + AC gaps"

# VERSION exact match via production helper version_changelog_match
bash -c '
  set -euo pipefail
  eval "$(sed -n "/^version_changelog_match()/,/^}/p" "'"$ROOT"'/shared/.plinth/review.sh")"
  d=$(mktemp -d)
  printf "%s\n" "# Plinth changelog" "" "## v5.0.0 — x" > "$d/CHANGELOG.md"
  echo 9.9.9 > "$d/VERSION"
  version_changelog_match "$d/VERSION" "$d/CHANGELOG.md" && { echo "9.9.9 must not match"; exit 1; }
  echo 5.0.0 > "$d/VERSION"
  version_changelog_match "$d/VERSION" "$d/CHANGELOG.md" || { echo "5.0.0 should match"; exit 1; }
  echo 5.0 > "$d/VERSION"
  version_changelog_match "$d/VERSION" "$d/CHANGELOG.md" && { echo "5.0 must not match"; exit 1; }
  printf "%s\n" "# Plinth changelog" "" "## v5.0.0-rc1 — x" > "$d/CHANGELOG.md"
  echo 5.0.0 > "$d/VERSION"
  version_changelog_match "$d/VERSION" "$d/CHANGELOG.md" && { echo "5.0.0 must not match v5.0.0-rc1"; exit 1; }
  rm -rf "$d"
' || fail "VERSION exact match"
pass "VERSION exact token match via production helper"

# plinth harden invalidates BUILD-era APPROVED@HEAD (encoded + legacy dirs)
setup_proj "$TMP/p20"
"$PLINTH" build "$TMP/p20" >/dev/null
enc=feat%2Fcanary
leg=feat-canary
head=$(git -C "$TMP/p20" rev-parse HEAD)
mkdir -p "$TMP/p20/.plinth/session/review/$enc" "$TMP/p20/.plinth/session/review/$leg"
jq -n --arg s "$head" '{verdict:"APPROVED",sha:$s,round:1,review_phase:"build"}' \
  > "$TMP/p20/.plinth/session/review/$enc/verdict.json"
jq -n --arg s "$head" '{verdict:"APPROVED",sha:$s,round:1}' \
  > "$TMP/p20/.plinth/session/review/$leg/verdict.json"
"$PLINTH" harden "$TMP/p20" >/dev/null
v=$(jq -r .verdict "$TMP/p20/.plinth/session/review/$enc/verdict.json")
[ "$v" = "UNBOUND" ] || fail "harden should UNBOUND encoded build approval, got $v"
v=$(jq -r .verdict "$TMP/p20/.plinth/session/review/$leg/verdict.json")
[ "$v" = "UNBOUND" ] || fail "harden should UNBOUND legacy build approval, got $v"
# Empty encoded dir + legacy APPROVED only
setup_proj "$TMP/p20b"
"$PLINTH" build "$TMP/p20b" >/dev/null
mkdir -p "$TMP/p20b/.plinth/session/review/$enc" "$TMP/p20b/.plinth/session/review/$leg"
head=$(git -C "$TMP/p20b" rev-parse HEAD)
# empty encoded dir (exists but no verdict)
: > "$TMP/p20b/.plinth/session/review/$enc/.keep"
jq -n --arg s "$head" '{verdict:"APPROVED",sha:$s,round:1,review_phase:"build"}' \
  > "$TMP/p20b/.plinth/session/review/$leg/verdict.json"
"$PLINTH" harden "$TMP/p20b" >/dev/null
v=$(jq -r .verdict "$TMP/p20b/.plinth/session/review/$leg/verdict.json")
[ "$v" = "UNBOUND" ] || fail "legacy-only APPROVED must UNBOUND on harden, got $v"
pass "plinth harden invalidates BUILD APPROVED (encoded+legacy)"

# Cost append under flock: two concurrent writers, one event id
python3 - <<'PY' || fail "cost concurrent append"
import json, os, tempfile, threading, time
from pathlib import Path
# Inline minimal append_entries logic from bin/plinth (fcntl+reload)
log = Path(tempfile.mkdtemp()) / "api-cost-log.jsonl"
log.write_text("")
def load_seen():
    s, c = set(), set()
    for line in log.read_text().splitlines():
        try:
            rec = json.loads(line)
        except Exception:
            continue
        i = rec.get("id")
        if isinstance(i, str):
            s.add(i)
    return s, c
def append(entries):
    import fcntl
    with log.open("a") as f:
        fcntl.flock(f.fileno(), fcntl.LOCK_EX)
        seen, _ = load_seen()
        for e in entries:
            if e["id"] in seen:
                continue
            f.write(json.dumps(e) + "\n")
            seen.add(e["id"])
        f.flush(); os.fsync(f.fileno())
errs = []
def worker():
    try:
        append([{"id": "claude:s:1:0.1", "vendor": "claude", "usd": 0.1}])
    except Exception as e:
        errs.append(e)
ts = [threading.Thread(target=worker) for _ in range(8)]
for t in ts: t.start()
for t in ts: t.join()
lines = [l for l in log.read_text().splitlines() if l.strip()]
assert not errs, errs
assert len(lines) == 1, f"expected 1 line, got {len(lines)}: {lines}"
print("cost concurrent ok")
PY
pass "cost log concurrent append dedupes event id"

# plan --deep with fake seats (no network) — multi-seat nits + security blocker
setup_proj "$TMP/p16"
mkdir -p "$TMP/p16/.plinth" "$TMP/fakebin"
echo "spec_path = PLAN.md" > "$TMP/p16/.plinth/config"
printf 'reviewer_vendor = claude\naudit_vendor = codex\nadvisor_vendor = grok\n' >> "$TMP/p16/.plinth/config"
"$PLINTH" plan "$TMP/p16" >/dev/null
for cli in claude codex grok; do
  cat > "$TMP/fakebin/$cli" <<'FAKE'
#!/usr/bin/env bash
role=security_ops
case "$0" in *codex*) role=completeness ;; *grok*) role=delete_simplify ;; esac
if [ "$role" = "security_ops" ]; then
  cat <<EOF
### Seat: $role
#### Blockers
- auth gap on login
#### Questions for human
- none
#### Nits
- none
#### One-line verdict
block
\`\`\`json
{"seat":"$role","blockers":["auth gap on login"],"questions":[],"nits":[],"verdict":"block"}
\`\`\`
EOF
else
  cat <<EOF
### Seat: $role
#### Blockers
- none
#### Questions for human
- none
#### Nits
- nit-$role
#### One-line verdict
ok
\`\`\`json
{"seat":"$role","blockers":[],"questions":[],"nits":["nit-$role"],"verdict":"ok"}
\`\`\`
EOF
fi
FAKE
  chmod +x "$TMP/fakebin/$cli"
done
PATH="$TMP/fakebin:$PATH" "$PLINTH" plan --deep "$TMP/p16" >/dev/null 2>&1 \
  || fail "plan --deep with fake seats failed"
[ -f "$TMP/p16/PLAN-REVIEW.md" ] || fail "PLAN-REVIEW.md missing after plan --deep"
mj="$TMP/p16/.plinth/session/plan-review-merge.json"
[ -f "$mj" ] || fail "plan-review-merge.json missing"
jq -e '.nits | length >= 2' "$mj" >/dev/null \
  || fail "expected >=2 nits from completeness+delete seats: $(cat "$mj")"
jq -e '.status == "complete" and .available_seats == 3' "$mj" >/dev/null \
  || fail "expected complete/3 available: $(cat "$mj")"
grep -qE 'auth gap|security_ops|completeness|delete_simplify' "$TMP/p16/PLAN-REVIEW.md" \
  || fail "PLAN-REVIEW missing seat/blocker content"
# Security blocker should appear in PLAN-REVIEW and preferably NEEDS-HUMAN
grep -q 'auth gap' "$TMP/p16/PLAN-REVIEW.md" || fail "security blocker missing from PLAN-REVIEW"
pass "plinth plan --deep multi-seat nits + security blocker"

# plan --deep: all seats fail → status empty, never looks like a clean 0/0/0 review
setup_proj "$TMP/p16b"
mkdir -p "$TMP/p16b/.plinth" "$TMP/fakebin-fail"
echo "spec_path = PLAN.md" > "$TMP/p16b/.plinth/config"
# advisor_vendor unset → default claude (not primary codex); still all fail via fakes
printf 'reviewer_vendor = codex\naudit_vendor = claude\n# advisor_vendor intentionally unset\nadvisor_model_max = fable\n' \
  >> "$TMP/p16b/.plinth/config"
"$PLINTH" plan "$TMP/p16b" >/dev/null
for cli in claude codex grok; do
  cat > "$TMP/fakebin-fail/$cli" <<'FAKE'
#!/usr/bin/env bash
echo "Not logged in · Please run /login" >&2
echo "Not logged in · Please run /login"
exit 1
FAKE
  chmod +x "$TMP/fakebin-fail/$cli"
done
PATH="$TMP/fakebin-fail:$PATH" "$PLINTH" plan --deep "$TMP/p16b" >/dev/null 2>&1 \
  || true  # empty status is success of the command; credit is withheld in merge
mj2="$TMP/p16b/.plinth/session/plan-review-merge.json"
[ -f "$mj2" ] || fail "plan-review-merge.json missing after failed seats"
jq -e '.status == "empty" and .unavailable_seats == 3 and .available_seats == 0' "$mj2" >/dev/null \
  || fail "expected empty/3 unavailable: $(cat "$mj2")"
jq -e '.open_blocker_count == 0 and .blockers == []' "$mj2" >/dev/null \
  || fail "empty merge must not invent blockers: $(cat "$mj2")"
grep -qE 'No full review credit|INCOMPLETE|empty|Status: \*\*empty\*\*' "$TMP/p16b/PLAN-REVIEW.md" \
  || fail "PLAN-REVIEW must flag no review credit: $(head -20 "$TMP/p16b/PLAN-REVIEW.md")"
# Seat header should use claude default for delete_simplify when advisor_vendor unset
grep -q 'delete_simplify (claude' "$TMP/p16b/PLAN-REVIEW.md" \
  || fail "unset advisor_vendor should default delete_simplify to claude: $(grep Seats "$TMP/p16b/PLAN-REVIEW.md")"
pass "plinth plan --deep empty merge + advisor_vendor default claude"

# Legacy verdict path: plinth next reads encoded OR legacy review dir
setup_proj "$TMP/p17"
"$PLINTH" harden "$TMP/p17" >/dev/null
printf '%s\n' '# H' '## Next' '' > "$TMP/p17/HANDOFF.md"
mkdir -p "$TMP/p17/.plinth/session/review/feat-canary"
head=$(git -C "$TMP/p17" rev-parse HEAD)
jq -n --arg s "$head" '{verdict:"APPROVED",sha:$s,round:1}' \
  > "$TMP/p17/.plinth/session/review/feat-canary/verdict.json"
set +e
out=$("$PLINTH" next "$TMP/p17" 2>&1)
rc=$?
set -e
echo "$out" | grep -qE 'open PR|APPROVED' \
  || fail "next should see legacy-slug APPROVED@HEAD: $out"
pass "plinth next resolves legacy review slug verdict"

# Sticky: AC-worded coverage must NOT auto-resolve as thrash class
bash -c '
  set -euo pipefail
  eval "$(sed -n "/^sticky_process_findings()/,/^}/p" "'"$ROOT"'/shared/.plinth/review.sh")"
  d=$(mktemp -d)
  git -C "$d" init -q
  git -C "$d" config user.email t@t
  git -C "$d" config user.name t
  echo x > "$d/a.sh"
  git -C "$d" add a.sh && git -C "$d" commit -qm i
  SDIR="$d/.plinth/session/review/x"
  mkdir -p "$SDIR"
  f="$SDIR/f.json"
  jq -n "{verdict:\"CHANGES_NEEDED\",summary:\"t\",findings:[
    {file:\"a.sh\",line:1,severity:\"major\",
     description:\"Coverage remains incomplete for AC 8\",status:\"open\"}
  ]}" > "$f"
  cd "$d"
  sticky_process_findings "$f"
  jq ".findings[].status=\"resolved\"" "$f" > "$f.t" && mv "$f.t" "$f"
  sticky_process_findings "$f"
  jq -n "{verdict:\"CHANGES_NEEDED\",summary:\"t\",findings:[
    {file:\"a.sh\",line:1,severity:\"major\",
     description:\"Coverage remains incomplete for AC 8\",status:\"open\"}
  ]}" > "$f"
  sticky_process_findings "$f"
  st=$(jq -r ".findings[0].status" "$f")
  [ "$st" = "open" ] || { echo "AC-worded gap must stay open, got $st id=$(jq -r .findings[0].id "$f")"; exit 1; }
  rm -rf "$d"
' || fail "sticky AC gap not thrash"
pass "AUTO-STICKY does not resolve AC-worded coverage gaps"

# Evidence live line updates on phase change at same HEAD
setup_proj "$TMP/p18"
printf '%s\n' '# H' '## Next' '1. x' '## Evidence' '- operator note' > "$TMP/p18/CHECKPOINT.md"
"$PLINTH" build "$TMP/p18" >/dev/null
grep -q 'Live: phase=build' "$TMP/p18/CHECKPOINT.md" || fail "expected Live build line"
"$PLINTH" harden "$TMP/p18" >/dev/null
grep -q 'Live: phase=harden' "$TMP/p18/CHECKPOINT.md" || fail "Live line must refresh on harden: $(grep Live "$TMP/p18/CHECKPOINT.md" || true)"
# Generated BUILD bullets must not remain after harden
if grep -qE 'Lifecycle phase: build|Snapshot reason: enter-build' "$TMP/p18/CHECKPOINT.md"; then
  fail "stale generated build evidence after harden: $(grep -E 'Lifecycle|Live' "$TMP/p18/CHECKPOINT.md")"
fi
pass "handoff Live evidence refreshes on phase change"

# Empty HANDOFF (generated path) also strips stale generated evidence
setup_proj "$TMP/p19"
"$PLINTH" build "$TMP/p19" >/dev/null
"$PLINTH" harden "$TMP/p19" >/dev/null
if grep -qE 'Lifecycle phase: build|Snapshot reason: enter-build' "$TMP/p19/CHECKPOINT.md"; then
  fail "generated path left stale build evidence: $(grep -E 'Lifecycle|Live|Snapshot' "$TMP/p19/CHECKPOINT.md")"
fi
grep -q 'Live: phase=harden' "$TMP/p19/CHECKPOINT.md" || fail "generated path missing Live harden"
pass "handoff generated evidence path no stale build after harden"

# plinth next done when empty Next / no NH
setup_proj "$TMP/p15"
printf '%s\n' '# H' '## Next' '' > "$TMP/p15/HANDOFF.md"
set +e
out=$("$PLINTH" next "$TMP/p15" 2>&1)
rc=$?
set -e
echo "$out" | grep -q 'status: done' || fail "expected done: $out"
[ "$rc" -eq 3 ] || fail "plinth next exit 3 for done, got $rc"
pass "plinth next done when idle"

# Strict delta: verify demotes thrash classes outside fix pathspec only —
# never arbitrary "free-roam" majors (real bugs stay major even out-of-delta).
# shellcheck disable=SC1090
. "$THRASH_FN"
f=$(mktemp)
jq -n '{verdict:"CHANGES_NEEDED",summary:"t",findings:[
  {file:"bin/plinth",line:1,severity:"major",description:"real null deref in next routing",status:"open",id:"keep"},
  {file:"untouched/other.c",line:2,severity:"major",description:"coverage remains incomplete for asymptotic free roam",status:"open",id:"thrash1"},
  {file:"untouched/other.c",line:3,severity:"major",description:"Clicking Save does nothing",status:"open",id:"bug1"},
  {file:"auth.py",line:4,severity:"major",description:"auth bypass on login",status:"open",id:"sec1"}
]}' > "$f"
thrash_policy_process_findings "$f" build "bin/plinth" "keep" "MANUAL.md" "verify"
s0=$(jq -r '.findings[]|select(.id=="keep")|.severity' "$f")
s1=$(jq -r '.findings[]|select(.id=="thrash1")|.severity' "$f")
sbug=$(jq -r '.findings[]|select(.id=="bug1")|.severity' "$f")
s2=$(jq -r '.findings[]|select(.id=="sec1")|.severity' "$f")
[ "$s0" = "major" ] || fail "ledger open must stay major, got $s0"
[ "$s1" = "minor" ] || fail "outside delta thrash class must demote, got $s1"
[ "$sbug" = "major" ] || fail "outside delta real bug must stay major, got $sbug"
[ "$s2" = "major" ] || fail "security outside delta must stay major, got $s2"
rm -f "$f"
pass "BUILD verify strict delta demotes thrash-only; keeps real bugs + security + ledger"

# residual bind authorizes ship when only residual hygiene changed
setup_proj "$TMP/p21"
head=$(git -C "$TMP/p21" rev-parse HEAD)
"$PLINTH" residual "$TMP/p21" --bind --note "canary residual land" >/dev/null
[ -f "$TMP/p21/.plinth/RESIDUAL.json" ] || fail "RESIDUAL.json missing"
jq -e --arg s "$head" '.bound==true and .sha==$s' "$TMP/p21/.plinth/RESIDUAL.json" >/dev/null \
  || fail "residual bind shape wrong: $(cat "$TMP/p21/.plinth/RESIDUAL.json")"
# Commit residual alone — still valid (only RESIDUAL changed after product sha)
git -C "$TMP/p21" add .plinth/RESIDUAL.json
git -C "$TMP/p21" commit -qm "residual land"
# Source production residual helpers (awk brace-count; sed-to-first-} truncates).
awk '
  /^residual_path\(\)/ {p=1}
  /^residual_ship_ok\(\)/ {p=1}
  p {
    print
    for (i=1;i<=length($0);i++) {
      c=substr($0,i,1)
      if (c=="{") d++
      if (c=="}") { d--; if (d==0) p=0 }
    }
  }
' "$PLINTH" > "$TMP/residual_fn.sh"
# shellcheck disable=SC1090
. "$TMP/residual_fn.sh"
type residual_ship_ok >/dev/null 2>&1 || fail "failed to source residual_ship_ok from bin/plinth"
residual_ship_ok "$TMP/p21" || fail "residual_ship_ok should pass after residual-only commit"
# HANDOFF-only still ok
printf 'h\n' > "$TMP/p21/HANDOFF.md"
git -C "$TMP/p21" add HANDOFF.md && git -C "$TMP/p21" commit -qm "handoff hygiene"
residual_ship_ok "$TMP/p21" || fail "residual_ship_ok should pass after HANDOFF-only"
# NEEDS-HUMAN change must invalidate (project queue, not residual hygiene)
mkdir -p "$TMP/p21/.plinth"
printf '# NH\n- [ ] [BLOCKING] x\n' > "$TMP/p21/.plinth/NEEDS-HUMAN.md"
git -C "$TMP/p21" add .plinth/NEEDS-HUMAN.md && git -C "$TMP/p21" commit -qm "queue edit"
residual_ship_ok "$TMP/p21" && fail "residual_ship_ok must FAIL after NEEDS-HUMAN change" || true
# product change after residual must invalidate
echo z >> "$TMP/p21/f"
git -C "$TMP/p21" add f && git -C "$TMP/p21" commit -qm "product after residual"
rf="$TMP/p21/.plinth/RESIDUAL.json"
rsha=$(jq -r .sha "$rf")
ch=$(git -C "$TMP/p21" diff --name-only "$rsha" HEAD)
printf '%s\n' "$ch" | grep -Ev '^\.plinth/RESIDUAL\.json$|^HANDOFF\.md$' | grep -q . \
  || fail "expected product path in residual window: $ch"
residual_ship_ok "$TMP/p21" && fail "residual_ship_ok must FAIL after product change" || true
pass "residual bind + hygiene window (HANDOFF ok; NEEDS-HUMAN/product invalidate)"

# residual against wrong tip (targeted-merge class): authorize bound tip only
setup_proj "$TMP/p22"
"$PLINTH" residual "$TMP/p22" --bind --note "tip-a residual" >/dev/null
git -C "$TMP/p22" add .plinth/RESIDUAL.json && git -C "$TMP/p22" commit -qm residual-a
tip_a=$(git -C "$TMP/p22" rev-parse HEAD)
# Orphan tip with no ancestry from residual.sha
git -C "$TMP/p22" checkout --orphan other-tip >/dev/null 2>&1
echo o > "$TMP/p22/o" && git -C "$TMP/p22" add o && git -C "$TMP/p22" commit -qm orphan
tip_b=$(git -C "$TMP/p22" rev-parse HEAD)
# Keep residual file from tip_a in the tree for residual_ship_ok reads
mkdir -p "$TMP/p22/.plinth"
git -C "$TMP/p22" show "$tip_a:.plinth/RESIDUAL.json" > "$TMP/p22/.plinth/RESIDUAL.json"
# shellcheck disable=SC1090
. "$TMP/residual_fn.sh"
residual_ship_ok "$TMP/p22" "$tip_a" || fail "residual should authorize its own tip_a"
residual_ship_ok "$TMP/p22" "$tip_b" && fail "residual for tip_a must NOT authorize unrelated tip_b" || true
pass "residual authorizes bound tip only (not unrelated tip)"

# plinth#11: git diff --raw failure → Tier 2 (not empty/Tier 0)
setup_proj "$TMP/p23b"
mkdir -p "$TMP/p23b/.plinth" "$TMP/badgit2"
cp "$ROOT/shared/.plinth/risk-classify.sh" "$TMP/p23b/.plinth/risk-classify.sh"
chmod +x "$TMP/p23b/.plinth/risk-classify.sh"
# Ensure a base branch named main exists (setup_proj may leave only feat/canary).
git -C "$TMP/p23b" branch -f main HEAD~1 2>/dev/null || git -C "$TMP/p23b" branch -f main "$(git -C "$TMP/p23b" rev-list --max-parents=0 HEAD)"
REALGIT="$(command -v git)"
cat > "$TMP/badgit2/git" <<G
#!/bin/bash
if [ "\$1" = "diff" ] && [ "\$2" = "--raw" ]; then exit 128; fi
exec "$REALGIT" "\$@"
G
chmod +x "$TMP/badgit2/git"
out="$(cd "$TMP/p23b" && PATH="$TMP/badgit2:$PATH" ./.plinth/risk-classify.sh main 2>/dev/null || true)"
tier="$(printf '%s' "$out" | jq -r .tier 2>/dev/null || echo x)"
[ "$tier" = "2" ] || fail "plinth#11: git diff --raw failure must be Tier 2, got tier=$tier out=$out"
reasons="$(printf '%s' "$out" | jq -r '.reasons[0] // empty' 2>/dev/null || true)"
printf '%s' "$reasons" | grep -qi 'diff --raw failed' \
  || fail "plinth#11: expected raw-failed reason, got: $reasons"
pass "plinth#11 git diff --raw failure fails closed to Tier 2"

# plinth#2: codex event-stream parse must not use jq|head (SIGPIPE under pipefail)
bash -c '
  set -euo pipefail
  f=$(mktemp)
  for i in $(seq 1 50); do
    printf "%s\n" "{\"type\":\"other\",\"n\":$i}"
  done > "$f"
  printf "%s\n" "{\"type\":\"thread.started\",\"thread_id\":\"tid-abc\"}" >> "$f"
  for i in $(seq 1 50); do
    printf "%s\n" "{\"type\":\"item\",\"n\":$i}"
  done >> "$f"
  printf "%s\n" "{\"type\":\"turn.completed\",\"usage\":{\"input_tokens\":9}}" >> "$f"
  RSID="$(jq -rs "[.[] | select(.type==\"thread.started\") | .thread_id // empty] | first // empty" "$f")"
  RUSAGE="$(jq -rcs "[.[] | select(.type==\"turn.completed\") | .usage] | last // null" "$f")"
  rm -f "$f"
  [ "$RSID" = "tid-abc" ] || { echo "RSID=$RSID"; exit 1; }
  echo "$RUSAGE" | jq -e ".input_tokens == 9" >/dev/null
'
pass "plinth#2 codex event slurp avoids SIGPIPE (jq|head)"

# plinth#20: verify open-findings ledger caps prefer blockers
bash -c '
  set -euo pipefail
  f=$(mktemp)
  jq -n "{findings: ([range(1;60)] | map({status:\"open\",severity:(if . < 3 then \"blocker\" elif . < 10 then \"major\" else \"minor\" end),file:(\"f\"+tostring+\".go\"),line:.,description:(\"d\"+tostring),id:(\"id\"+tostring)}))}" > "$f"
  out="$(jq -c --argjson n 40 "
    [.findings[] | select(.status == \"open\")
      | {id:(.id//null),file,line,severity,description,
         _rank:(if .severity==\"blocker\" then 0 elif .severity==\"major\" then 1 else 2 end)}]
    | sort_by(._rank) | map(del(._rank))
    | .[0:\$n]
  " "$f")"
  rm -f "$f"
  n="$(printf "%s" "$out" | jq "length")"
  [ "$n" = "40" ] || { echo "cap len=$n"; exit 1; }
  b="$(printf "%s" "$out" | jq "[.[]|select(.severity==\"blocker\")]|length")"
  [ "$b" = "2" ] || { echo "blockers first expected 2 got $b"; exit 1; }
'
pass "plinth#20 verify findings ledger cap prefers blockers"

# plinth#21: custom CLAUDE.md migrates into DRIVER-project.md then shell regenerates
setup_proj "$TMP/p21mig"
"$PLINTH" init "$TMP/p21mig" >/dev/null 2>&1 || true
cat > "$TMP/p21mig/CLAUDE.md" <<'EOF'
# CLAUDE.md

You are the implementer for this repository.

## Project-specific notes
- NEVER invent regulatory rates
- toolchain: go 1.22 pinned
- domain: texas affordable housing only
EOF
# Reset DRIVER-project to scaffold so migration replaces (not appends) once
cp "$ROOT/templates/DRIVER-project.md" "$TMP/p21mig/.plinth/DRIVER-project.md"
out21="$("$PLINTH" update "$TMP/p21mig" 2>&1)" || fail "plinth update for #21 migration failed: $out21"
printf '%s' "$out21" | grep -q 'migrated: custom CLAUDE.md' \
  || fail "expected migrate note: $out21"
grep -q "NEVER invent regulatory rates" "$TMP/p21mig/.plinth/DRIVER-project.md" \
  || fail "DRIVER-project missing migrated notes: $(cat "$TMP/p21mig/.plinth/DRIVER-project.md")"
# Scaffold heading alone must not remain as the only content before migration body
grep -qF "Plinth driver shell (version-pinned)" "$TMP/p21mig/CLAUDE.md" \
  || fail "CLAUDE.md not regenerated as shell: $(head -5 "$TMP/p21mig/CLAUDE.md")"
# No double scaffold dump: at most one "# Project-Specific Driver Notes" title
titles="$(grep -c '^# Project-Specific Driver Notes' "$TMP/p21mig/.plinth/DRIVER-project.md" || true)"
[ "$titles" = "1" ] || fail "expected single DRIVER-project title after scaffold replace, got $titles"
pass "plinth#21 custom CLAUDE.md migrates into DRIVER-project.md"

# plinth#32: delegation requires non-empty transcript; optional before-sha binds
setup_proj "$TMP/p32del"
mkdir -p "$TMP/p32del/.plinth"
cp "$ROOT/shared/.plinth/lane-guard.sh" "$TMP/p32del/.plinth/lane-guard.sh"
chmod +x "$TMP/p32del/.plinth/lane-guard.sh"
trf=$(mktemp)
echo "MODEL: grok-test-delegate" > "$trf"
set +e
out="$("$TMP/p32del/.plinth/lane-guard.sh" delegation grok 0 /nonexistent/out 2>&1)"
rc=$?
set -e
[ "$rc" = "3" ] || fail "empty/missing transcript must exit 3, got $rc $out"
printf '%s' "$out" | grep -qi unavailable || fail "expected unavailable for missing transcript: $out"
bsha=$(git -C "$TMP/p32del" rev-parse HEAD)
# Must run inside the fixture repo so before-sha resolves to that HEAD (not the host checkout).
out2="$(cd "$TMP/p32del" && ./.plinth/lane-guard.sh delegation grok 0 "$trf" "$bsha" 2>&1)" \
  || fail "delegation with transcript+before failed: $out2"
printf '%s' "$out2" | grep -q "delegation recorded:" || fail "expected receipt line: $out2"
printf '%s' "$out2" | grep -q "before=$bsha" || fail "expected before= binding: $out2"
rm -f "$trf"
pass "plinth#32 delegation receipt requires transcript + optional before-sha"


# ── residual closeout 5.0.5 ──────────────────────────────────────────────
_review_src="$ROOT/shared/.plinth/review.sh"
[ -f "$_review_src" ] || fail "missing $_review_src"

_gap_n="$(grep -c 'no end-to-end test covers' "$_review_src" || true)"
[ "$_gap_n" -ge 3 ] || fail "end-to-end test-gap regex under-copied (count=$_gap_n want >=3)"
grep -qF '(^|[^A-Za-z0-9_])AC[[:space:]]*[0-9]+' "$_review_src" \
  || fail "AC edge pattern missing (avoid jq \\b backspace trap)"
pass "residual: sticky+thrash test-gap regex parity markers present"

THRASH_FN2="$TMP/thrash_fn2.sh"
sed -n '/^thrash_policy_process_findings()/,/^review_phase_for_round()/p' \
  "$_review_src" | sed '$d' > "$THRASH_FN2"
grep -q 'is_precedence_must_block' "$THRASH_FN2" \
  || fail "thrash policy missing is_precedence_must_block"
# shellcheck disable=SC1090
. "$THRASH_FN2"
_tf=$(mktemp)
jq -n '{verdict:"CHANGES_NEEDED",summary:"t",findings:[
  {file:"other.go",line:1,severity:"major",
   description:"no end-to-end test covers the new changed quota parser",status:"open",id:"t1"},
  {file:"docs/readme-extra.md",line:2,severity:"major",
   description:"coverage remains incomplete for asymptotic cases",status:"open",id:"t2"}
]}' > "$_tf"
thrash_policy_process_findings "$_tf" "build" "fixed.go" "" "SPEC.md" "verify"
sev1=$(jq -r '.findings[] | select(.id=="t1") | .severity' "$_tf")
[ "$sev1" = "major" ] || fail "real e2e test gap demoted to $sev1 (must stay major)"
sev2=$(jq -r '.findings[] | select(.id=="t2") | .severity' "$_tf")
[ "$sev2" = "minor" ] || fail "asymptotic coverage should demote to minor, got $sev2"
rm -f "$_tf"
pass "residual: thrash keeps real e2e gap; demotes asymptotic outside delta"

setup_proj "$TMP/pphase"
mkdir -p "$TMP/pphase/.plinth/session"
_br=$(git -C "$TMP/pphase" symbolic-ref --short HEAD 2>/dev/null || echo main)
_slug=$(printf '%s' "$_br" | sed 's/\//%2F/g; s/ /%20/g')
echo '{"phase":"harden"}' > "$TMP/pphase/.plinth/session/phase-${_slug}.json"
PHASE_FN="$TMP/phase_fn.sh"
sed -n '/^review_phase_for_round()/,/^run_round()/p' "$_review_src" | sed '$d' > "$PHASE_FN"
_ph_out="$(cd "$TMP/pphase" && PLINTH_REVIEW_PHASE=build bash -c '
  set -euo pipefail
  # shellcheck disable=SC1090
  . "'"$PHASE_FN"'"
  review_phase_for_round
' 2>&1)"
printf '%s\n' "$_ph_out" | tail -1 | grep -qx 'hardening' \
  || fail "env build must not downgrade lifecycle harden, got: $_ph_out"
pass "residual: PLINTH_REVIEW_PHASE=build does not downgrade lifecycle harden"

# Hollow plan seat (header-only / empty JSON) rejected; explicit - none + verdict accepted
_plan_ok_src="$TMP/plan_ok_fn.sh"
sed -n '/^_plan_seat_output_ok()/,/^}/p' "$PLINTH" > "$_plan_ok_src"
# shellcheck disable=SC1090
. "$_plan_ok_src"
_plan_seat_output_ok $'### Seat: completeness\n#### Blockers\n' \
  && fail "header-only plan seat should fail"
_plan_seat_output_ok $'### Seat: completeness\n```json\n{"seat":"completeness","blockers":[],"questions":[],"nits":[],"verdict":""}\n```\n' \
  && fail "empty JSON plan seat should fail"
_plan_seat_output_ok $'### Seat: completeness\n#### Blockers\n- none\n#### Questions for human\n- none\n#### Nits\n- none\n#### One-line verdict\nok\n```json\n{"seat":"completeness","blockers":[],"questions":[],"nits":[],"verdict":"ok"}\n```\n' \
  || fail "explicit none + verdict should pass"
pass "residual: plan seat rejects hollow header/empty JSON"

_df=$(mktemp)
printf '%s\n' '# Project-Specific Driver Notes' '' \
  '<!-- Operator rule: always use texas housing rates for compliance checks. -->' > "$_df"
_scaf_src="$TMP/scaf_fn.sh"
sed -n '/^_driver_project_is_scaffold()/,/^}/p' "$PLINTH" > "$_scaf_src"
# shellcheck disable=SC1090
. "$_scaf_src"
if _driver_project_is_scaffold "$_df"; then
  fail "comment-only custom DRIVER-project treated as scaffold"
fi
rm -f "$_df"
pass "residual: comment-only DRIVER-project is not scaffold"

setup_proj "$TMP/p32b"
cp "$ROOT/shared/.plinth/lane-guard.sh" "$TMP/p32b/.plinth/lane-guard.sh"
chmod +x "$TMP/p32b/.plinth/lane-guard.sh"
trf=$(mktemp)
git -C "$TMP/p32b" commit --allow-empty -m "second" >/dev/null 2>&1 || true
_old=$(git -C "$TMP/p32b" rev-parse HEAD~1 2>/dev/null || git -C "$TMP/p32b" rev-parse HEAD)
_new=$(git -C "$TMP/p32b" rev-parse HEAD)
printf 'BEFORE: %s\nMODEL: x\nok\n' "$_old" > "$trf"
set +e
outm="$(cd "$TMP/p32b" && ./.plinth/lane-guard.sh delegation grok 0 "$trf" "$_new" 2>&1)"
rcm=$?
set -e
[ "$rcm" = "3" ] || fail "mismatched transcript BEFORE must exit 3, got $rcm $outm"
printf '%s' "$outm" | grep -qiE 'does not match|mismatched|stale' \
  || fail "expected mismatch message: $outm"
rm -f "$trf"
pass "residual: delegation rejects transcript BEFORE mismatch"

_vf=$(mktemp)
echo '{}' > "$_vf"
_vf_src="$TMP/validate_fn.sh"
sed -n '/^validate_findings()/,/^}/p' "$_review_src" > "$_vf_src"
# shellcheck disable=SC1090
. "$_vf_src"
if validate_findings "$_vf"; then
  fail "validate_findings should reject {}"
fi
rm -f "$_vf"
pass "residual: validate_findings rejects corrupt {}"



# residual r2: hollow free-floating bullet rejected; stock scaffold still scaffold
bash -c '
  set -euo pipefail
  eval "$(sed -n "/^_plan_seat_output_ok()/,/^}/p" "'"$PLINTH"'")"
  eval "$(sed -n "/^_driver_project_is_scaffold()/,/^}/p" "'"$PLINTH"'")"
  _plan_seat_output_ok $'"'"'### Seat: completeness
Generated notes:
- model completed
'"'"' && exit 1 || true
  _driver_project_is_scaffold "'"$ROOT"'/templates/DRIVER-project.md" || exit 1
  f=$(mktemp)
  printf "%s\n" "# Project-Specific Driver Notes" "" "<!-- use Go 1.23 -->" > "$f"
  if _driver_project_is_scaffold "$f"; then rm -f "$f"; exit 1; fi
  rm -f "$f"
' || fail "hollow free-floating bullet / scaffold edge cases"
pass "residual: hollow free-float rejected; stock scaffold; short comment kept"

# residual r2: sticky does not thrash-class "for the new" coverage wording
bash -c '
  set -euo pipefail
  eval "$(sed -n "/^sticky_process_findings()/,/^}/p" "'"$ROOT"'/shared/.plinth/review.sh")"
  d=$(mktemp -d)
  git -C "$d" init -q
  git -C "$d" config user.email t@t
  git -C "$d" config user.name t
  echo x > "$d/a.sh"
  git -C "$d" add a.sh && git -C "$d" commit -qm i
  SDIR="$d/.plinth/session/review/x"
  mkdir -p "$SDIR"
  f="$SDIR/f.json"
  jq -n "{verdict:\"CHANGES_NEEDED\",summary:\"t\",findings:[
    {file:\"a.sh\",line:1,severity:\"major\",
     description:\"Coverage remains incomplete for the new empty-vendor branch\",status:\"open\"}
  ]}" > "$f"
  cd "$d"
  sticky_process_findings "$f"
  id=$(jq -r .findings[0].id "$f")
  decoded=$(printf "%s" "$id" | base64 -d 2>/dev/null || true)
  printf "%s" "$decoded" | grep -q "class:coverage-gap" && { echo "still coverage-gap: $decoded"; exit 1; }
  jq ".findings[].status=\"resolved\"" "$f" > "$f.t" && mv "$f.t" "$f"
  sticky_process_findings "$f"
  jq -n "{verdict:\"CHANGES_NEEDED\",summary:\"t\",findings:[
    {file:\"a.sh\",line:1,severity:\"major\",
     description:\"Coverage remains incomplete for the new empty-vendor branch\",status:\"open\"}
  ]}" > "$f"
  sticky_process_findings "$f"
  st=$(jq -r .findings[0].status "$f")
  [ "$st" = "open" ] || { echo "should stay open, got $st"; exit 1; }
  rm -rf "$d"
' || fail "sticky for-the-new coverage must not AUTO-STICKY"
pass "residual: sticky keeps for-the-new coverage gaps open"

# residual r2: thrash keeps NaN/data-loss/documented-command outside delta
THRASH_FN3="$TMP/thrash_fn3.sh"
sed -n "/^thrash_policy_process_findings()/,/^review_phase_for_round()/p" \
  "$ROOT/shared/.plinth/review.sh" | sed "\$d" > "$THRASH_FN3"
# shellcheck disable=SC1090
. "$THRASH_FN3"
_tf3=$(mktemp)
jq -n "{verdict:\"CHANGES_NEEDED\",summary:\"t\",findings:[
  {file:\"other.go\",line:1,severity:\"major\",description:\"The quota row renders NaN% for an empty overall value\",status:\"open\",id:\"n1\"},
  {file:\"other.go\",line:2,severity:\"major\",description:\"Saving an empty record erases the previous value\",status:\"open\",id:\"n2\"},
  {file:\"other.go\",line:3,severity:\"major\",description:\"The documented command no longer exists\",status:\"open\",id:\"n3\"}
]}" > "$_tf3"
thrash_policy_process_findings "$_tf3" "build" "fixed.go" "" "SPEC.md" "verify"
for id in n1 n2 n3; do
  sev=$(jq -r --arg i "$id" ".findings[]|select(.id==\$i)|.severity" "$_tf3")
  [ "$sev" = "major" ] || fail "precedence class $id demoted to $sev"
done
rm -f "$_tf3"
pass "residual: thrash keeps NaN/data-loss/documented-command majors"

# residual r2: agy auditor uses -p (non-interactive print) with stdin redirect
grep -E 'agy -p --sandbox.*<\s*"\$_agy_p"' "$ROOT/shared/.plinth/review.sh" \
  || fail "agy auditor must use -p non-interactive print mode with stdin"
pass "residual: agy auditor invokes -p"



# residual r3: real bugs outside delta stay major (not keyword-list dependent)
. "$THRASH_FN2" 2>/dev/null || {
  THRASH_FN2="$TMP/thrash_fn2b.sh"
  sed -n '/^thrash_policy_process_findings()/,/^review_phase_for_round()/p' \
    "$ROOT/shared/.plinth/review.sh" | sed '$d' > "$THRASH_FN2"
  # shellcheck disable=SC1090
  . "$THRASH_FN2"
}
_tf4=$(mktemp)
jq -n '{verdict:"CHANGES_NEEDED",summary:"t",findings:[
  {file:"other.go",line:1,severity:"major",description:"Clicking Save does nothing",status:"open",id:"b1"},
  {file:"other.go",line:2,severity:"major",description:"Clearing the name deletes the saved settings",status:"open",id:"b2"},
  {file:"other.go",line:3,severity:"major",description:"The required export flag is absent",status:"open",id:"b3"}
]}' > "$_tf4"
thrash_policy_process_findings "$_tf4" "build" "fixed.go" "" "SPEC.md" "verify"
for id in b1 b2 b3; do
  sev=$(jq -r --arg i "$id" '.findings[]|select(.id==$i)|.severity' "$_tf4")
  [ "$sev" = "major" ] || fail "real-bug class $id demoted to $sev"
done
rm -f "$_tf4"
pass "residual: out-of-delta real bugs stay major without keyword match"

# residual r3: single-section - none is hollow
bash -c '
  set -euo pipefail
  eval "$(sed -n "/^_plan_seat_output_ok()/,/^}/p" "'"$PLINTH"'")"
  _plan_seat_output_ok $'"'"'### Seat: completeness
#### Blockers
- none
'"'"' && exit 1 || true
' || fail "single-section - none must be hollow"
pass "residual: single-section plan seat is hollow"

# residual r3: stock comment + short AWS token kept
bash -c '
  set -euo pipefail
  eval "$(sed -n "/^_driver_project_is_scaffold()/,/^}/p" "'"$PLINTH"'")"
  f=$(mktemp)
  # stock template body + AWS in the comment
  cat "'"$ROOT"'/templates/DRIVER-project.md" | sed "s/real notes\\./real notes. AWS./" > "$f"
  if _driver_project_is_scaffold "$f"; then rm -f "$f"; exit 1; fi
  rm -f "$f"
' || fail "stock template with AWS append must not be scaffold"
pass "residual: stock-comment AWS append preserved"



# ── residual-zero: thrash never demotes mixed asymptotic+real-bug wording ──
THRASH_FNZ="$TMP/thrash_zero.sh"
sed -n '/^thrash_policy_process_findings()/,/^review_phase_for_round()/p' \
  "$ROOT/shared/.plinth/review.sh" | sed '$d' > "$THRASH_FNZ"
# shellcheck disable=SC1090
. "$THRASH_FNZ"
_tz=$(mktemp)
for desc in \
  "Helper extraction for the new path. Clicking Save does nothing" \
  "Existing coverage either injects fixtures. Clicking Save does nothing" \
  "Missing cases include empty input. Clicking Save does nothing"
do
  jq -n --arg d "$desc" '{verdict:"CHANGES_NEEDED",summary:"t",findings:[
    {file:"x.go",line:1,severity:"major",description:$d,status:"open",id:"c1"}
  ]}' > "$_tz"
  thrash_policy_process_findings "$_tz" "build" "x.go" "" "SPEC.md" "fresh"
  sev=$(jq -r '.findings[0].severity' "$_tz")
  [ "$sev" = "major" ] || fail "mixed asymptotic+bug demoted to $sev: $desc"
done
rm -f "$_tz"
pass "residual-zero: combined asymptotic+bug stays major"

# ── residual-zero: product-path — both verify prior schema gates present ──
# Production run_round calls validate_findings on prior before ledger+re-merge.
n_prior_val=$(grep -c 'verify prior findings' "$ROOT/shared/.plinth/review.sh" || true)
[ "$n_prior_val" -ge 2 ] || fail "expected >=2 verify prior schema messages, got $n_prior_val"
# Exercise production validate_findings (extracted) on corrupt {}
_vf_src="$TMP/validate_fn_zero.sh"
sed -n '/^validate_findings()/,/^}/p' "$ROOT/shared/.plinth/review.sh" > "$_vf_src"
# shellcheck disable=SC1090
. "$_vf_src"
_bad=$(mktemp)
echo '{}' > "$_bad"
if validate_findings "$_bad"; then fail "validate_findings must reject {}"; fi
echo '{"verdict":"CHANGES_NEEDED","summary":"x","findings":[{"file":"a","line":1,"severity":"major","description":"d","status":"open"}]}' > "$_bad"
validate_findings "$_bad" || fail "validate_findings must accept schema-valid findings"
rm -f "$_bad"
pass "residual-zero: verify prior schema gates present + validate_findings product path"

# ── residual-zero: plinth update migration (comment-only custom + stock+AWS) ──
setup_proj "$TMP/pzero_mig"
"$PLINTH" init "$TMP/pzero_mig" >/dev/null 2>&1 || true
# comment-only custom DRIVER-project must not be treated as scaffold wipe
cat > "$TMP/pzero_mig/.plinth/DRIVER-project.md" <<'EOF'
# Project-Specific Driver Notes

<!-- Operator: use Go 1.23 for this repo only. -->
EOF
cat > "$TMP/pzero_mig/CLAUDE.md" <<'EOF'
# CLAUDE.md
You are the implementer.
## Project-specific notes
- NEVER invent regulatory rates without a cite.
EOF
outm="$("$PLINTH" update "$TMP/pzero_mig" 2>&1)" || fail "plinth update failed: $outm"
printf '%s' "$outm" | grep -q 'migrated: custom CLAUDE.md' || fail "expected migrate: $outm"
# Go 1.23 note must survive (append or keep)
grep -q 'Go 1.23\|NEVER invent regulatory' "$TMP/pzero_mig/.plinth/DRIVER-project.md" \
  || fail "DRIVER-project lost operator notes: $(cat "$TMP/pzero_mig/.plinth/DRIVER-project.md")"
pass "residual-zero: plinth update preserves comment-only DRIVER notes + migrates CLAUDE"

# ── residual-zero: plan hollow JSON via product _plan_seat_output_ok ──
bash -c '
  set -euo pipefail
  eval "$(sed -n "/^_plan_seat_output_ok()/,/^}/p" "'"$PLINTH"'")"
  # empty verdict + none markers must fail
  _plan_seat_output_ok $'"'"'### Seat: x
```json
{"blockers":["none"],"questions":[],"nits":[],"verdict":""}
```
'"'"' && exit 1 || true
  # real verdict ok
  _plan_seat_output_ok $'"'"'### Seat: x
#### Blockers
- none
#### Questions for human
- none
#### Nits
- none
```json
{"blockers":[],"questions":[],"nits":[],"verdict":"ok"}
```
'"'"' || exit 1
' || fail "plan seat product hollow checks failed"
pass "residual-zero: plan seat product hollow/non-hollow path"

# ── upstream #63: --help must be SIDE-EFFECT FREE for every command ──────────
# `plinth harden --help` used to fall through to dispatch: it ran the pathless
# harden, flipped BUILD→HARDEN, and wrote phase-<slug>.json + CHECKPOINT.md +
# HANDOFF.md. A help flag that mutates the project is a trap — the operator asking
# "what does this do?" is exactly the one who does not want it done. Digest the
# whole tree before and after; byte-identical is the assertion, not "looks fine".
# Every step is EXPLICITLY checked; nothing relies on errexit. A subshell on the
# LEFT of `|| fail` runs with errexit suppressed, so `set -euo pipefail` inside it
# does not abort on a failing `cd`/`git`/`plinth init` — the setup could collapse and
# the later assertions would still "pass". Found by review (round 1, v5.1.1).
H63="$TMP/h63"   # under $TMP so the EXIT trap removes it
mkdir -p "$H63"
h63_rc=0
(
  # Every step explicitly checked: a subshell on the LEFT of `||` runs with errexit
  # suppressed, so `set -e` inside would NOT abort a failing cd/git/init and the
  # assertions could "pass" on collapsed setup (review finding, v5.1.1 r1).
  cd "$H63" || exit 1
  git init -q -b main . >/dev/null 2>&1 || exit 1
  git config user.email t@t || exit 1; git config user.name t || exit 1
  "$PLINTH" init . >/dev/null 2>&1 || exit 1
  echo s > SPEC.md || exit 1; git add -A || exit 1; git commit -qm base >/dev/null || exit 1
  git checkout -qb feat >/dev/null 2>&1 || exit 1
  # Portable digest: path + content for every tracked-or-untracked regular file, plus
  # symlink targets. No GNU-only `-printf` (that silently produced nothing on BSD find
  # and would have made this vacuous). `.git` excluded because git rewrites index
  # metadata for reasons unrelated to plinth.
  digest() {
    { find . -path ./.git -prune -o -type f -print 2>/dev/null | sort | xargs shasum 2>/dev/null
      find . -path ./.git -prune -o -type l -print 2>/dev/null | sort | while read -r l; do
        printf 'link %s -> %s\n' "$l" "$(readlink "$l")"; done
    } | shasum | cut -d" " -f1
  }
  before="$(digest)" || exit 1
  case "$before" in ''|*[!0-9a-f]*) echo "digest empty/invalid — assertion would be vacuous"; exit 1 ;; esac
  for c in harden build plan next checkpoint handoff residual lifecycle-migrate phase; do
    out="$("$PLINTH" "$c" --help 2>&1)" || { echo "$c --help exited nonzero"; exit 1; }
    case "$out" in Usage:*) ;; *) echo "$c --help did not print usage — it RAN the command"; exit 1 ;; esac
    out2="$("$PLINTH" "$c" -h 2>&1)" || { echo "$c -h exited nonzero"; exit 1; }
    case "$out2" in Usage:*) ;; *) echo "$c -h did not print usage"; exit 1 ;; esac
  done
  after="$(digest)" || exit 1
  [ "$before" = "$after" ] || { echo "--help mutated the project tree"; exit 1; }
  # An option VALUE that looks like a help flag must stay a value.
  vout="$("$PLINTH" residual . --note --help 2>&1)" || true
  case "$vout" in Usage:*) echo "an option VALUE (--note --help) was read as a help request"; exit 1 ;; esac
  # bad usage still exits 1 (only an EXPLICIT help request is a success)
  rc=0; "$PLINTH" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 1 ] || { echo "no-args usage should exit 1, got $rc"; exit 1; }
) || h63_rc=$?
[ "$h63_rc" = 0 ] || fail "--help is not side-effect free (upstream #63; rc=$h63_rc)"
pass "--help/-h side-effect free for every phase-changing command (upstream #63)"

echo "canary-lifecycle-build-harden: ALL PASS"
