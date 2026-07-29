#!/usr/bin/env bash
# Checkpoint + slice routing + effort/seat live wiring canary (v5.0.8)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLINTH="${PLINTH:-$ROOT/bin/plinth}"
REVIEW="$ROOT/shared/.plinth/review.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

setup() {
  local d="$1"
  mkdir -p "$d" && cd "$d"
  git init -q
  git config user.email t@t
  git config user.name t
  echo x > f && git add f && git commit -qm i
  git checkout -qb feat/cp
  "$PLINTH" init . >/dev/null 2>&1 || true
}

# ── dual matrix (pure function from product review.sh) ─────────────────────
# Extract slice_dual_from_effort without sourcing the whole review entrypoint.
awk '
  /^slice_dual_from_effort\(\)/ {p=1}
  p {print}
  p && /^}/ {exit}
' "$REVIEW" > "$TMP/dual_fn.sh"
# shellcheck disable=SC1090
. "$TMP/dual_fn.sh"
type slice_dual_from_effort >/dev/null 2>&1 || fail "slice_dual_from_effort not extractable"
# HARDEN always dual (effort never weakens)
[ "$(slice_dual_from_effort medium hardening)" = 1 ] || fail "medium+harden should dual"
[ "$(slice_dual_from_effort high hardening)" = 1 ] || fail "high+harden should dual"
[ "$(slice_dual_from_effort xhigh hardening)" = 1 ] || fail "xhigh+harden should dual"
# BUILD: only xhigh
[ "$(slice_dual_from_effort medium build)" = 0 ] || fail "medium+build should skip dual"
[ "$(slice_dual_from_effort high build)" = 0 ] || fail "high+build should skip dual (default posture)"
[ "$(slice_dual_from_effort xhigh build)" = 1 ] || fail "xhigh+build should dual"
# overrides
[ "$(slice_dual_from_effort medium build 1)" = 1 ] || fail "PLINTH_DUAL_PASS=1 forces on"
[ "$(slice_dual_from_effort xhigh build 0)" = 0 ] || fail "PLINTH_DUAL_PASS=0 forces off"
[ "$(slice_dual_from_effort high hardening 0)" = 0 ] || fail "override 0 wins over harden"
# default effort arg
[ "$(slice_dual_from_effort "" build)" = 0 ] || fail "empty effort defaults high → no build dual"
pass "slice_dual_from_effort matrix (HARDEN always; BUILD only xhigh; overrides)"

# ── checkpoint write / preserve / next route+implement hint ────────────────
setup "$TMP/a"
PLINTH_CHECKPOINT_SLICE_ID=R2 PLINTH_CHECKPOINT_SLICE_INDEX=2 PLINTH_CHECKPOINT_SLICE_TOTAL=5 \
PLINTH_CHECKPOINT_EFFORT=medium PLINTH_CHECKPOINT_IMPLEMENT=driver \
PLINTH_CHECKPOINT_EFFORT_RATIONALE='judgment-shaped' \
  "$PLINTH" checkpoint . >/dev/null
[ -f CHECKPOINT.md ] || fail "CHECKPOINT.md missing"
[ -f HANDOFF.md ] || fail "HANDOFF pointer missing"
grep -q 'plinth.checkpoint/v1' CHECKPOINT.md || fail "schema missing"
grep -q '"effort": "medium"' CHECKPOINT.md || fail "effort not medium"
grep -q '"implement": "driver"' CHECKPOINT.md || fail "implement not driver"
grep -q 'Canonical restart state' HANDOFF.md || fail "HANDOFF not pointer"
# invalid JSON fail-soft: keep prior fields
printf '\n```json\n{broken\n```\n' >> CHECKPOINT.md
"$PLINTH" checkpoint . >/dev/null
grep -q '"slice_id": "R2"' CHECKPOINT.md || fail "did not preserve slice_id after corrupt fence"
# next route + implement=driver hint (non-blocking)
out=$("$PLINTH" next . 2>&1 || true)
printf '%s\n' "$out" | grep -qE '^route:' || fail "next missing route: $out"
printf '%s\n' "$out" | grep -qE '^hint: implement=driver' || fail "next missing driver hint: $out"
printf '%s\n' "$out" | grep -qE '^status:' || fail "next missing status: $out"
pass "checkpoint write/preserve + next route/driver hint"

# implement=worker hint
setup "$TMP/w"
PLINTH_CHECKPOINT_SLICE_ID=W1 PLINTH_CHECKPOINT_EFFORT=high PLINTH_CHECKPOINT_IMPLEMENT=worker \
  "$PLINTH" checkpoint . >/dev/null
outw=$("$PLINTH" next . 2>&1 || true)
printf '%s\n' "$outw" | grep -qE '^hint: implement=worker' || fail "next missing worker hint: $outw"
# either → no implement hint
setup "$TMP/e"
PLINTH_CHECKPOINT_SLICE_ID=E1 PLINTH_CHECKPOINT_EFFORT=high PLINTH_CHECKPOINT_IMPLEMENT=either \
  "$PLINTH" checkpoint . >/dev/null
oute=$("$PLINTH" next . 2>&1 || true)
printf '%s\n' "$oute" | grep -qE '^hint: implement=' && fail "either should not emit implement hint: $oute" || true
printf '%s\n' "$oute" | grep -qE '^route:' || fail "either still routes: $oute"
pass "implement worker/either hint policy"

# ── review.sh slice_load_routing via fence + env (no full review dispatch) ──
awk '
  /^SLICE_EFFORT=/ {p=1}
  /^# Review charter phase/ {exit}
  p {print}
' "$REVIEW" > "$TMP/slice_helpers.sh"
mkdir -p "$TMP/load"
(
  set -euo pipefail
  cd "$TMP/load"
  cat > CHECKPOINT.md <<'EOF'
```json
{"schema":"plinth.checkpoint/v1","effort":"xhigh","implement":"worker","slice_id":"X1"}
```
EOF
  # shellcheck disable=SC1091
  . "$TMP/slice_helpers.sh"
  slice_load_routing
  [ "$SLICE_EFFORT" = "xhigh" ] || { echo "effort=$SLICE_EFFORT"; exit 1; }
  [ "$SLICE_IMPLEMENT" = "worker" ] || { echo "impl=$SLICE_IMPLEMENT"; exit 1; }
  [ "$SLICE_ID" = "X1" ] || { echo "id=$SLICE_ID"; exit 1; }
  [ "$(slice_dual_from_effort "$SLICE_EFFORT" build)" = 1 ] || exit 1
  # env override beats fence
  export PLINTH_CHECKPOINT_EFFORT=medium
  slice_load_routing
  [ "$SLICE_EFFORT" = "medium" ] || { echo "env override failed: $SLICE_EFFORT"; exit 1; }
)
pass "slice_load_routing fence + env override"

# legacy HANDOFF-only read path
setup "$TMP/b"
cat > HANDOFF.md <<'EOF'
# Handoff
## Next
1. do the thing
EOF
out2=$("$PLINTH" next . 2>&1 || true)
printf '%s\n' "$out2" | grep -q 'do the thing' || fail "HANDOFF-only fallback next: $out2"
pass "HANDOFF-only fallback next"

# missing effort never fails next
setup "$TMP/c"
# checkpoint without effort field in body (empty fence)
cat > CHECKPOINT.md <<'EOF'
# Checkpoint
## Next
1. keep going
EOF
set +e
out3=$("$PLINTH" next . 2>&1)
rc3=$?
set -e
# exit 0 (work) or 3 (done) — never 1 crash
[ "$rc3" -eq 0 ] || [ "$rc3" -eq 3 ] || fail "missing effort must not crash next (rc=$rc3): $out3"
printf '%s\n' "$out3" | grep -qE '^status:' || fail "missing effort still status: $out3"
pass "missing effort never fails next"

echo "canary-checkpoint-routing: ALL PASS"
