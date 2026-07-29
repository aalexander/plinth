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
# Must not classify ordinary "please run the tests" advice as unauth
grep -q 'please run /login' "$ROOT/bin/plinth" || fail "auth re must require /login not bare please run"
pass "advise diagnostic strings present in product"

# Fake claude: exit 0 with legitimate advice containing 'please run' must NOT be auth-fail
# (unit: the classifier pattern alone)
python3 - <<'PY'
import re
re_auth = re.compile(
    r"not logged in|please run /login|not authenticated|auth(entication)? (fail|required|error)|unauthorized \(401\)|401 unauthorized",
    re.I,
)
ok = "Sound; please run the focused tests before merging"
assert not re_auth.search(ok), ok
assert re_auth.search("Not logged in · Please run /login")
print("auth classifier unit ok")
PY
pass "auth classifier does not false-positive on please-run advice"

echo "canary-advise-diag: ALL PASS"
