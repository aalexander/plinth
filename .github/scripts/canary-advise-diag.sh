#!/usr/bin/env bash
# plinth#62: advise distinguishes missing CLI vs auth/failure (no conflated message)
# Exercises real run_advise vendor branches via fake PATH CLIs (no network).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLINTH="${PLINTH:-$ROOT/bin/plinth}"
TMP=$(mktemp -d)
export TMPDIR="$TMP/tmp"
mkdir -p "$TMPDIR"
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
grep -q '_advise_line_is_banner' "$ROOT/bin/plinth" || fail "missing _advise_line_is_banner helper"
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
  ok_embed_banner)
    # Legitimate advice embedding banner tokens mid-sentence
    echo "Keep public routes visible when not logged in."
    exit 0
    ;;
  ok_embed_sign_in)
    echo "Docs: operators please sign in only after staging is up."
    exit 0
    ;;
  auth_four_lines_unterminated)
    # Four whole-line banners, no final newline — logical count must be 4 (not auth).
    printf '%s' $'Please sign in\nPlease sign in\nPlease sign in\nPlease sign in'
    exit 0
    ;;
  auth_three_lines)
    printf '%s\n' "Please sign in" "Not logged in" "Please run /login"
    exit 0
    ;;
  empty)
    exit 0
    ;;
  whitespace)
    printf '   \n\t  \n'
    exit 0
    ;;
  fail_nz)
    echo "model overloaded" >&2
    exit 7
    ;;
  slow)
    # Dies on TERM (default); used for cancellation cleanup check
    sleep 8
    exit 0
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
[ "$_adv_rc" -eq 0 ] || fail "ok_short rc"
echo "$_adv_out" | grep -qi 'not signed in\|advisor unavailable' \
  && fail "short advice with authentication required must not auth-fail: $_adv_out" || true
echo "$_adv_out" | grep -qi 'Sound: require authentication' \
  || fail "short advice should print: $_adv_out"
pass "short exit-0 advice with authentication required is advice"

run_advise_vendor claude ok_embed_banner
[ "$_adv_rc" -eq 0 ] || fail "embed banner rc"
echo "$_adv_out" | grep -qi 'not signed in\|advisor unavailable' \
  && fail "embedded not logged in must be advice: $_adv_out" || true
echo "$_adv_out" | grep -qi 'Keep public routes visible when not logged in' \
  || fail "embed advice print: $_adv_out"
pass "advice embedding 'not logged in' mid-sentence is advice"

run_advise_vendor grok ok_embed_sign_in
[ "$_adv_rc" -eq 0 ] || fail "embed sign-in rc"
echo "$_adv_out" | grep -qi 'not signed in\|advisor unavailable' \
  && fail "embedded please sign in must be advice: $_adv_out" || true
echo "$_adv_out" | grep -qi 'please sign in only after staging' \
  || fail "embed sign-in advice text missing: $_adv_out"
pass "advice embedding please sign in mid-sentence is advice"

run_advise_vendor codex auth_stdout_nz
[ "$_adv_rc" -eq 0 ] || fail "codex auth must be non-blocking rc=0"
echo "$_adv_out" | grep -qi 'not signed in' || fail "auth_stdout_nz recheck: $_adv_out"

run_advise_vendor agy empty
[ "$_adv_rc" -eq 0 ] || fail "empty must be non-blocking"
echo "$_adv_out" | grep -qi 'empty output\|advisor unavailable' || fail "empty: $_adv_out"
pass "agy empty stdout → unavailable"
run_advise_vendor claude whitespace
echo "$_adv_out" | grep -qi 'empty output\|advisor unavailable' || fail "whitespace: $_adv_out"
pass "whitespace-only stdout is empty (not advice)"
for v in codex grok agy; do
  run_advise_vendor "$v" whitespace
  echo "$_adv_out" | grep -qi 'empty output\|advisor unavailable' || fail "$v whitespace: $_adv_out"
done
pass "whitespace-only stdout empty on all vendors"

run_advise_vendor claude fail_nz
[ "$_adv_rc" -eq 0 ] || fail "fail_nz must be non-blocking"
echo "$_adv_out" | grep -qiE 'exited 7|advisor unavailable' || fail "fail_nz: $_adv_out"
echo "$_adv_out" | grep -qi 'not signed in' && fail "fail_nz must not be auth: $_adv_out" || true
pass "claude nonzero non-auth → exited (not auth)"

# grok failure path
run_advise_vendor grok fail_nz
[ "$_adv_rc" -eq 0 ] || fail "grok fail non-blocking"
echo "$_adv_out" | grep -qiE 'exited 7|advisor unavailable' || fail "grok fail_nz: $_adv_out"
pass "grok nonzero non-auth → exited (not auth)"

# four unterminated banner lines → NOT short-banner auth; must return advice text
run_advise_vendor claude auth_four_lines_unterminated
echo "$_adv_out" | grep -qi 'not signed in' \
  && fail "4 unterminated banner lines must not be short-banner auth: $_adv_out" || true
echo "$_adv_out" | grep -qi 'Please sign in' \
  || fail "four-line advice must print content: $_adv_out"
# count Please sign in occurrences >= 3
n=$(echo "$_adv_out" | grep -ci 'please sign in' || true)
[ "${n:-0}" -ge 3 ] || fail "expected multiple banner lines as advice, got n=$n out=$_adv_out"
pass "four unterminated banner lines are not short-banner auth"

# three whole-line banners → auth
run_advise_vendor claude auth_three_lines
echo "$_adv_out" | grep -qi 'not signed in' || fail "3-line banner should be auth: $_adv_out"
pass "three whole-line banners classify as auth"

# successful advise removes prompt temp files created during this run
rm -f "$TMPDIR"/plinth-advise-prompt.* 2>/dev/null || true
run_advise_vendor claude ok
leftover=$(ls "$TMPDIR"/plinth-advise-prompt.* 2>/dev/null | head -5 || true)
[ -z "$leftover" ] || fail "prompt temp files left after success: $leftover"
# product cleanup must include _apf (signal path + success)
grep -q '_apf' "$ROOT/bin/plinth" || fail "missing _apf prompt path"
grep -A8 '_advise_cleanup()' "$ROOT/bin/plinth" | grep -q '_apf' \
  || fail "_advise_cleanup must rm _apf (signal path)"
# also clear _apf after success rm so signal mid-run still cleans
grep -q 'rm -f "\$_apf"' "$ROOT/bin/plinth" || grep -q 'rm -f "$_apf"' "$ROOT/bin/plinth" \
  || fail "success path should rm _apf"
pass "advise prompt files cleaned; cleanup covers _apf"

# positive auth for grok + agy
run_advise_vendor grok auth_stderr
echo "$_adv_out" | grep -qi 'not signed in' || fail "grok auth_stderr: $_adv_out"
pass "grok auth_stderr → not signed in"
run_advise_vendor agy auth_stdout0
echo "$_adv_out" | grep -qi 'not signed in' || fail "agy auth_stdout0: $_adv_out"
pass "agy exit-0 Please sign in → not signed in"

# soft cancel: short sleep fake; TERM parent; no prompt leftovers
rm -f "$TMPDIR"/plinth-advise-prompt.* 2>/dev/null || true
printf 'advisor_vendor = claude\nadvisor_model = x\n' > .plinth/config
install_fake claude
set +e
PATH="$TMP/bin:/usr/bin:/bin" FAKE_ADVISE_MODE=slow \
  "$PLINTH" advise "cancel-secret-token" >"$TMP/adv-cancel.out" 2>&1 &
pid=$!
sleep 0.25
kill -TERM "$pid" 2>/dev/null || true
# bounded wait
for i in 1 2 3 4 5 6 7 8 9 10; do
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.3
done
kill -KILL "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
set -e
leftover=$(ls "$TMPDIR"/plinth-advise-prompt.* 2>/dev/null | head -3 || true)
[ -z "$leftover" ] || fail "prompt leak after TERM: $leftover"
pass "TERM cancel path leaves no prompt files"

echo "canary-advise-diag: ALL PASS"
