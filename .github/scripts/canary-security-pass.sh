#!/usr/bin/env bash
# L3 security-pass trigger canary (v5.1 S4).
#
# v5.1 stopped running a generalist dual pass by default. The security coverage
# that dual was actually providing is now supplied by ONE risk-triggered
# security-focused pass. If this canary passes, the trigger is honest:
#   - security-sensitive / tooling-ship-path / supply-chain surfaces DO fire it;
#   - an inert docs-only diff does NOT (ship bias: no paid pass for nothing);
#   - the operator flag forces it on and off explicitly;
#   - an unreadable classifier fails TOWARD running it, never silently past it;
#   - the pass never false-concurs: unavailable is recorded as UNAVAILABLE, and
#     a same-vendor seat is not counted as an independent opinion.
# It drives the PRODUCTION functions extracted from shared/.plinth/review.sh —
# no live vendor seat required.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REVIEW="$ROOT/shared/.plinth/review.sh"
CLS="$ROOT/shared/.plinth/risk-classify.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

# ── extract the production trigger functions ────────────────────────────────
awk '
  /^security_trigger_re\(\)/ {p=1}
  /^# ── Receipt minting/ {exit}
  p {print}
' "$REVIEW" > "$TMP/trig.sh"
# shellcheck disable=SC1090
. "$TMP/trig.sh"
type security_trigger_re >/dev/null 2>&1 || fail "security_trigger_re not extractable"
type security_pass_wanted >/dev/null 2>&1 || fail "security_pass_wanted not extractable"

want() { printf '%s' "$1" | cut -d' ' -f1; }
why()  { printf '%s' "$1" | cut -d' ' -f2-; }
rj() { jq -cn --args '{tier:2, reasons:$ARGS.positional}' "$@"; }

# ── (1) triggering surfaces ─────────────────────────────────────────────────
fires() {
  local label="$1"; shift
  local out; out="$(security_pass_wanted "$(rj "$@")" "")"
  [ "$(want "$out")" = 1 ] || fail "expected a security pass ($label): $out"
}
fires "auth source"            "security-sensitive: src/auth/login.py"
fires "crypto source"          "security-sensitive: lib/crypto.ts"
fires "tooling ship path"      "tooling: .plinth/review.sh"
fires "claude hooks"           "tooling: .claude/hooks/guard.sh"
fires "sensitive source moved" "sensitive/tooling source moved: a.py -> b.py"
fires "dependency manifest"    "dependency manifest: package-lock.json"
fires "submodule"              "submodule: vendor/thing"
fires "symlink"                "symlink: config/link"
fires "buried among others"    "docs: README.md" "code: src/x.py" "security-sensitive: src/session.go"
# The recorded reason must name the TRIGGERING PATH, not just the category: it is
# the audit trail for why a paid pass ran. (ERE binds `a|b[^;]*` as `a` OR
# `b[^;]*`, so an unparenthesized alternation silently drops the path for every
# alternative but the last.)
for probe in "security-sensitive: src/auth/login.py|src/auth/login.py" \
             "tooling: .plinth/review.sh|.plinth/review.sh" \
             "dependency manifest: package-lock.json|package-lock.json"; do
  reason_in="${probe%%|*}"; want_path="${probe#*|}"
  out="$(security_pass_wanted "$(rj "$reason_in")" "")"
  printf '%s' "$(why "$out")" | grep -qF "$want_path" \
    || fail "recorded reason dropped the triggering path (want '$want_path'): $out"
done
pass "security-sensitive / tooling / supply-chain surfaces fire the L3 pass (with the path recorded)"

# ── (2) inert diffs do NOT (ship bias — no paid pass for nothing) ───────────
quiet() {
  local label="$1"; shift
  local out; out="$(security_pass_wanted "$(rj "$@")" "")"
  [ "$(want "$out")" = 0 ] || fail "expected NO security pass ($label): $out"
}
quiet "docs only"        "docs: README.md"
quiet "plain code"       "code: src/widget.py"
quiet "test added"       "test added: tests/test_widget.py"
quiet "docs + code"      "docs: docs/guide.md" "code: src/widget.py"
pass "inert diffs do not trigger a paid security pass"

# ── (3) the operator flag is explicit in both directions ────────────────────
out="$(security_pass_wanted "$(rj 'docs: README.md')" 1)"
[ "$(want "$out")" = 1 ] || fail "PLINTH_SECURITY_PASS=1 must force the pass on: $out"
printf '%s' "$(why "$out")" | grep -q 'PLINTH_SECURITY_PASS=1' || fail "forced-on reason must name the flag: $out"
out="$(security_pass_wanted "$(rj 'security-sensitive: src/auth.py')" 0)"
[ "$(want "$out")" = 0 ] || fail "PLINTH_SECURITY_PASS=0 must force the pass off: $out"
printf '%s' "$(why "$out")" | grep -qi 'declined' || fail "forced-off reason must record the operator decision: $out"
pass "PLINTH_SECURITY_PASS forces on/off with the reason recorded"

# ── (4) unreadable classifier fails TOWARD the pass ─────────────────────────
# A skipped security pass is exactly the silent gap this layer closes, so an
# unparseable or empty risk JSON must run it, not skip it.
for bad in "" "not json at all" '{"tier":2}' '{"tier":2,"reasons":[]}'; do
  out="$(security_pass_wanted "$bad" "")"
  [ "$(want "$out")" = 1 ] \
    || fail "unreadable risk JSON must fail TOWARD a security pass (input='$bad'): $out"
done
pass "unreadable/empty risk reasons fail toward running the pass"

# ── (5) the trigger list is a single in-repo source ─────────────────────────
re="$(security_trigger_re)"
[ -n "$re" ] || fail "empty trigger regex"
for tok in 'security-sensitive:' 'tooling:' 'dependency manifest:' submodule symlink; do
  printf '%s' "$re" | grep -qF "$tok" || fail "trigger list lost '$tok'"
done
# The trigger list lives under .plinth/, so widening/narrowing it is Tier 2 by
# construction — the same bound the demotion allowlist gets. Assert it, since a
# trigger list that could ship under a Tier-1 review is not really bounded.
RC=$(mktemp -d)
(
  set -euo pipefail
  cd "$RC"
  git init -q; git config user.email t@t; git config user.name t
  mkdir -p shared/.plinth .plinth
  echo x > shared/.plinth/review.sh
  printf 'spec_path = SPEC.md\n' > .plinth/config
  echo spec > SPEC.md
  git add -A; git commit -qm base
  base_branch="$(git rev-parse --abbrev-ref HEAD)"
  git checkout -qb feat/narrow
  # simulate narrowing the security trigger list
  printf 'security_trigger_re() { printf %%s "security-sensitive:"; }\n' >> shared/.plinth/review.sh
  git add -A; git commit -qm narrow
  out="$("$CLS" "$base_branch" 2>/dev/null || true)"
  printf '%s' "$out" | jq -e '.reasons | join(" ") | test("base ref not found") | not' >/dev/null \
    || { echo "fixture base ref did not resolve — assertion would be vacuous: $out"; exit 1; }
  [ "$(printf '%s' "$out" | jq -r '.tier')" = "2" ] \
    || { echo "narrowing the security trigger list was not Tier 2: $out"; exit 1; }
)
pass "trigger list is in-repo and its edit surface is Tier 2"

# ── (6) the pass never false-concurs ───────────────────────────────────────
# Structural locks on the production block: unavailable and same-vendor must be
# recorded as UNAVAILABLE (not as a clean pass), the required-knob must fail
# closed, and the knob must be read from the BASE config so a PR cannot delete it.
python3 - "$REVIEW" <<'PY'
from pathlib import Path
import sys
src = Path(sys.argv[1]).read_text()
need = {
  'security_pass wired to the verdict': 'security_pass: {status: "RAN"',
  'unavailable recorded, not concurred': 'security_pass: {status: "UNAVAILABLE"',
  'not-triggered recorded': 'security_pass: {status: "NOT_TRIGGERED"',
  'required knob fails closed': 'security_pass_required=true in .plinth/config',
  'same-vendor is not an independent opinion': 'no independent seat',
  'knob read from base config': 'bcfg security_pass_required',
  'status folded into the receipt': 'security_pass:$sp',
}
for label, frag in need.items():
    if frag not in src:
        raise SystemExit(f"missing production wiring — {label}: {frag!r}")
# The receipt must read the status off the verdict, never default to something
# reassuring when the verdict cannot be read.
if 'sp_status="UNKNOWN"' not in src:
    raise SystemExit("receipt must default security_pass to UNKNOWN, not a reassuring value")
# A same-vendor seat must be gated by an explicit inequality test.
if '[ "$AUDIT_VENDOR" != "$REVIEWER_VENDOR" ]' not in src:
    raise SystemExit("security pass must require an independent (cross-vendor) seat")
PY
pass "no false concur: UNAVAILABLE recorded, required-knob fails closed, base-config read"

# ── (7) the no-model approval paths must not silently claim NOT_TRIGGERED ───────
# Round 29 walked straight past the trigger: Tier-0 and HANDOFF/CHECKPOINT-only
# approvals exit BEFORE security_pass_wanted, so PLINTH_SECURITY_PASS=1 — documented
# as always forcing L3 — was hardcoded NOT_TRIGGERED and security_pass_required was
# never evaluated. The canary previously tested only the pure helper, which is why
# it passed. These assertions target the INTEGRATION, not the helper.
awk '/^record_no_model_security_pass\(\)/ {p=1} p {print} p && /^}$/ {exit}' "$REVIEW" > "$TMP/nomodel.sh"
[ -s "$TMP/nomodel.sh" ] || fail "record_no_model_security_pass not extractable — the no-model paths would silently claim NOT_TRIGGERED again"
python3 - "$REVIEW" <<'PY2'
from pathlib import Path
import sys
src = Path(sys.argv[1]).read_text()
# Both no-model approval paths must call the recorder BEFORE minting, so the verdict
# and the receipt disclose the same thing.
for ctx in ("Tier 0 deterministic floor", "HANDOFF/CHECKPOINT-only ephemera floor"):
    if f'record_no_model_security_pass "$SDIR/verdict.json" "{ctx}"' not in src:
        raise SystemExit(f"no-model path missing the honest security_pass recorder: {ctx}")
i_t0 = src.index('record_no_model_security_pass "$SDIR/verdict.json" "Tier 0 deterministic floor"')
i_m0 = src.index("mint_receipt 0", i_t0)
if not i_t0 < i_m0:
    raise SystemExit("Tier-0 recorder must run before mint_receipt")
if 'security_pass:{status:"NOT_TRIGGERED", trigger:"Tier 0' in src:
    raise SystemExit("Tier-0 still hardcodes NOT_TRIGGERED instead of evaluating the trigger")
if "SKIPPED_NO_MODEL_ROUND" not in src:
    raise SystemExit("a triggered-but-unrunnable pass must record SKIPPED_NO_MODEL_ROUND")
if "security_pass_required=true, but ${ctx} approves without a model round" not in src:
    raise SystemExit("security_pass_required must fail closed on the no-model paths")
PY2
[ "$?" = 0 ] || fail "no-model integration wiring missing"
# Drive the real recorder: a forced pass on a no-model path records SKIPPED, not NOT_TRIGGERED.
NM=$(mktemp -d)
(
  set -euo pipefail
  cd "$NM"
  # shellcheck disable=SC1090
  . "$TMP/trig.sh"; . "$TMP/nomodel.sh"
  bcfg() { :; }; cfg() { :; }; base_has_config=1
  die_infra() { echo "DIE:$*"; exit 9; }
  RISK_JSON='{"tier":0,"reasons":["empty diff"]}'
  echo '{"verdict":"APPROVED","round":0}' > v.json
  PLINTH_SECURITY_PASS=1 record_no_model_security_pass v.json "Tier 0 deterministic floor" >/dev/null
  st=$(jq -r '.security_pass.status' v.json)
  [ "$st" = "SKIPPED_NO_MODEL_ROUND" ] || { echo "forced pass on a no-model path recorded '$st', expected SKIPPED_NO_MODEL_ROUND"; exit 1; }
  # untriggered stays NOT_TRIGGERED
  echo '{"verdict":"APPROVED","round":0}' > v2.json
  record_no_model_security_pass v2.json "Tier 0 deterministic floor" >/dev/null
  st2=$(jq -r '.security_pass.status' v2.json)
  [ "$st2" = "NOT_TRIGGERED" ] || { echo "untriggered recorded '$st2', expected NOT_TRIGGERED"; exit 1; }
) || fail "no-model security_pass recorder behaves incorrectly"
pass "no-model approval paths record SKIPPED_NO_MODEL_ROUND, never a silent NOT_TRIGGERED"

echo "canary-security-pass: ALL PASS"
