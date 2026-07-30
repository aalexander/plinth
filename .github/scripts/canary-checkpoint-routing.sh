#!/usr/bin/env bash
# Checkpoint + slice routing + rigor/seat live wiring canary (v5.1.0)
#
# v5.1 renamed the slice knob `effort: medium|high|xhigh` → `rigor: standard|deep`
# and made dual OFF by default in EVERY phase (HARDEN no longer forces it). This
# canary is the regression lock for both: the matrix, the deprecated-alias read
# path, the two independent alias implementations agreeing, and the new
# fail-closed path when a REQUESTED dual has no cross-vendor seat.
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
# Extract slice_dual_from_rigor without sourcing the whole review entrypoint.
awk '
  /^slice_dual_from_rigor\(\)/ {p=1}
  p {print}
  p && /^}/ {exit}
' "$REVIEW" > "$TMP/dual_fn.sh"
# shellcheck disable=SC1090
. "$TMP/dual_fn.sh"
type slice_dual_from_rigor >/dev/null 2>&1 || fail "slice_dual_from_rigor not extractable"
# THE v5.1 BEHAVIOR CHANGE: HARDEN no longer forces dual. Phase alone is not
# evidence that a second generalist opinion is worth a paid round — a regression
# here silently restores dual-as-habit on every ship.
[ "$(slice_dual_from_rigor standard hardening)" = 0 ] || fail "HARDEN must NOT force dual in v5.1 (ship-bias: dual is optional rigor)"
[ "$(slice_dual_from_rigor standard build)" = 0 ] || fail "standard+build should skip dual"
# deep is the only rigor that wants dual, in either phase
[ "$(slice_dual_from_rigor deep build)" = 1 ] || fail "deep+build should dual"
[ "$(slice_dual_from_rigor deep hardening)" = 1 ] || fail "deep+harden should dual"
# overrides win over rigor, in both directions
[ "$(slice_dual_from_rigor standard build 1)" = 1 ] || fail "PLINTH_DUAL_PASS=1 forces on"
[ "$(slice_dual_from_rigor deep build 0)" = 0 ] || fail "PLINTH_DUAL_PASS=0 forces off"
[ "$(slice_dual_from_rigor deep hardening 0)" = 0 ] || fail "override 0 wins over deep+harden"
# default rigor arg → standard → no dual
[ "$(slice_dual_from_rigor "" build)" = 0 ] || fail "empty rigor defaults standard → no dual"
[ "$(slice_dual_from_rigor "" hardening)" = 0 ] || fail "empty rigor + harden still no dual"
# an unknown token is never treated as deep (fail toward the cheap default, loudly elsewhere)
[ "$(slice_dual_from_rigor bogus hardening)" = 0 ] || fail "unknown rigor must not dual"
pass "slice_dual_from_rigor matrix (dual OFF default incl. HARDEN; deep/override only)"

# ── deprecated `effort` vocabulary is READ as an alias, exactly once warned ──
awk '
  /^slice_rigor_normalize\(\)/ {p=1}
  /^# Stamp request-N.json/ {exit}
  p {print}
' "$REVIEW" > "$TMP/norm_fn.sh"
# shellcheck disable=SC1090
. "$TMP/norm_fn.sh"
type slice_rigor_normalize >/dev/null 2>&1 || fail "slice_rigor_normalize not extractable"
# normalize is PURE: token in, token out, and NOTHING on stderr. The warning is
# the caller's job precisely because normalize is invoked through `$(...)`.
[ "$(slice_rigor_normalize standard)" = standard ] || fail "normalize standard"
[ "$(slice_rigor_normalize deep)" = deep ] || fail "normalize deep"
[ "$(slice_rigor_normalize xhigh)" = deep ] || fail "legacy xhigh → deep"
[ "$(slice_rigor_normalize high)" = standard ] || fail "legacy high → standard"
[ "$(slice_rigor_normalize medium)" = standard ] || fail "legacy medium → standard"
[ -z "$(slice_rigor_normalize bogus)" ] || fail "unknown token must normalize to empty"
[ -z "$(slice_rigor_normalize "")" ] || fail "empty token must normalize to empty"
: >"$TMP/pure.err"
slice_rigor_normalize xhigh >/dev/null 2>"$TMP/pure.err"
[ ! -s "$TMP/pure.err" ] || fail "slice_rigor_normalize must be pure (no stderr): $(cat "$TMP/pure.err")"
slice_rigor_is_legacy xhigh || fail "xhigh is legacy vocabulary"
slice_rigor_is_legacy deep && fail "deep is not legacy vocabulary" || true
pass "slice_rigor_normalize is pure + maps the deprecated vocabulary"

# ── checkpoint write / preserve / next route+implement hint ────────────────
setup "$TMP/a"
PLINTH_CHECKPOINT_SLICE_ID=R2 PLINTH_CHECKPOINT_SLICE_INDEX=2 PLINTH_CHECKPOINT_SLICE_TOTAL=5 \
PLINTH_CHECKPOINT_RIGOR=deep PLINTH_CHECKPOINT_IMPLEMENT=driver \
PLINTH_CHECKPOINT_RIGOR_RATIONALE='judgment-shaped' \
  "$PLINTH" checkpoint . >/dev/null
[ -f CHECKPOINT.md ] || fail "CHECKPOINT.md missing"
[ -f HANDOFF.md ] || fail "HANDOFF pointer missing"
grep -q 'plinth.checkpoint/v1' CHECKPOINT.md || fail "schema missing"
grep -q '"rigor": "deep"' CHECKPOINT.md || fail "rigor not deep"
grep -q '"rigor_rationale": "judgment-shaped"' CHECKPOINT.md || fail "rigor_rationale not written"
grep -q '"implement": "driver"' CHECKPOINT.md || fail "implement not driver"
# The writer must NOT re-emit the deprecated key — a refreshed checkpoint migrates itself.
grep -q '"effort"' CHECKPOINT.md && fail "writer must not emit the deprecated effort key" || true
grep -q 'Canonical restart state' HANDOFF.md || fail "HANDOFF not pointer"
# invalid JSON fail-soft: keep prior fields
printf '\n```json\n{broken\n```\n' >> CHECKPOINT.md
"$PLINTH" checkpoint . >/dev/null
grep -q '"slice_id": "R2"' CHECKPOINT.md || fail "did not preserve slice_id after corrupt fence"
# next route + implement=driver hint (non-blocking)
out=$("$PLINTH" next . 2>&1 || true)
printf '%s\n' "$out" | grep -qE '^route:' || fail "next missing route: $out"
printf '%s\n' "$out" | grep -qE '^route:.*deep' || fail "next route must surface rigor: $out"
printf '%s\n' "$out" | grep -qE '^hint: implement=driver' || fail "next missing driver hint: $out"
printf '%s\n' "$out" | grep -qE '^status:' || fail "next missing status: $out"
pass "checkpoint write/preserve + next route/driver hint (rigor surfaced)"

# ── legacy `effort` fence MIGRATES through the writer (deprecation window) ──
# A downstream repo whose CHECKPOINT.md predates v5.1 must keep routing, and one
# `plinth checkpoint` must rewrite it onto the new key rather than stranding it.
setup "$TMP/legacy"
cat > CHECKPOINT.md <<'EOF'
# Checkpoint
## Next
1. legacy fence
## Routing
```json
{"schema":"plinth.checkpoint/v1","effort":"xhigh","implement":"worker","slice_id":"L1","effort_rationale":"legacy reason"}
```
EOF
outl=$("$PLINTH" next . 2>&1 || true)
printf '%s\n' "$outl" | grep -qE '^route:.*deep' || fail "legacy effort=xhigh must read as rigor=deep: $outl"
printf '%s\n' "$outl" | grep -qE '^route:.*legacy reason' || fail "legacy effort_rationale must still surface: $outl"
"$PLINTH" checkpoint . >/dev/null
grep -q '"rigor": "deep"' CHECKPOINT.md || fail "legacy effort=xhigh must migrate to rigor=deep: $(cat CHECKPOINT.md)"
grep -q '"rigor_rationale": "legacy reason"' CHECKPOINT.md || fail "legacy rationale must migrate"
grep -q '"effort"' CHECKPOINT.md && fail "migration must drop the deprecated key" || true
pass "legacy effort fence reads + migrates to rigor (bin/plinth alias impl)"

# ── the two alias implementations must agree on every token ─────────────────
# review.sh slice_rigor_normalize (shell) is the canonical rule; bin/plinth
# _rigor (python, inside _checkpoint_parse_json) is a second implementation. A
# silent divergence would route the dash and the review loop differently for the
# same fence — so drive bin/plinth end-to-end per token and compare.
for tok in standard deep xhigh high medium; do
  expect="$(slice_rigor_normalize "$tok" 2>/dev/null)"
  setup "$TMP/agree-$tok"
  cat > CHECKPOINT.md <<EOF
# Checkpoint
## Next
1. agree
## Routing
\`\`\`json
{"schema":"plinth.checkpoint/v1","rigor":"$tok","slice_id":"A1"}
\`\`\`
EOF
  "$PLINTH" checkpoint . >/dev/null
  grep -q "\"rigor\": \"$expect\"" CHECKPOINT.md \
    || fail "alias impls disagree for '$tok': review.sh says '$expect', bin/plinth wrote $(grep '"rigor"' CHECKPOINT.md)"
done
pass "review.sh and bin/plinth alias implementations agree on every token"

# implement=worker hint
setup "$TMP/w"
PLINTH_CHECKPOINT_SLICE_ID=W1 PLINTH_CHECKPOINT_RIGOR=standard PLINTH_CHECKPOINT_IMPLEMENT=worker \
  "$PLINTH" checkpoint . >/dev/null
outw=$("$PLINTH" next . 2>&1 || true)
printf '%s\n' "$outw" | grep -qE '^hint: implement=worker' || fail "next missing worker hint: $outw"
# either → no implement hint
setup "$TMP/e"
PLINTH_CHECKPOINT_SLICE_ID=E1 PLINTH_CHECKPOINT_RIGOR=standard PLINTH_CHECKPOINT_IMPLEMENT=either \
  "$PLINTH" checkpoint . >/dev/null
oute=$("$PLINTH" next . 2>&1 || true)
printf '%s\n' "$oute" | grep -qE '^hint: implement=' && fail "either should not emit implement hint: $oute" || true
printf '%s\n' "$oute" | grep -qE '^route:' || fail "either still routes: $oute"
pass "implement worker/either hint policy"

# ── review.sh slice_load_routing via fence + env (no full review dispatch) ──
awk '
  /^SLICE_RIGOR=/ {p=1}
  /^# Review charter phase/ {exit}
  p {print}
' "$REVIEW" > "$TMP/slice_helpers.sh"
mkdir -p "$TMP/load"
(
  set -euo pipefail
  cd "$TMP/load"
  cat > CHECKPOINT.md <<'EOF'
```json
{"schema":"plinth.checkpoint/v1","rigor":"deep","implement":"worker","slice_id":"X1"}
```
EOF
  # shellcheck disable=SC1091
  . "$TMP/slice_helpers.sh"
  slice_load_routing
  [ "$SLICE_RIGOR" = "deep" ] || { echo "rigor=$SLICE_RIGOR"; exit 1; }
  [ "$SLICE_IMPLEMENT" = "worker" ] || { echo "impl=$SLICE_IMPLEMENT"; exit 1; }
  [ "$SLICE_ID" = "X1" ] || { echo "id=$SLICE_ID"; exit 1; }
  [ "$(slice_dual_from_rigor "$SLICE_RIGOR" build)" = 1 ] || exit 1
  # legacy fence key still loads (deprecation window) and maps to deep
  cat > CHECKPOINT.md <<'EOF'
```json
{"schema":"plinth.checkpoint/v1","effort":"xhigh","implement":"worker","slice_id":"X1"}
```
EOF
  : >"$TMP/legacy.err"
  slice_load_routing 2>"$TMP/legacy.err"
  [ "$SLICE_RIGOR" = "deep" ] || { echo "legacy fence effort=xhigh should load deep: $SLICE_RIGOR"; exit 1; }
  grep -qi 'deprecated' "$TMP/legacy.err" || { echo "legacy fence should warn: $(cat "$TMP/legacy.err")"; exit 1; }
  grep -q 'rigor' "$TMP/legacy.err" || { echo "deprecation warning must name the new knob"; exit 1; }
  # ONCE PER PROCESS, measured on the PRODUCTION path. The guard lives in the
  # current shell precisely because normalize runs in a command substitution —
  # testing the helper directly would pass while every round spammed the log.
  : >"$TMP/legacy2.err"
  slice_load_routing 2>"$TMP/legacy2.err"
  grep -qi 'deprecated' "$TMP/legacy2.err" \
    && { echo "deprecation note must be once per process, not per round: $(cat "$TMP/legacy2.err")"; exit 1; } || true
  # env override beats fence; the NEW env name works
  export PLINTH_CHECKPOINT_RIGOR=standard
  slice_load_routing
  [ "$SLICE_RIGOR" = "standard" ] || { echo "env override failed: $SLICE_RIGOR"; exit 1; }
  # the new env name wins over the deprecated one when both are set
  export PLINTH_CHECKPOINT_EFFORT=xhigh
  slice_load_routing
  [ "$SLICE_RIGOR" = "standard" ] || { echo "PLINTH_CHECKPOINT_RIGOR must win over PLINTH_CHECKPOINT_EFFORT: $SLICE_RIGOR"; exit 1; }
  unset PLINTH_CHECKPOINT_RIGOR
  # deprecated env name still applies when the new one is unset
  slice_load_routing
  [ "$SLICE_RIGOR" = "deep" ] || { echo "deprecated env should still apply alone: $SLICE_RIGOR"; exit 1; }
  unset PLINTH_CHECKPOINT_EFFORT
  # invalid env over deep fence → safe default standard (not keep fence)
  cat > CHECKPOINT.md <<'EOF'
```json
{"schema":"plinth.checkpoint/v1","rigor":"deep","implement":"worker","slice_id":"X1"}
```
EOF
  export PLINTH_CHECKPOINT_RIGOR=bogus
  export PLINTH_CHECKPOINT_IMPLEMENT=notaseat
  : >"$TMP/load.err"
  slice_load_routing 2>"$TMP/load.err"
  [ "$SLICE_RIGOR" = "standard" ] || { echo "invalid rigor env should default standard: $SLICE_RIGOR"; exit 1; }
  [ "$SLICE_IMPLEMENT" = "either" ] || { echo "invalid implement env should default either: $SLICE_IMPLEMENT"; exit 1; }
  grep -qi 'invalid' "$TMP/load.err" || { echo "expected invalid-env warning: $(cat "$TMP/load.err")"; exit 1; }
  unset PLINTH_CHECKPOINT_RIGOR PLINTH_CHECKPOINT_IMPLEMENT
  # unrecognized fence value → default standard + warning (never silently deep)
  cat > CHECKPOINT.md <<'EOF'
```json
{"schema":"plinth.checkpoint/v1","rigor":"banana","slice_id":"X1"}
```
EOF
  : >"$TMP/load.err3"
  slice_load_routing 2>"$TMP/load.err3"
  [ "$SLICE_RIGOR" = "standard" ] || { echo "unrecognized fence rigor should default standard: $SLICE_RIGOR"; exit 1; }
  grep -qi 'unrecognized' "$TMP/load.err3" || { echo "expected unrecognized-fence warning: $(cat "$TMP/load.err3")"; exit 1; }
  # corrupt fence → default standard + unparseable warning
  printf '# broken\n```json\n{not json\n```\n' > CHECKPOINT.md
  : >"$TMP/load.err2"
  slice_load_routing 2>"$TMP/load.err2"
  [ "$SLICE_RIGOR" = "standard" ] || { echo "corrupt fence should default standard: $SLICE_RIGOR"; exit 1; }
  grep -qi 'unparseable' "$TMP/load.err2" || { echo "expected unparseable warning: $(cat "$TMP/load.err2")"; exit 1; }
)
pass "slice_load_routing fence + legacy alias + env precedence + invalid/corrupt defaults"

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

# missing rigor never fails next
setup "$TMP/c"
# checkpoint without rigor field in body (empty fence)
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
[ "$rc3" -eq 0 ] || [ "$rc3" -eq 3 ] || fail "missing rigor must not crash next (rc=$rc3): $out3"
printf '%s\n' "$out3" | grep -qE '^status:' || fail "missing rigor still status: $out3"
pass "missing rigor never fails next"

# implement-only fence still emits route: (not only rigor/slice_id)
setup "$TMP/implonly"
# Write CHECKPOINT with implement but no rigor/slice_id via raw fence (bypass build_json defaults)
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
[ "$(slice_dual_from_rigor deep build)" = 1 ] || fail "policy dual_wanted deep+build"
[ "$(slice_dual_from_rigor standard build)" = 0 ] || fail "policy dual_wanted standard+build"
pass "dual_wanted policy matrix (pre-eligibility)"

# request.json stamp: call production stamp_request_json (same function run_round uses)
awk '
  /^SLICE_RIGOR=/ {p=1}
  /^# Review charter phase/ {exit}
  p {print}
' "$REVIEW" > "$TMP/slice_helpers2.sh"
# Also extract stamp_request_json function
awk '
  /^stamp_request_json\(\)/ {p=1}
  p {print}
  p && /^}$/ {exit}
' "$REVIEW" >> "$TMP/slice_helpers2.sh"
# shellcheck disable=SC1091
. "$TMP/slice_helpers2.sh"
type stamp_request_json >/dev/null 2>&1 || fail "stamp_request_json not extracted from review.sh"
grep -q 'stamp_request_json "\$SDIR"' "$REVIEW" \
  || fail "run_round must call stamp_request_json (production path)"
mkdir -p "$TMP/req"
(
  cd "$TMP/req"
  cat > CHECKPOINT.md <<'EOF'
```json
{"schema":"plinth.checkpoint/v1","rigor":"deep","implement":"worker","slice_id":"X9"}
```
EOF
  slice_load_routing
  stamp_request_json "$TMP/req" 1 deadbeef origin/main fresh SPEC.md build file_or_default
  jq -e '.slice_routing.rigor=="deep" and .slice_routing.dual_wanted==true
    and .slice_routing.slice_id=="X9"
    and .slice_routing.ack_no_dual==false
    and (.slice_routing.dual_wanted_note|test("policy desire"))
    and .sha=="deadbeef" and .mode=="fresh"' \
    request-1.json >/dev/null || fail "production stamp_request_json: $(cat request-1.json)"
  # HARDEN with standard rigor must stamp dual_wanted=false — the v5.1 default.
  stamp_request_json "$TMP/req" 2 deadbeef origin/main fresh SPEC.md hardening file_or_default
  jq -e '.slice_routing.dual_wanted==true' request-2.json >/dev/null \
    || fail "deep rigor should still want dual in hardening"
  SLICE_RIGOR=standard stamp_request_json "$TMP/req" 3 deadbeef origin/main fresh SPEC.md hardening file_or_default
  jq -e '.slice_routing.rigor=="standard" and .slice_routing.dual_wanted==false' request-3.json >/dev/null \
    || fail "HARDEN+standard must stamp dual_wanted=false (v5.1): $(cat request-3.json)"
  # the ack is stamped on the request when the operator set it
  PLINTH_ACK_NO_DUAL=1 stamp_request_json "$TMP/req" 4 deadbeef origin/main fresh SPEC.md build file_or_default
  jq -e '.slice_routing.ack_no_dual==true' request-4.json >/dev/null \
    || fail "PLINTH_ACK_NO_DUAL must be stamped on the request: $(cat request-4.json)"
)
pass "request.json via production stamp_request_json (rigor, dual_wanted, ack_no_dual)"

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
  'slice_dual_from_rigor',
]
# v5.1 fail-closed path: a REQUESTED dual with no usable seat must die_infra
# (exit 2) BEFORE reviewer_run spends a paid round, unless explicitly acked.
need += [
  'PLINTH_ACK_NO_DUAL',
  'dual-no-seat-ack.json',
  'die_infra "dual first-pass REQUESTED',
]
for n in need:
    if n not in src:
        raise SystemExit(f"production dual gate missing fragment: {n}")
# The fail-closed check must precede the paid primary call in run_round.
i_block = src.index('die_infra "dual first-pass REQUESTED')
i_run = src.index('reviewer_run "$m"')
if not i_block < i_run:
    raise SystemExit("requested-dual fail-closed check must run BEFORE reviewer_run (else a paid round is spent first)")
Path(sys.argv[2]).write_text("ok\n")
PY
# Compose using the same fragments production uses (helpers already sourced)
dual_ok_compose() {
  local m="$1" r="$2" RISK="$3" AUDIT_VENDOR="$4" REVIEWER_VENDOR="$5" rigor="$6" rphase="$7"
  local dual_ok=0
  # Exact eligibility predicate from shared/.plinth/review.sh dual first-pass block
  if [ "$m" = "fresh" ] && [ "$r" = "1" ] && [ "$RISK" = "2" ] \
     && [ -n "${AUDIT_VENDOR:-}" ] && [ "$AUDIT_VENDOR" != "$REVIEWER_VENDOR" ]; then
    dual_ok="$(slice_dual_from_rigor "$rigor" "$rphase" "")"
  fi
  echo "$dual_ok"
}
[ "$(dual_ok_compose fresh 1 2 claude codex deep build)" = 1 ] || fail "eligible deep BUILD dual_ok"
[ "$(dual_ok_compose fresh 1 2 claude codex standard build)" = 0 ] || fail "eligible standard BUILD dual_ok=0"
[ "$(dual_ok_compose fresh 1 2 claude codex standard hardening)" = 0 ] || fail "eligible standard HARDEN dual_ok=0 (v5.1)"
[ "$(dual_ok_compose fresh 1 2 claude codex deep hardening)" = 1 ] || fail "eligible deep HARDEN dual_ok"
[ "$(dual_ok_compose fresh 2 2 claude codex deep build)" = 0 ] || fail "r2 not dual_ok"
[ "$(dual_ok_compose fresh 1 1 claude codex deep build)" = 0 ] || fail "Tier-1 not dual_ok"
[ "$(dual_ok_compose fresh 1 2 codex codex deep build)" = 0 ] || fail "same-vendor not dual_ok"
[ "$(dual_ok_compose verify 1 2 claude codex deep build)" = 0 ] || fail "verify mode not dual_ok"
pass "dual_ok eligibility×policy composition (deep BUILD/HARDEN; standard never)"

# ── requested dual + no cross-vendor seat → FAIL CLOSED (not silent skip) ────
# Replicates the production predicate (the fragment lock above catches drift in
# the real block, which lives inside run_round and cannot be sourced standalone).
requested_dual_blocks() {
  local rigor="$1" override="$2" m="$3" r="$4" RISK="$5" AUDIT_VENDOR="$6" REVIEWER_VENDOR="$7" ack="$8"
  if [ "$(slice_dual_from_rigor "$rigor" build "$override")" = 1 ] \
     && [ "$m" = "fresh" ] && [ "$r" = "1" ] && [ "$RISK" = "2" ] \
     && { [ -z "${AUDIT_VENDOR:-}" ] || [ "$AUDIT_VENDOR" = "$REVIEWER_VENDOR" ]; }; then
    if [ "$ack" = "1" ]; then echo ack; else echo block; fi
  else
    echo run
  fi
}
[ "$(requested_dual_blocks deep "" fresh 1 2 "" codex 0)" = block ] || fail "deep + no audit seat must fail closed"
[ "$(requested_dual_blocks deep "" fresh 1 2 codex codex 0)" = block ] || fail "deep + same-vendor seat must fail closed"
[ "$(requested_dual_blocks standard "" fresh 1 2 "" codex 0)" = run ] || fail "default dual-skip must stay log-only (never block)"
[ "$(requested_dual_blocks standard 1 fresh 1 2 "" codex 0)" = block ] || fail "PLINTH_DUAL_PASS=1 + no seat must fail closed"
[ "$(requested_dual_blocks deep 0 fresh 1 2 "" codex 0)" = run ] || fail "PLINTH_DUAL_PASS=0 withdraws the request"
[ "$(requested_dual_blocks deep "" fresh 1 2 "" codex 1)" = ack ] || fail "PLINTH_ACK_NO_DUAL must convert the block into a recorded ack"
[ "$(requested_dual_blocks deep "" verify 1 2 "" codex 0)" = run ] || fail "a verify round never wanted the seat — must not wedge"
[ "$(requested_dual_blocks deep "" fresh 2 2 "" codex 0)" = run ] || fail "r2 never wanted the seat — must not wedge"
[ "$(requested_dual_blocks deep "" fresh 1 1 "" codex 0)" = run ] || fail "Tier-1 never wanted the seat — must not wedge"
[ "$(requested_dual_blocks deep "" fresh 1 2 codex claude 0)" = run ] || fail "usable cross-vendor seat proceeds to dual"
pass "requested-dual fail-closed matrix (block / ack / never-wedge)"

# the ack must reach the verdict AND the receipt, not just the log
grep -q 'dual_first_pass: "ACK_NO_SEAT"' "$REVIEW" \
  || fail "acked seatless dual must be surfaced on the verdict"
grep -q 'ack_no_dual:\$ack' "$REVIEW" \
  || fail "acked seatless dual must be disclosed on the minted receipt"
python3 - "$REVIEW" <<'PY'
from pathlib import Path
import sys
src = Path(sys.argv[1]).read_text()
# The verdict must carry the ack BEFORE mint_receipt reads the session dir, so
# verdict and receipt disclose the same gap.
i_ack = src.index('dual_first_pass: "ACK_NO_SEAT"')
i_mint = src.rindex('mint_receipt "$round"')
if not i_ack < i_mint:
    raise SystemExit("ack must be surfaced on the verdict before mint_receipt")
PY
pass "ack_no_dual reaches verdict + receipt (ordered before mint)"

echo "canary-checkpoint-routing: ALL PASS"
