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
echo "$out" | grep -qi 'not on PATH\|CLI not on PATH\|command -v' \
  || fail "missing CLI should say not on PATH: $out"
echo "$out" | grep -qi 'missing or not signed in' \
  && fail "must not use conflated missing-or-unsigned message: $out" || true
pass "missing claude → PATH diagnostic (not conflated)"

# Product strings present
grep -q '_nh_blocker_scope()' "$ROOT/bin/plinth" || fail "missing _nh_blocker_scope"
grep -q '_nh_blocker_applies_to_phase()' "$ROOT/bin/plinth" || fail "missing phase apply helper"
grep -q 'not on PATH' "$ROOT/bin/plinth" || fail "missing PATH diagnostic"
grep -q 'is not signed in for this environment' "$ROOT/bin/plinth" || fail "missing auth diagnostic"
grep -q '_advise_auth_hit' "$ROOT/bin/plinth" || fail "missing _advise_auth_hit helper"
pass "advise diagnostic strings present in product"

# --- Fake vendor helpers ---
# Mode via FAKE_ADVISE_MODE: auth_stderr | auth_stdout0 | auth_stdout_nz | ok | empty | fail_nz
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
    # Short exit-0 unauth banner (real CLIs sometimes do this)
    echo "Please sign in"
    exit 0
    ;;
  auth_stdout_nz)
    echo "Error: not authenticated." 
    exit 2
    ;;
  ok)
    # Legitimate advice that mentions authentication in prose — must NOT auth-fail
    echo "Sound: the request is not authenticated until middleware lands; please run the focused tests."
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

run_advise_vendor() {
  local vendor="$1" mode="$2"
  printf 'advisor_vendor = %s\nadvisor_model = x\n' "$vendor" > .plinth/config
  install_fake "$vendor"
  # Also install agy when vendor is agy
  export FAKE_ADVISE_MODE="$mode"
  set +e
  out=$(PATH="$TMP/bin:/usr/bin:/bin" FAKE_ADVISE_MODE="$mode" "$PLINTH" advise "q" 2>&1)
  rc=$?
  set -e
  printf '%s\n' "$out"
}

# Auth via stderr → not signed in
out=$(run_advise_vendor claude auth_stderr)
echo "$out" | grep -qi 'not signed in' || fail "auth_stderr should be not signed in: $out"
echo "$out" | grep -qi 'Sound:' && fail "auth_stderr must not emit advice: $out" || true
pass "claude auth_stderr → not signed in"

# Exit-0 short banner → not signed in
out=$(run_advise_vendor claude auth_stdout0)
echo "$out" | grep -qi 'not signed in' || fail "auth_stdout0 short banner: $out"
pass "claude exit-0 Please sign in → not signed in"

# Exit nonzero auth on stdout
out=$(run_advise_vendor codex auth_stdout_nz)
echo "$out" | grep -qi 'not signed in' || fail "auth_stdout_nz: $out"
pass "codex nonzero stdout auth → not signed in"

# Legitimate long advice mentioning auth → SUCCESS (printed advice, not unavailable)
out=$(run_advise_vendor grok ok)
echo "$out" | grep -qi 'advisor unavailable\|not signed in' \
  && fail "ok advice must not auth-fail: $out" || true
echo "$out" | grep -qi 'Sound: the request is not authenticated' \
  || fail "ok advice should print: $out"
pass "grok exit-0 prose with 'not authenticated until' is advice"

# Empty success → empty output diagnostic
out=$(run_advise_vendor agy empty)
echo "$out" | grep -qi 'empty output\|advisor unavailable' || fail "empty: $out"
pass "agy empty stdout → unavailable"

# Nonzero non-auth → exited N
out=$(run_advise_vendor claude fail_nz)
echo "$out" | grep -qiE 'exited 7|advisor unavailable' || fail "fail_nz: $out"
echo "$out" | grep -qi 'not signed in' && fail "fail_nz must not be auth: $out" || true
pass "claude nonzero non-auth → exited (not auth)"

echo "canary-advise-diag: ALL PASS"
