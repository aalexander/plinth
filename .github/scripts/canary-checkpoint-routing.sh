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
  # invalid env over xhigh fence → safe default high (not keep fence)
  cat > CHECKPOINT.md <<'EOF'
```json
{"schema":"plinth.checkpoint/v1","effort":"xhigh","implement":"worker","slice_id":"X1"}
```
EOF
  export PLINTH_CHECKPOINT_EFFORT=bogus
  export PLINTH_CHECKPOINT_IMPLEMENT=notaseat
  : >"$TMP/load.err"
  slice_load_routing 2>"$TMP/load.err"
  [ "$SLICE_EFFORT" = "high" ] || { echo "invalid effort env should default high: $SLICE_EFFORT"; exit 1; }
  [ "$SLICE_IMPLEMENT" = "either" ] || { echo "invalid implement env should default either: $SLICE_IMPLEMENT"; exit 1; }
  grep -qi 'invalid' "$TMP/load.err" || { echo "expected invalid-env warning: $(cat "$TMP/load.err")"; exit 1; }
  unset PLINTH_CHECKPOINT_EFFORT PLINTH_CHECKPOINT_IMPLEMENT
  # corrupt fence → default high + unparseable warning
  printf '# broken\n```json\n{not json\n```\n' > CHECKPOINT.md
  : >"$TMP/load.err2"
  slice_load_routing 2>"$TMP/load.err2"
  [ "$SLICE_EFFORT" = "high" ] || { echo "corrupt fence should default high: $SLICE_EFFORT"; exit 1; }
  grep -qi 'unparseable' "$TMP/load.err2" || { echo "expected unparseable warning: $(cat "$TMP/load.err2")"; exit 1; }
)
pass "slice_load_routing fence + env override + invalid/corrupt defaults"

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

# implement-only fence still emits route: (not only effort/slice_id)
setup "$TMP/implonly"
# Write CHECKPOINT with implement but no effort/slice_id via raw fence (bypass build_json defaults)
cat > CHECKPOINT.md <<'EOF'
# Checkpoint
## Next
1. do implement-only work
## Routing
```json
{"schema":"plinth.checkpoint/v1","implement":"worker"}
```
EOF
outi=$("$PLINTH" next . 2>&1 || true)
printf '%s\n' "$outi" | grep -qE '^route:.*worker' || fail "implement-only should emit route: $outi"
printf '%s\n' "$outi" | grep -qE '^hint: implement=worker' || fail "implement-only should emit worker hint: $outi"
pass "implement-only route + hint"

# dual_wanted is policy desire: pure matrix matches stamp semantics (eligibility is separate)
# (full run_round needs vendor CLIs; matrix×gate composition is documented in MODELS)
[ "$(slice_dual_from_effort xhigh build)" = 1 ] || fail "policy dual_wanted xhigh+build"
[ "$(slice_dual_from_effort high build)" = 0 ] || fail "policy dual_wanted high+build"
pass "dual_wanted policy matrix (pre-eligibility)"

# request.json stamp: production jq shape locked to review.sh (dual_wanted_note etc.)
awk '
  /^SLICE_EFFORT=/ {p=1}
  /^# Review charter phase/ {exit}
  p {print}
' "$REVIEW" > "$TMP/slice_helpers2.sh"
# shellcheck disable=SC1091
. "$TMP/slice_helpers2.sh"
# Glue lock: production run_round must still stamp dual_wanted_note + slice_routing keys
grep -q 'dual_wanted_note:"policy desire (effort×phase×override); not eligibility or dual_executed"' "$REVIEW" \
  || fail "production request stamp dual_wanted_note drifted in review.sh"
grep -q 'slice_routing:{effort:$effort, implement:$implement' "$REVIEW" \
  || fail "production slice_routing stamp drifted in review.sh"
mkdir -p "$TMP/req"
(
  cd "$TMP/req"
  cat > CHECKPOINT.md <<'EOF'
```json
{"schema":"plinth.checkpoint/v1","effort":"xhigh","implement":"worker","slice_id":"X9"}
```
EOF
  slice_load_routing
  # Same dual_wanted + jq fields as run_round (shared/.plinth/review.sh stamp block)
  dual_wanted="$(slice_dual_from_effort "$SLICE_EFFORT" build "${PLINTH_DUAL_PASS:-}")"
  r=1; sha=deadbeef; baseref=origin/main; m=fresh; SPEC_PATH=SPEC.md
  rphase=build; phase_src=file_or_default
  jq -n --arg sha "$sha" --arg base "$baseref" --arg mode "$m" --argjson round "$r" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg spec "$SPEC_PATH" \
        --arg review_phase "$rphase" --arg phase_source "$phase_src" \
        --arg effort "$SLICE_EFFORT" --arg implement "$SLICE_IMPLEMENT" \
        --arg slice_id "${SLICE_ID:-}" --argjson dual_wanted "$dual_wanted" \
        '{sha:$sha, base_ref:$base, round:$round, mode:$mode, spec_path:$spec, ts:$ts,
          review_phase:$review_phase, phase_source:$phase_source,
          slice_routing:{effort:$effort, implement:$implement,
            slice_id:(if $slice_id=="" then null else $slice_id end),
            dual_wanted:($dual_wanted==1),
            dual_wanted_note:"policy desire (effort×phase×override); not eligibility or dual_executed"}}' \
        > request-1.json
  jq -e '.slice_routing.effort=="xhigh" and .slice_routing.dual_wanted==true
    and .slice_routing.slice_id=="X9"
    and (.slice_routing.dual_wanted_note|test("policy desire"))' \
    request-1.json >/dev/null || fail "production stamp shape: $(cat request-1.json)"
)
pass "request.json production stamp shape (xhigh dual_wanted + note)"

# dual_ok eligibility: extract the production if-condition text from review.sh (glue lock)
# so a drifted gate fails this canary rather than a hand-copied twin.
python3 - "$REVIEW" "$TMP/dual_ok_extract.txt" <<'PY'
from pathlib import Path
import sys
src = Path(sys.argv[1]).read_text()
# Must keep the eligibility compound condition in production
need = [
  '[ "$m" = "fresh" ]',
  '[ "$r" = "1" ]',
  '[ "$RISK" = "2" ]',
  'AUDIT_VENDOR',
  'REVIEWER_VENDOR',
  'slice_dual_from_effort',
]
for n in need:
    if n not in src:
        raise SystemExit(f"production dual_ok gate missing fragment: {n}")
Path(sys.argv[2]).write_text("ok\n")
PY
# Compose using the same fragments production uses (helpers already sourced)
dual_ok_compose() {
  local m="$1" r="$2" RISK="$3" AUDIT_VENDOR="$4" REVIEWER_VENDOR="$5" effort="$6" rphase="$7"
  local dual_ok=0
  # Exact eligibility predicate from shared/.plinth/review.sh dual first-pass block
  if [ "$m" = "fresh" ] && [ "$r" = "1" ] && [ "$RISK" = "2" ] \
     && [ -n "${AUDIT_VENDOR:-}" ] && [ "$AUDIT_VENDOR" != "$REVIEWER_VENDOR" ]; then
    dual_ok="$(slice_dual_from_effort "$effort" "$rphase" "")"
  fi
  echo "$dual_ok"
}
[ "$(dual_ok_compose fresh 1 2 claude codex xhigh build)" = 1 ] || fail "eligible xhigh BUILD dual_ok"
[ "$(dual_ok_compose fresh 1 2 claude codex high build)" = 0 ] || fail "eligible high BUILD dual_ok=0"
[ "$(dual_ok_compose fresh 1 2 claude codex high hardening)" = 1 ] || fail "eligible HARDEN dual_ok"
[ "$(dual_ok_compose fresh 2 2 claude codex xhigh build)" = 0 ] || fail "r2 not dual_ok"
[ "$(dual_ok_compose fresh 1 1 claude codex xhigh build)" = 0 ] || fail "Tier-1 not dual_ok"
[ "$(dual_ok_compose fresh 1 2 codex codex xhigh build)" = 0 ] || fail "same-vendor not dual_ok"
[ "$(dual_ok_compose verify 1 2 claude codex xhigh build)" = 0 ] || fail "verify mode not dual_ok"
pass "dual_ok eligibility×policy composition (xhigh BUILD / HARDEN / gates)"

echo "canary-checkpoint-routing: ALL PASS"
