#!/usr/bin/env bash
# Checkpoint + slice routing canary (v5.0.5)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLINTH="${PLINTH:-$ROOT/bin/plinth}"
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

setup "$TMP/a"
PLINTH_CHECKPOINT_SLICE_ID=R2 PLINTH_CHECKPOINT_SLICE_INDEX=2 PLINTH_CHECKPOINT_SLICE_TOTAL=5 \
PLINTH_CHECKPOINT_EFFORT=medium PLINTH_CHECKPOINT_IMPLEMENT=driver \
PLINTH_CHECKPOINT_EFFORT_RATIONALE='judgment-shaped' \
  "$PLINTH" checkpoint . >/dev/null
[ -f CHECKPOINT.md ] || fail "CHECKPOINT.md missing"
[ -f HANDOFF.md ] || fail "HANDOFF pointer missing"
grep -q 'plinth.checkpoint/v1' CHECKPOINT.md || fail "schema missing"
grep -q '"effort": "medium"' CHECKPOINT.md || fail "effort not medium"
grep -q 'Canonical restart state' HANDOFF.md || fail "HANDOFF not pointer"
# invalid JSON fail-soft: keep prior fields
printf '\n```json\n{broken\n```\n' >> CHECKPOINT.md
"$PLINTH" checkpoint . >/dev/null
grep -q '"slice_id": "R2"' CHECKPOINT.md || fail "did not preserve slice_id after corrupt fence"
# next route line
out=$("$PLINTH" next . 2>&1 || true)
printf '%s\n' "$out" | grep -qE '^route:|^status:' || fail "next missing status"
# legacy HANDOFF-only read path
setup "$TMP/b"
# write only HANDOFF with Next (no CHECKPOINT)
cat > HANDOFF.md <<'EOF'
# Handoff
## Next
1. do the thing
EOF
out2=$("$PLINTH" next . 2>&1 || true)
printf '%s\n' "$out2" | grep -q 'do the thing' || fail "HANDOFF-only fallback next: $out2"
pass "checkpoint write/preserve + HANDOFF fallback"
echo "canary-checkpoint-routing: ALL PASS"
