#!/usr/bin/env bash
# plinth#62: advise distinguishes missing CLI vs auth/failure (no conflated message)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLINTH="${PLINTH:-$ROOT/bin/plinth}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

# Missing CLI: PATH without claude, advisor_vendor=claude
mkdir -p "$TMP/proj/.plinth"
cd "$TMP/proj"
git init -q
git config user.email t@t && git config user.name t
echo x > f && git add f && git commit -qm i
printf 'advisor_vendor = claude\nadvisor_model = opus\n' > .plinth/config
# Empty PATH except shell builtins via env that has no claude
set +e
out=$(PATH="/usr/bin:/bin" "$PLINTH" advise "should fail missing" 2>&1)
rc=$?
set -e
# advise returns 0 even when unavailable (non-blocking), but message must NOT say only "missing or not signed in" without path distinction
echo "$out" | grep -qi 'not on PATH\|CLI not on PATH\|command -v' \
  || fail "missing CLI should say not on PATH: $out"
echo "$out" | grep -qi 'missing or not signed in' \
  && fail "must not use conflated missing-or-unsigned message: $out" || true
pass "missing claude → PATH diagnostic (not conflated)"

# Product strings present (no network)
grep -q '_nh_blocker_scope()' "$ROOT/bin/plinth" || fail "missing _nh_blocker_scope"
grep -q '_nh_blocker_applies_to_phase()' "$ROOT/bin/plinth" || fail "missing phase apply helper"
grep -q 'not on PATH' "$ROOT/bin/plinth" || fail "missing PATH diagnostic"
grep -q 'is not signed in for this environment' "$ROOT/bin/plinth" || fail "missing auth diagnostic"
pass "advise diagnostic strings present in product"

echo "canary-advise-diag: ALL PASS"
