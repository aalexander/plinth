#!/usr/bin/env bash
# plinth#62: advise distinguishes missing CLI vs auth/failure (no conflated message)
# Exercises real run_advise vendor branches via fake PATH CLIs (no network).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLINTH="${PLINTH:-$ROOT/bin/plinth}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

mkdir -p "$TMP/proj/.plinth" "$TMP/bin"
cd "$TMP/proj"
git init -q
git config user.email t@t && git config user.name t
echo x > f && git add f && git commit -qm i

# --- Missing CLI: PATH without claude ---
printf 'advisor_vendor = claude\nadvisor_model = opus\n' > .plinth/config
set +e
out=$(PATH="/usr/bin:/bin" "$PLINTH" advise "should fail missing" 2>&1)
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "advise must be non-blocking exit 0 on missing CLI (rc=$rc)"
echo "$out" | grep -qi 'not on PATH\|CLI not on PATH\|command -v' \
  || fail "missing CLI should say not on PATH: $out"
echo "$out" | grep -qi 'missing or not signed in' \
  && fail "must not use conflated missing-or-unsigned message: $out" || true
pass "missing claude → PATH diagnostic (not conflated)"

grep -q '_advise_auth_hit' "$ROOT/bin/plinth" || fail "missing _advise_auth_hit helper"
grep -q '_advise_banner_re' "$ROOT/bin/plinth" || fail "missing narrow banner re"
pass "advise diagnostic helpers present in product"

install_fake() {
  local name="$1"
  cat > "$TMP/bin/$name" <<'FAKE'
#!/usr/bin/env bash
mode="${FAKE_ADVISE_MODE:-ok}"
case "$mode" in
  auth_stderr)
    echo "Not logged in. Please run /login" >&2
    exit 1
    ;;
  auth_stdout0)
    echo "Please sign in"
    exit 0
    ;;
  auth_stdout_nz)
    echo "Error: not authenticated."
    exit 2
    ;;
  ok)
    echo "Sound: the request is not authenticated until middleware lands; please run the focused tests."
    exit 0
    ;;
  ok_short_auth_phrase)
    # Concise valid advice containing generic auth phrases — must NOT auth-fail
    echo "Sound: require authentication; authentication required before protected-route rollout."
    exit 0
    ;;
  empty)
    exit 0
    ;;
  fail_nz)
    echo "model overloaded" >&2
    exit 7
    ;;
  *)
    echo "unknown FAKE_ADVISE_MODE=$mode" >&2
    exit 99
    ;;
esac
FAKE
  chmod +x "$TMP/bin/$name"
}

# Sets globals _adv_out and _adv_rc (must not run under $() — set -u subshell).
run_advise_vendor() {
  local vendor="$1" mode="$2"
  printf 'advisor_vendor = %s\nadvisor_model = x\n' "$vendor" > .plinth/config
  install_fake "$vendor"
  export FAKE_ADVISE_MODE="$mode"
  set +e
  _adv_out=$(PATH="$TMP/bin:/usr/bin:/bin" FAKE_ADVISE_MODE="$mode" "$PLINTH" advise "q" 2>&1)
  _adv_rc=$?
  set -e
}

_adv_out=""; _adv_rc=0
run_advise_vendor claude auth_stderr
[ "$_adv_rc" -eq 0 ] || fail "auth fail must stay non-blocking rc=0 (got $_adv_rc)"
echo "$_adv_out" | grep -qi 'not signed in' || fail "auth_stderr should be not signed in: $_adv_out"
pass "claude auth_stderr → not signed in (rc=0)"

run_advise_vendor claude auth_stdout0
[ "$_adv_rc" -eq 0 ] || fail "banner auth rc"
echo "$_adv_out" | grep -qi 'not signed in' || fail "auth_stdout0 short banner: $_adv_out"
pass "claude exit-0 Please sign in → not signed in"

run_advise_vendor codex auth_stdout_nz
echo "$_adv_out" | grep -qi 'not signed in' || fail "auth_stdout_nz: $_adv_out"
pass "codex nonzero stdout auth → not signed in"

run_advise_vendor grok ok
echo "$_adv_out" | grep -qi 'advisor unavailable\|not signed in' \
  && fail "ok advice must not auth-fail: $_adv_out" || true
echo "$_adv_out" | grep -qi 'Sound: the request is not authenticated' \
  || fail "ok advice should print: $_adv_out"
pass "grok exit-0 prose with 'not authenticated until' is advice"

run_advise_vendor claude ok_short_auth_phrase
echo "$_adv_out" | grep -qi 'not signed in\|advisor unavailable' \
  && fail "short advice with authentication required must not auth-fail: $_adv_out" || true
echo "$_adv_out" | grep -qi 'Sound: require authentication' \
  || fail "short advice should print: $_adv_out"
pass "short exit-0 advice with authentication required is advice"

run_advise_vendor agy empty
echo "$_adv_out" | grep -qi 'empty output\|advisor unavailable' || fail "empty: $_adv_out"
pass "agy empty stdout → unavailable"

run_advise_vendor claude fail_nz
echo "$_adv_out" | grep -qiE 'exited 7|advisor unavailable' || fail "fail_nz: $_adv_out"
echo "$_adv_out" | grep -qi 'not signed in' && fail "fail_nz must not be auth: $_adv_out" || true
pass "claude nonzero non-auth → exited (not auth)"

echo "canary-advise-diag: ALL PASS"
