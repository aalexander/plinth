#!/usr/bin/env bash
# Thrash DEMOTION CLASS bounds canary (v5.1 S2).
#
# Class demotion is a deliberate FAIL-OPEN: it turns a reviewer's major into a
# minor so the loop can converge. This canary is the regression lock on its
# bounds. If it passes, three properties hold:
#   1. the classifier can emit NOTHING outside the in-repo allowlist;
#   2. security / correctness / data-loss / real-test-gap findings are NEVER
#      demoted, however they are worded or wherever they are filed;
#   3. the asymptotic classes the 5.1 plan named ARE demoted in BUILD, so the
#      ship spiral stops without another paid round.
# It drives the PRODUCTION jq (thrash_policy_process_findings extracted from
# shared/.plinth/review.sh) — never a re-implementation of the rules.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REVIEW="$ROOT/shared/.plinth/review.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

# ── extract the production function (no re-implementation) ──────────────────
awk '
  /^thrash_policy_process_findings\(\)/ {p=1}
  p {print}
  p && /^}$/ {exit}
' "$REVIEW" > "$TMP/thrash_fn.sh"
# shellcheck disable=SC1090
. "$TMP/thrash_fn.sh"
type thrash_policy_process_findings >/dev/null 2>&1 \
  || fail "thrash_policy_process_findings not extractable from review.sh"

# ── the allowlist is a SINGLE SOURCE, read out of production ────────────────
# Parse the `def demotable_classes: [ ... ];` array out of review.sh itself. A
# canary carrying its own copy of the list could not detect the list changing.
ALLOW_JSON="$(python3 - "$REVIEW" <<'PY'
import json, re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"def demotable_classes:\s*\[(.*?)\];", src, re.S)
if not m:
    raise SystemExit("could not find `def demotable_classes:` in review.sh")
print(json.dumps(re.findall(r'"([^"]+)"', m.group(1))))
PY
)" || fail "allowlist not extractable"
[ -n "$ALLOW_JSON" ] || fail "empty allowlist extraction"
n_allow=$(printf '%s' "$ALLOW_JSON" | jq 'length')
[ "$n_allow" -ge 1 ] || fail "allowlist is empty — every demotion would be unbounded"
# Nothing security/correctness-shaped may ever enter the vocabulary.
printf '%s' "$ALLOW_JSON" | jq -e '
  map(test("secur|auth|crypt|secret|data.?loss|correct|ship|integrity|test-gap|acceptance"; "i")) | any | not
' >/dev/null || fail "allowlist contains a security/correctness-shaped class: $ALLOW_JSON"
printf '%s' "$ALLOW_JSON" | jq -e 'map(startswith("class:")) | all' >/dev/null \
  || fail "every demotable class must be namespaced class:*: $ALLOW_JSON"
pass "demotable allowlist extracted from production ($n_allow classes, none security-shaped)"

# ── every class:* literal in review.sh is allowlisted (sticky alignment) ────
# `thrash_class` is duplicated across the sticky blocks (identity/fingerprinting,
# not demotion authority) and emits class IDs of its own. If sticky ever coined a
# class the demotion vocabulary does not know — or the vocabulary dropped one
# sticky still emits — the two would drift apart silently. Assert one vocabulary
# across the whole file. `class:none` is the sentinel for "not demotable".
python3 - "$REVIEW" "$ALLOW_JSON" <<'PY'
import json, re, sys
src = open(sys.argv[1], encoding="utf-8").read()
allow = set(json.loads(sys.argv[2])) | {"class:none"}
found = set(re.findall(r'"(class:[a-z0-9-]+)"', src))
extra = sorted(found - allow)
if extra:
    raise SystemExit(
        "class IDs used in review.sh but absent from demotable_classes: "
        + ", ".join(extra)
    )
print(f"vocabulary agrees across {len(found)} class literal(s)")
PY
[ "$?" = 0 ] || fail "sticky/demotion class vocabularies drifted"
pass "one class vocabulary across review.sh (sticky fingerprints ⊆ allowlist)"

# ── fixture driver ──────────────────────────────────────────────────────────
# emit <file> <severity> <description>  → one-finding findings JSON
mkf() {
  jq -n --arg f "$1" --arg s "$2" --arg d "$3" \
    '{verdict:"CHANGES_NEEDED", summary:"t",
      findings:[{id:"F1", file:$f, line:1, severity:$s, description:$d, status:"open"}]}'
}
# run <phase> <file> <severity> <desc> [scope] [prior] [mode] → severity + marker
run_one() {
  local phase="$1" file="$2" sev="$3" desc="$4" scope="${5:-}" prior="${6:-}" mode="${7:-fresh}"
  mkf "$file" "$sev" "$desc" > "$TMP/f.json"
  thrash_policy_process_findings "$TMP/f.json" "$phase" "$scope" "$prior" "SPEC.md" "$mode"
  jq -r '.findings[0] | .severity + "|" + (.description // "")' "$TMP/f.json"
}
sev_of() { printf '%s' "$1" | cut -d'|' -f1; }
class_of() {
  # the class recorded in the THRASH marker, or empty when not demoted
  printf '%s' "$1" | sed -n 's/.*\[THRASH:\(class:[a-z-]*\).*/\1/p'
}

# ── (1) NEVER-DEMOTE FLOOR ──────────────────────────────────────────────────
# Each of these is worded to ALSO trip a demotable classifier, so a floor that
# is merely "checked somewhere" rather than "checked first" fails here.
never_demote() {
  local label="$1" phase="$2" file="$3" desc="$4"
  local out; out="$(run_one "$phase" "$file" major "$desc")"
  [ "$(sev_of "$out")" = "major" ] \
    || fail "NEVER-DEMOTE violated ($label): $out"
}
# fabricated security major dressed as asymptotic coverage (plan criterion #3)
never_demote "auth bypass + coverage wording" build src/app.py \
  "coverage remains incomplete: no test covers the auth bypass when the session token is unauthenticated"
never_demote "secret exposure + docs path" build docs/notes.md \
  "credential leak: the doc example embeds a live secret expos[ure] in the copy-paste block"
never_demote "receipt forgery + dual e2e wording" build shared/.plinth/review.sh \
  "dual e2e cannot cover this: a forged receipt bypass lets APPROVED@HEAD be minted for another subject"
never_demote "fail-open on trust boundary + fake CLI wording" build src/gate.ts \
  "the fake CLI matrix hides it, but the guard is fail-open on auth when the vendor is unset"
# correctness / data loss, worded as ephemera or coverage
never_demote "data loss on ephemera path" build HANDOFF.md \
  "handoff whitespace change erases the previous stored queue — data loss on every refresh"
never_demote "data loss in CHECKPOINT path" build CHECKPOINT.md \
  "trailing newline handling erases the prior slice record on every write"
# passive-voice data loss: no `data loss` token and no `erases the prior` token.
# This wording demoted as class:handoff-ws on path alone until the belt learned it.
never_demote "passive-voice data loss on ephemera path" build HANDOFF.md \
  "handoff whitespace normalization means the stored slice state is lost after a refresh"
never_demote "passive-voice loss of receipt" build CHECKPOINT.md \
  "trailing newline rewrite means the prior verdict is lost"
never_demote "real bug + coverage wording" build src/ui.js \
  "coverage remains incomplete; also clicking Save does nothing and the row renders NaN%"
never_demote "spec violation + docs prose" build docs/api.md \
  "documented endpoint does not exist — spec violation against the canonical spec"
# genuine test gaps / acceptance criteria
never_demote "acceptance criterion" build tests/test_x.py \
  "no real test for acceptance criterion 4; the assertion is hollow"
never_demote "AC-numbered gap + asymptotic wording" build tests/test_y.py \
  "wants more coverage, but AC 7 is not implemented and has no real assertion"
never_demote "hollow test" build tests/test_z.py \
  "hollow test: no assertion can fail when the business logic changes"
# HARDEN keeps coverage depth in charter
never_demote "coverage-asymp in HARDEN" hardening src/app.py \
  "coverage remains incomplete — wants additional coverage of the retry path"
never_demote "canary-depth in HARDEN" hardening .github/scripts/canary-x.sh \
  "dual e2e merge is unexercised in free CI; needs a live dual-vendor seat"
pass "never-demote floor holds (security, correctness, data-loss, real test gaps, HARDEN coverage)"

# ── (2) THE ASYMPTOTIC CLASSES DO DEMOTE IN BUILD (plan criterion #4) ───────
demotes_as() {
  local label="$1" phase="$2" file="$3" desc="$4" want="$5"
  local out cls; out="$(run_one "$phase" "$file" major "$desc")"
  [ "$(sev_of "$out")" = "minor" ] || fail "expected demotion ($label): $out"
  cls="$(class_of "$out")"
  [ "$cls" = "$want" ] || fail "expected $want, got '${cls:-none}' ($label): $out"
  printf '%s' "$ALLOW_JSON" | jq -e --arg c "$cls" 'index($c) != null' >/dev/null \
    || fail "demoted with class '$cls' which is NOT in the allowlist ($label)"
}
demotes_as "asymptotic coverage" build src/app.py \
  "coverage remains incomplete — wants additional coverage of the timeout path" \
  class:coverage-gap
demotes_as "dual e2e canary depth" build .github/scripts/canary-x.sh \
  "the dual e2e merge path is not free-canary; only a real PR can exercise it" \
  class:canary-depth
demotes_as "fake CLI argv matrix" build .github/scripts/canary-y.sh \
  "wants a wider fake CLI argv matrix across every vendor shim" \
  class:fake-cli-argv
demotes_as "handoff whitespace" build HANDOFF.md \
  "handoff whitespace preservation differs by one trailing newline" \
  class:handoff-ws
demotes_as "sticky ledger nit" build shared/.plinth/x.md \
  "sticky ledger lookup could collapse siblings more tidily" \
  class:sticky-ledger
demotes_as "docs prose" build docs/guide.md \
  "the prose here could be clearer about ordering" \
  class:docs-prose
demotes_as "queue nit" build NEEDS-HUMAN.md \
  "formatting nit: blank line missing between queue entries" \
  class:queue-nit
# blockers demote by the same rules (severity floor is class-driven, not severity-driven)
out_blk="$(run_one build src/app.py blocker "coverage remains incomplete — wants additional coverage of the retry path")"
[ "$(sev_of "$out_blk")" = "minor" ] || fail "an asymptotic BLOCKER should demote like a major: $out_blk"
pass "asymptotic classes demote in BUILD with an allowlisted class recorded"

# ── (3) the classifier cannot emit anything outside the allowlist ───────────
# Drive a corpus through production and assert every recorded class is allowlisted
# and every non-demotion left severity untouched.
while IFS='|' read -r ph fl ds; do
  [ -n "${ph:-}" ] || continue
  out="$(run_one "$ph" "$fl" major "$ds")"
  cls="$(class_of "$out")"
  if [ "$(sev_of "$out")" = "minor" ]; then
    [ -n "$cls" ] || fail "demoted with NO class recorded (unauditable): $out"
    printf '%s' "$ALLOW_JSON" | jq -e --arg c "$cls" 'index($c) != null' >/dev/null \
      || fail "demoted with non-allowlisted class '$cls': $out"
  else
    [ -z "$cls" ] || fail "not demoted yet a THRASH class was stamped: $out"
  fi
done <<'CORPUS'
build|src/a.py|some entirely unremarkable observation about naming
build|src/b.py|the retry loop double-counts attempts and returns the wrong total
hardening|docs/c.md|prose could be tightened
build|NEEDS-HUMAN.md|the queue entry was checked off prematurely
build|.plinth/session/x.json|session artifact wording
hardening|src/d.go|unauthenticated request reaches the admin handler
build|CHANGELOG.md|the release notes omit the behavior change
CORPUS
pass "no demotion without an allowlisted, recorded class (corpus sweep)"

# NEEDS-HUMAN "checked off prematurely" must NOT be a queue nit (it is a lost blocker)
out_nh="$(run_one build NEEDS-HUMAN.md major "the queue entry was checked off prematurely, losing a blocking item")"
[ "$(sev_of "$out_nh")" = "major" ] || fail "a checked-off/lost blocker must never demote as a queue nit: $out_nh"
# CHANGELOG is release surface, never docs-prose
out_cl="$(run_one build CHANGELOG.md major "the prose could be clearer")"
[ "$(sev_of "$out_cl")" = "major" ] || fail "CHANGELOG must not demote as docs prose: $out_cl"
pass "queue-nit and docs-prose exclusions (lost blockers, CHANGELOG release surface)"

# ── (4) minors and resolved findings are untouched ──────────────────────────
out_min="$(run_one build src/app.py minor "coverage remains incomplete")"
[ "$(sev_of "$out_min")" = "minor" ] || fail "minor should stay minor: $out_min"
[ -z "$(class_of "$out_min")" ] || fail "an already-minor finding must not be re-stamped: $out_min"
mkf src/app.py major "coverage remains incomplete" | jq '.findings[0].status="resolved"' > "$TMP/f.json"
thrash_policy_process_findings "$TMP/f.json" build "" "" SPEC.md fresh
jq -e '.findings[0].severity=="major"' "$TMP/f.json" >/dev/null \
  || fail "a resolved finding must not be rewritten"
pass "minor / resolved findings untouched"

# ── (5) the allowlist edit surface is Tier 2 (bound #2) ─────────────────────
# The vocabulary lives in shared/.plinth/review.sh, and risk-classify's TOOLING
# pattern must classify that path Tier 2 — otherwise widening the fail-open could
# ship under a Tier-1 review.
CLS="$ROOT/shared/.plinth/risk-classify.sh"
RC=$(mktemp -d)
(
  set -euo pipefail
  cd "$RC"
  git init -q; git config user.email t@t; git config user.name t
  mkdir -p shared/.plinth .plinth
  echo 'x' > shared/.plinth/review.sh
  printf 'spec_path = SPEC.md\n' > .plinth/config
  echo spec > SPEC.md
  git add -A; git commit -qm base
  # Capture the real default branch — `git init` may default to main or master,
  # and risk-classify honestly reports an unresolvable base as Tier 1, which
  # would make this assertion pass/fail for the wrong reason.
  base_branch="$(git rev-parse --abbrev-ref HEAD)"
  git checkout -qb feat/widen
  # simulate widening the demotable vocabulary
  printf 'def demotable_classes: ["class:coverage-gap","class:security-nit"];\n' >> shared/.plinth/review.sh
  git add -A; git commit -qm widen
  out="$("$CLS" "$base_branch" 2>/dev/null || true)"
  tier=$(printf '%s' "$out" | jq -r '.tier' 2>/dev/null || echo err)
  printf '%s' "$out" | jq -e '.reasons | join(" ") | test("base ref not found") | not' >/dev/null \
    || { echo "fixture base ref did not resolve — assertion would be vacuous: $out"; exit 1; }
  [ "$tier" = "2" ] || { echo "editing the demotion allowlist classified Tier $tier, expected 2: $out"; exit 1; }
)
rm -rf "$RC"
pass "editing the demotion vocabulary is Tier 2 (cross-vendor review by construction)"

echo "canary-thrash-classes: ALL PASS"
