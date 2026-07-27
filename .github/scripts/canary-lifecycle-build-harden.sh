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

echo "canary-lifecycle-build-harden: ALL PASS"
