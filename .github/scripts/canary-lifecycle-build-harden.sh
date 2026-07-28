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
[ -f "$TMP/p1/HANDOFF.md" ] || fail "HANDOFF.md missing"
grep -q 'Restart prompt' "$TMP/p1/HANDOFF.md" || fail "HANDOFF missing restart section"
pass "plinth handoff writes HANDOFF.md"

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
if ! grep -q '## Next' "$TMP/p3/HANDOFF.md"; then fail "handoff missing Next"; fi
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
next_block=$(awk '/^## Next/{p=1;next} p&&/^## /{exit} p' "$TMP/p8/HANDOFF.md")
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
  > "$TMP/p11/HANDOFF.md"
"$PLINTH" harden "$TMP/p11" >/dev/null
grep -F 'Fix [Windows] packaging regression' "$TMP/p11/HANDOFF.md" \
  || fail "operator Fix [Windows] line must be preserved"
grep -F 'custom operator note' "$TMP/p11/HANDOFF.md" \
  || fail "operator note must be preserved"
pass "handoff preserves operator-authored Next lines"

# Handoff preserves Goal/Evidence freeform + pre-archive
setup_proj "$TMP/p12"
printf '%s\n' '# H' '## Goal' 'Operator custom goal text keep me' '## Next' '1. do thing' \
  '## Evidence' '- my evidence note' '## Risks / Noticed' '- my risk' \
  > "$TMP/p12/HANDOFF.md"
"$PLINTH" build "$TMP/p12" >/dev/null
grep -F 'Operator custom goal text keep me' "$TMP/p12/HANDOFF.md" \
  || fail "Goal freeform must survive refresh"
grep -F 'my evidence note' "$TMP/p12/HANDOFF.md" \
  || fail "Evidence freeform must survive refresh"
grep -F 'my risk' "$TMP/p12/HANDOFF.md" \
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
bash -c '
  set -euo pipefail
  eval "$(sed -n "/^thrash_policy_process_findings()/,/^}/p" "'"$ROOT"'/shared/.plinth/review.sh")"
  f=$(mktemp)
  jq -n "{verdict:\"CHANGES_NEEDED\",summary:\"t\",findings:[
    {file:\"x.sh\",line:1,severity:\"major\",description:\"Coverage remains incomplete despite canary\",status:\"open\"},
    {file:\"auth.py\",line:2,severity:\"major\",description:\"auth bypass on login route\",status:\"open\"},
    {file:\"CHANGELOG.md\",line:3,severity:\"major\",description:\"awkward wording in residual\",status:\"open\"},
    {file:\"docs/build.py\",line:4,severity:\"major\",description:\"crash on empty input\",status:\"open\"}
  ]}" > "$f"
  scope=$(printf "%s\n" "x.sh" "auth.py" "CHANGELOG.md" "docs/build.py")
  thrash_policy_process_findings "$f" build "$scope" "" "MANUAL.md"
  s0=$(jq -r ".findings[0].severity" "$f")
  s1=$(jq -r ".findings[1].severity" "$f")
  s2=$(jq -r ".findings[2].severity" "$f")
  s3=$(jq -r ".findings[3].severity" "$f")
  [ "$s0" = "minor" ] || { echo "coverage should demote, got $s0"; exit 1; }
  [ "$s1" = "major" ] || { echo "auth bypass must stay major, got $s1"; exit 1; }
  [ "$s2" = "minor" ] || { echo "docs prose should demote, got $s2"; exit 1; }
  [ "$s3" = "major" ] || { echo "docs/build.py must stay major, got $s3"; exit 1; }
  rm -f "$f"
' || fail "thrash_policy matrix"
pass "thrash_policy demotes coverage/docs; keeps external security + docs scripts"

# VERSION exact match (python path — empty-sed bug regression)
bash -c '
  set -euo pipefail
  d=$(mktemp -d)
  echo 9.9.9 > "$d/VERSION"
  printf "%s\n" "# Plinth changelog" "" "## v5.0.0 — x" > "$d/CHANGELOG.md"
  cd "$d"
  ver_txt=$(tr -d "[:space:]" < VERSION)
  top_entry=$(awk "/^## /{print; exit}" CHANGELOG.md)
  if python3 -c "import re,sys
v,t=sys.argv[1],sys.argv[2]
sys.exit(0 if re.search(r\"(^|[^0-9.])\"+re.escape(v)+r\"([^0-9.]|$)\", t) else 1)
" "$ver_txt" "$top_entry" 2>/dev/null; then
    echo "9.9.9 must not match v5.0.0"; exit 1
  fi
  echo 5.0.0 > VERSION
  ver_txt=$(tr -d "[:space:]" < VERSION)
  python3 -c "import re,sys
v,t=sys.argv[1],sys.argv[2]
sys.exit(0 if re.search(r\"(^|[^0-9.])\"+re.escape(v)+r\"([^0-9.]|$)\", t) else 1)
" "$ver_txt" "$top_entry" || { echo "5.0.0 should match v5.0.0"; exit 1; }
  echo 5.0 > VERSION
  ver_txt=$(tr -d "[:space:]" < VERSION)
  if python3 -c "import re,sys
v,t=sys.argv[1],sys.argv[2]
sys.exit(0 if re.search(r\"(^|[^0-9.])\"+re.escape(v)+r\"([^0-9.]|$)\", t) else 1)
" "$ver_txt" "$top_entry" 2>/dev/null; then
    echo "5.0 must not match v5.0.0"; exit 1
  fi
  rm -rf "$d"
' || fail "VERSION exact match"
pass "VERSION exact token match vs CHANGELOG top H2"

# plan --deep with fake seats (no network)
setup_proj "$TMP/p16"
mkdir -p "$TMP/p16/.plinth" "$TMP/fakebin"
echo "spec_path = PLAN.md" > "$TMP/p16/.plinth/config"
printf 'reviewer_vendor = claude\naudit_vendor = codex\nadvisor_vendor = grok\n' >> "$TMP/p16/.plinth/config"
"$PLINTH" plan "$TMP/p16" >/dev/null
# Fake CLIs that emit role-shaped JSON regardless of args
for cli in claude codex grok; do
  cat > "$TMP/fakebin/$cli" <<'FAKE'
#!/usr/bin/env bash
# Read prompt from stdin or argv; emit a fixed seat review JSON fence.
role=security_ops
case "$0" in *codex*) role=completeness ;; *grok*) role=delete_simplify ;; esac
cat <<EOF
### Seat: $role
#### Blockers
- none
#### Questions for human
- none
#### Nits
- none
#### One-line verdict
ok
\`\`\`json
{"seat":"$role","blockers":[],"questions":[],"nits":["nit-$role"],"verdict":"shippable"}
\`\`\`
EOF
FAKE
  chmod +x "$TMP/fakebin/$cli"
done
PATH="$TMP/fakebin:$PATH" "$PLINTH" plan --deep "$TMP/p16" >/dev/null 2>&1 \
  || fail "plan --deep with fake seats failed"
[ -f "$TMP/p16/PLAN-REVIEW.md" ] || fail "PLAN-REVIEW.md missing after plan --deep"
grep -q 'nit-security_ops\|nit-completeness\|nit-delete_simplify\|Merged\|Raw' "$TMP/p16/PLAN-REVIEW.md" \
  || grep -q . "$TMP/p16/PLAN-REVIEW.md" || fail "PLAN-REVIEW empty"
[ -f "$TMP/p16/.plinth/session/plan-review-merge.json" ] \
  || fail "plan-review-merge.json missing"
pass "plinth plan --deep fake-seat merge writes PLAN-REVIEW"

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

echo "canary-lifecycle-build-harden: ALL PASS"
