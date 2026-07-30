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

# ── (6) DEMOTION LEDGER → receipt (v5.1 S3) ─────────────────────────────────
# The receipt is what makes the demotion fail-open auditable, so drive the REAL
# row builder (thrash_ledger_rows extracted from production) rather than a twin.
awk '
  /^thrash_ledger_rows\(\)/ {p=1}
  p {print}
  p && /^}$/ {exit}
' "$REVIEW" > "$TMP/ledger_fn.sh"
# shellcheck disable=SC1090
. "$TMP/ledger_fn.sh"
type thrash_ledger_rows >/dev/null 2>&1 || fail "thrash_ledger_rows not extractable from review.sh"

# a demoted finding produces exactly one row carrying class + from→to
mkf src/app.py major "coverage remains incomplete — wants additional coverage of the timeout path" > "$TMP/L.json"
jq -c '[.findings[] | {id: (.id // ""), severity: (.severity // ""), file: (.file // "")}]' "$TMP/L.json" > "$TMP/Lpre.json"
thrash_policy_process_findings "$TMP/L.json" build "" "" SPEC.md fresh
rows="$(thrash_ledger_rows "$TMP/L.json" "$TMP/Lpre.json" 3 build fresh)"
printf '%s' "$rows" | jq -e 'length == 1' >/dev/null || fail "expected one ledger row: $rows"
printf '%s' "$rows" | jq -e '.[0]
  | .class == "class:coverage-gap"
  and .from == "major" and .to == "minor"
  and .round == 3 and .phase == "build" and .mode == "fresh"
  and .id == "F1" and .file == "src/app.py"' >/dev/null \
  || fail "ledger row does not record class/from→to/round: $rows"
# a blocker records from=blocker (the severity it actually came from)
mkf src/app.py blocker "coverage remains incomplete — wants additional coverage of the retry path" > "$TMP/B.json"
jq -c '[.findings[] | {id: (.id // ""), severity: (.severity // ""), file: (.file // "")}]' "$TMP/B.json" > "$TMP/Bpre.json"
thrash_policy_process_findings "$TMP/B.json" build "" "" SPEC.md fresh
printf '%s' "$(thrash_ledger_rows "$TMP/B.json" "$TMP/Bpre.json" 1 build fresh)" \
  | jq -e '.[0].from == "blocker" and .[0].to == "minor"' >/dev/null \
  || fail "a demoted blocker must record from=blocker"
# nothing demoted → empty ledger (an empty array is the correct answer)
mkf src/b.py major "the retry loop double-counts attempts and returns the wrong total" > "$TMP/N.json"
jq -c '[.findings[] | {id: (.id // ""), severity: (.severity // ""), file: (.file // "")}]' "$TMP/N.json" > "$TMP/Npre.json"
thrash_policy_process_findings "$TMP/N.json" build "" "" SPEC.md fresh
[ "$(thrash_ledger_rows "$TMP/N.json" "$TMP/Npre.json" 1 build fresh)" = "[]" ] \
  || fail "a non-demoted finding must produce no ledger row"
# an unchanged severity carrying a stale marker (sticky forwards descriptions)
# must NOT re-enter the ledger on a later round
mkf src/app.py minor "coverage remains incomplete [THRASH:class:coverage-gap → minor/Noticed in BUILD]" > "$TMP/S.json"
jq -c '[.findings[] | {id: (.id // ""), severity: (.severity // ""), file: (.file // "")}]' "$TMP/S.json" > "$TMP/Spre.json"
[ "$(thrash_ledger_rows "$TMP/S.json" "$TMP/Spre.json" 4 build verify)" = "[]" ] \
  || fail "a stale THRASH marker with no severity transition must not re-enter the ledger"
# The AUDIT payload gets the same demotion policy applied (it changes the reported
# blocking count), so its demotions must reach the ledger too — otherwise "every
# demotion is disclosed on the receipt" is wider than the code. Exercise the same
# shape the production audit block uses, tagged source:"audit".
mkf docs/guide.md major "the prose here could be clearer about ordering" > "$TMP/A.json"
jq -c '[.findings[] | {id: (.id // ""), severity: (.severity // ""), file: (.file // "")}]' "$TMP/A.json" > "$TMP/Apre.json"
thrash_policy_process_findings "$TMP/A.json" build "" "" SPEC.md fresh
arows="$(thrash_ledger_rows "$TMP/A.json" "$TMP/Apre.json" 2 build audit)"
printf '%s' "$arows" | jq -e 'length == 1 and .[0].class == "class:docs-prose" and .[0].mode == "audit"' >/dev/null \
  || fail "audit-payload demotions must produce ledger rows: $arows"
printf '%s' "$arows" | jq -c '.[] + {source:"audit"}' | jq -e '.source == "audit"' >/dev/null \
  || fail "audit rows must be taggable with their source"
grep -q 'source:"audit"' "$REVIEW" \
  || fail "the production audit block must tag its demotion rows with source"
grep -q 'thrash_ledger_rows "\$afind"' "$REVIEW" \
  || fail "the production audit block must feed its demotions into the ledger"
pass "audit-payload demotions also reach the ledger (tagged source=audit)"

# the ledger is wired into mint_receipt, and refuses to mint on an unparseable one
grep -q 'demotions:\$demotions' "$REVIEW" \
  || fail "mint_receipt must fold the demotion ledger into the receipt payload"
grep -q 'demotions.jsonl' "$REVIEW" \
  || fail "the cumulative demotion ledger artifact must be read at mint time"
grep -q 'receipt NOT minted: the demotion ledger' "$REVIEW" \
  || fail "an unparseable demotion ledger must refuse to mint rather than mint an empty array"
grep -q 'thrash_ledger_rows "\$SDIR/findings-\$r.json"' "$REVIEW" \
  || fail "run_round must call the production ledger builder"
pass "demotion ledger rows (class, from→to, no stale re-entry) + receipt wiring"

# ── (7) receipt-verify bounds the ledger SHAPE but never requires it ─────────
VERIFY="$ROOT/shared/.plinth/receipt-verify.sh"
# Pull the jq schema program out of the verifier and drive it directly: the full
# script needs a PR context (head sha, repo, network), but the schema conjunction
# is the part that must accept old receipts and reject malformed ledgers.
python3 - "$VERIFY" "$TMP/schema.jq" <<'PY'
from pathlib import Path
import re, sys
src = Path(sys.argv[1]).read_text()
m = re.search(r"jq -e '\n(.*?)\n' \"\$RECEIPT\"", src, re.S)
if not m:
    raise SystemExit("could not extract the receipt schema jq program from receipt-verify.sh")
Path(sys.argv[2]).write_text(m.group(1) + "\n")
PY
[ -s "$TMP/schema.jq" ] || fail "empty schema extraction"
base_receipt='{"schema":"plinth.review-receipt/v1","repo":"o/r",
  "head_sha":"'"$(printf 'a%.0s' $(seq 40))"'",
  "head_tree_sha":"'"$(printf 'b%.0s' $(seq 40))"'",
  "base_ref":"main","merge_base_sha":"'"$(printf 'c%.0s' $(seq 40))"'",
  "subject_digest":"sha256:'"$(printf 'd%.0s' $(seq 64))"'",
  "verdict":"APPROVED","round":2,"override_ledger":[]}'
schema_ok() { printf '%s' "$1" | jq -e --from-file "$TMP/schema.jq" >/dev/null 2>&1; }
# a pre-v5.1 receipt with NO demotions field still verifies (fail-open on old)
schema_ok "$base_receipt" || fail "a receipt without a demotions field must still verify"
# a valid ledger verifies
schema_ok "$(printf '%s' "$base_receipt" | jq -c '.demotions = [{round:1,id:"F1",file:"a.py",class:"class:coverage-gap",from:"major",to:"minor",phase:"build",mode:"fresh"}]')" \
  || fail "a well-formed demotion ledger must verify"
# an empty ledger verifies
schema_ok "$(printf '%s' "$base_receipt" | jq -c '.demotions = []')" \
  || fail "an empty demotion ledger must verify"
# malformed ledgers are rejected — a receipt must not disclose demotions in a
# form the reader cannot audit
schema_reject() {
  local label="$1" filter="$2"
  ! schema_ok "$(printf '%s' "$base_receipt" | jq -c "$filter")" \
    || fail "receipt schema accepted a malformed demotion ledger ($label)"
}
schema_reject "not an array"        '.demotions = {}'
schema_reject "class not namespaced" '.demotions = [{round:1,id:"F1",file:"a.py",class:"coverage-gap",from:"major",to:"minor"}]'
schema_reject "class empty"          '.demotions = [{round:1,id:"F1",file:"a.py",class:"",from:"major",to:"minor"}]'
schema_reject "missing from"         '.demotions = [{round:1,id:"F1",file:"a.py",class:"class:coverage-gap",to:"minor"}]'
schema_reject "empty to"             '.demotions = [{round:1,id:"F1",file:"a.py",class:"class:coverage-gap",from:"major",to:""}]'
schema_reject "round not a number"   '.demotions = [{round:"1",id:"F1",file:"a.py",class:"class:coverage-gap",from:"major",to:"minor"}]'
schema_reject "uppercase class"      '.demotions = [{round:1,id:"F1",file:"a.py",class:"class:Coverage",from:"major",to:"minor"}]'
pass "receipt-verify bounds the demotion ledger shape, never requires the field"

echo "canary-thrash-classes: ALL PASS"
