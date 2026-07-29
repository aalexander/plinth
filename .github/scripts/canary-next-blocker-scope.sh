#!/usr/bin/env bash
# plinth#61: phase-scoped NEEDS-HUMAN blockers for plinth next
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLINTH="${PLINTH:-$ROOT/bin/plinth}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

setup() {
  local d="$1"
  mkdir -p "$d/.plinth/session"
  git -C "$d" init -q 2>/dev/null || true
  git -C "$d" config user.email t@t
  git -C "$d" config user.name t
  echo x > "$d/f"
  git -C "$d" add f && git -C "$d" commit -qm init
  git -C "$d" checkout -qb feat/scope
  echo y >> "$d/f" && git -C "$d" add f && git -C "$d" commit -qm work
  "$PLINTH" init "$d" >/dev/null 2>&1 || true
  "$PLINTH" build "$d" >/dev/null 2>&1 || true
  # Ensure build phase
  mkdir -p "$d/.plinth/session"
  printf '%s\n' '{"phase":"build"}' > "$d/.plinth/session/phase-feat%2Fscope.json"
  cat > "$d/CHECKPOINT.md" <<'EOF'
# Checkpoint
## Next
1. implement the feature work
EOF
}

# 1) BUILD + explicit ship blocker + open Next → work (not human_blocked)
setup "$TMP/a"
mkdir -p "$TMP/a/.plinth"
cat > "$TMP/a/.plinth/NEEDS-HUMAN.md" <<'EOF'
# NH
- [ ] [BLOCKING:ship] Choose one GitHub control for merge (receipt / verify)
- [ ] optional non-blocking note
EOF
set +e
out=$("$PLINTH" next "$TMP/a" 2>&1)
rc=$?
set -e
echo "$out" | grep -q 'status: work' || fail "BUILD+ship blocker should still work: $out"
echo "$out" | grep -qi 'deferred BLOCKING' || fail "expected deferred note: $out"
echo "$out" | grep -qi 'implement the feature' || fail "expected HANDOFF next action: $out"
[ "$rc" -eq 0 ] || fail "exit 0 expected, got $rc"
pass "BUILD continues past BLOCKING:ship with deferred note"

# 1b) Bare titled BLOCKING stays GLOBAL even if text says merge/provenance
setup "$TMP/a2"
mkdir -p "$TMP/a2/.plinth"
cat > "$TMP/a2/.plinth/NEEDS-HUMAN.md" <<'EOF'
# NH
- [ ] **[BLOCKING — unspoofable review provenance] Choose one GitHub control** for merge
EOF
set +e
out=$("$PLINTH" next "$TMP/a2" 2>&1)
rc=$?
set -e
echo "$out" | grep -q human_blocked || fail "bare BLOCKING must stay global: $out"
[ "$rc" -eq 2 ] || fail "exit 2 for bare global, got $rc"
pass "bare [BLOCKING — title] stays global (no heuristic re-scope)"

# 1c) explicit global
setup "$TMP/a3"
mkdir -p "$TMP/a3/.plinth"
printf '%s\n' '# NH' '- [ ] [BLOCKING:global] always stop' > "$TMP/a3/.plinth/NEEDS-HUMAN.md"
set +e
out=$("$PLINTH" next "$TMP/a3" 2>&1)
rc=$?
set -e
echo "$out" | grep -q human_blocked || fail "BLOCKING:global must block: $out"
pass "explicit BLOCKING:global blocks BUILD"

# 1d) BUILD + BLOCKING:harden → deferred
setup "$TMP/a4"
mkdir -p "$TMP/a4/.plinth"
printf '%s\n' '# NH' '- [ ] [BLOCKING:harden] paid review seat credit' > "$TMP/a4/.plinth/NEEDS-HUMAN.md"
set +e
out=$("$PLINTH" next "$TMP/a4" 2>&1)
rc=$?
set -e
echo "$out" | grep -q 'status: work' || fail "BUILD+harden should defer: $out"
echo "$out" | grep -qi 'deferred BLOCKING (harden)' || fail "expected harden deferred: $out"
[ "$rc" -eq 0 ] || fail "exit 0 expected, got $rc"
pass "BUILD continues past BLOCKING:harden"

# 1e) HARDEN + BLOCKING:harden → human_blocked
setup "$TMP/a5"
"$PLINTH" harden "$TMP/a5" >/dev/null 2>&1 || true
mkdir -p "$TMP/a5/.plinth"
printf '%s\n' '# NH' '- [ ] [BLOCKING:harden] paid review seat credit' > "$TMP/a5/.plinth/NEEDS-HUMAN.md"
set +e
out=$("$PLINTH" next "$TMP/a5" 2>&1)
rc=$?
set -e
echo "$out" | grep -q human_blocked || fail "HARDEN+BLOCKING:harden must block: $out"
[ "$rc" -eq 2 ] || fail "exit 2 expected, got $rc"
pass "HARDEN blocked by BLOCKING:harden"

# 2) BUILD + global BLOCKING → human_blocked
setup "$TMP/b"
mkdir -p "$TMP/b/.plinth"
printf '%s\n' '# NH' '- [ ] [BLOCKING] need secret from human' > "$TMP/b/.plinth/NEEDS-HUMAN.md"
set +e
out=$("$PLINTH" next "$TMP/b" 2>&1)
rc=$?
set -e
echo "$out" | grep -q human_blocked || fail "global BLOCKING must block BUILD: $out"
[ "$rc" -eq 2 ] || fail "exit 2 expected, got $rc"
pass "BUILD blocked by global BLOCKING"

# 3) BUILD + [BLOCKING:build] → human_blocked
setup "$TMP/c"
mkdir -p "$TMP/c/.plinth"
printf '%s\n' '# NH' '- [ ] [BLOCKING:build] fill this credential now' > "$TMP/c/.plinth/NEEDS-HUMAN.md"
set +e
out=$("$PLINTH" next "$TMP/c" 2>&1)
rc=$?
set -e
echo "$out" | grep -q human_blocked || fail "BLOCKING:build must block BUILD: $out"
[ "$rc" -eq 2 ] || fail "exit 2 expected, got $rc"
pass "BUILD blocked by BLOCKING:build"

# 4) BUILD + [BLOCKING:ship] → work + deferred
setup "$TMP/d"
mkdir -p "$TMP/d/.plinth"
printf '%s\n' '# NH' '- [ ] [BLOCKING:ship] wire receipt before merge' > "$TMP/d/.plinth/NEEDS-HUMAN.md"
set +e
out=$("$PLINTH" next "$TMP/d" 2>&1)
rc=$?
set -e
echo "$out" | grep -q 'status: work' || fail "BLOCKING:ship must not stop BUILD: $out"
echo "$out" | grep -qi 'deferred BLOCKING (ship)' || fail "expected ship deferred note: $out"
[ "$rc" -eq 0 ] || fail "exit 0 expected, got $rc"
pass "BUILD continues with BLOCKING:ship"

# 5) HARDEN + [BLOCKING:ship] → human_blocked
setup "$TMP/e"
"$PLINTH" harden "$TMP/e" >/dev/null 2>&1 || true
mkdir -p "$TMP/e/.plinth"
printf '%s\n' '# NH' '- [ ] [BLOCKING:ship] wire receipt before merge' > "$TMP/e/.plinth/NEEDS-HUMAN.md"
set +e
out=$("$PLINTH" next "$TMP/e" 2>&1)
rc=$?
set -e
echo "$out" | grep -q human_blocked || fail "HARDEN must fail closed on ship blocker: $out"
[ "$rc" -eq 2 ] || fail "exit 2 expected in harden, got $rc"
pass "HARDEN blocked by BLOCKING:ship"

# Leading marker wins — later [BLOCKING:ship] in prose must not re-scope to ship
setup "$TMP/lead"
mkdir -p "$TMP/lead/.plinth"
cat > "$TMP/lead/.plinth/NEEDS-HUMAN.md" <<'EOF'
# NH
- [ ] [BLOCKING:global] document why [BLOCKING:ship] is insufficient for this gate
EOF
set +e
out=$("$PLINTH" next "$TMP/lead" 2>&1)
rc=$?
set -e
echo "$out" | grep -q human_blocked || fail "leading global must block despite later :ship: $out"
[ "$rc" -eq 2 ] || fail "exit 2 for leading global, got $rc ($out)"
# BUILD + leading ship with later global mention → still deferred (ship)
setup "$TMP/lead2"
mkdir -p "$TMP/lead2/.plinth"
cat > "$TMP/lead2/.plinth/NEEDS-HUMAN.md" <<'EOF'
# NH
- [ ] [BLOCKING:ship] note that [BLOCKING:global] was considered and rejected
EOF
cat > "$TMP/lead2/CHECKPOINT.md" <<'EOF'
# Checkpoint
## Next
1. implement the feature work
EOF
set +e
out=$("$PLINTH" next "$TMP/lead2" 2>&1)
rc=$?
set -e
echo "$out" | grep -q 'status: work' || fail "leading ship must stay deferred in BUILD: $out"
[ "$rc" -eq 0 ] || fail "exit 0 for leading ship in BUILD, got $rc"
pass "leading BLOCKING scope wins over later tags in prose"

echo "canary-next-blocker-scope: ALL PASS"
