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

# 1) BUILD + ship-only blocker + open Next → work (not human_blocked)
setup "$TMP/a"
mkdir -p "$TMP/a/.plinth"
cat > "$TMP/a/.plinth/NEEDS-HUMAN.md" <<'EOF'
# NH
- [ ] **[BLOCKING — unspoofable review provenance] Choose one GitHub control** for merge
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
pass "BUILD continues past ship-only BLOCKING with deferred note"

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

echo "canary-next-blocker-scope: ALL PASS"
