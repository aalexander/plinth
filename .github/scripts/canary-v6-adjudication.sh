#!/usr/bin/env bash
# v6 adjudication receipt canary.
#
# v6: the reviewer ADVISES, the driver ADJUDICATES on the record, CI GATES. The receipt
# stops asserting "a model approved this" and starts asserting WHAT HAPPENED. That is
# only an improvement if a bad dismissal is VISIBLE — so this canary exists to prove the
# audit trail cannot be hollowed out. If it passes:
#   1. pre-v6 APPROVED receipts still verify (no flag day);
#   2. an ADJUDICATED receipt verifies ONLY with per-finding dispositions;
#   3. a dismissal or deferral with no real reason is REJECTED — a shrug is not a
#      judgement, and "dismissed" with an empty reason is exactly the silent drop the
#      whole design replaces;
#   4. an unknown disposition or an empty adjudication list is rejected.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERIFY="$ROOT/shared/.plinth/receipt-verify.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

python3 - "$VERIFY" "$TMP/schema.jq" <<'PY'
from pathlib import Path
import re, sys
src = Path(sys.argv[1]).read_text()
m = re.search(r"jq -e '\n(.*?)\n' \"\$RECEIPT\"", src, re.S)
if not m: raise SystemExit("could not extract the receipt schema program")
Path(sys.argv[2]).write_text(m.group(1) + "\n")
PY
[ -s "$TMP/schema.jq" ] || fail "empty schema extraction"

H=$(printf 'a%.0s' $(seq 40)); T=$(printf 'b%.0s' $(seq 40)); M=$(printf 'c%.0s' $(seq 40)); D=$(printf 'd%.0s' $(seq 64))
base="{\"schema\":\"plinth.review-receipt/v1\",\"repo\":\"o/r\",\"head_sha\":\"$H\",\"head_tree_sha\":\"$T\",\"base_ref\":\"main\",\"merge_base_sha\":\"$M\",\"subject_digest\":\"sha256:$D\",\"verdict\":\"APPROVED\",\"round\":2,\"override_ledger\":[]}"
ok()  { printf '%s' "$base" | jq -c "$1" | jq -e --from-file "$TMP/schema.jq" >/dev/null 2>&1; }
rej() { ! ok "$1"; }

ok '.' || fail "a pre-v6 APPROVED receipt (no basis field) must still verify"
pass "pre-v6 APPROVED receipts still verify (no flag day)"

ADJ='[{"id":"F1","severity":"major","disposition":"fixed"},{"id":"F2","severity":"major","disposition":"dismissed","reason":"asks for a live two-vendor seat that does not exist"}]'
ok ".verdict=\"ADJUDICATED\" | .basis=\"adjudicated\" | .adjudications=$ADJ" \
  || fail "a well-formed ADJUDICATED receipt must verify"
pass "ADJUDICATED receipt with per-finding dispositions verifies"

rej '.verdict="ADJUDICATED" | .basis="adjudicated" | .adjudications=[{"id":"F1","severity":"major","disposition":"dismissed","reason":"nah"}]' \
  || fail "a dismissal with a 3-char reason was ACCEPTED — the audit trail can be hollowed out"
rej '.verdict="ADJUDICATED" | .basis="adjudicated" | .adjudications=[{"id":"F1","severity":"major","disposition":"dismissed"}]' \
  || fail "a dismissal with NO reason was accepted"
rej '.verdict="ADJUDICATED" | .basis="adjudicated" | .adjudications=[{"id":"F1","severity":"major","disposition":"deferred","reason":"later"}]' \
  || fail "a deferral with a weak reason was accepted"
pass "dismissed/deferred without a real reason are REJECTED (a shrug is not a judgement)"

rej '.verdict="ADJUDICATED" | .basis="adjudicated" | .adjudications=[]' || fail "an empty adjudication list was accepted"
rej '.verdict="ADJUDICATED" | .basis="adjudicated" | .adjudications=[{"id":"F1","severity":"major","disposition":"ignored","reason":"because I said so and this is long"}]' \
  || fail "an unknown disposition was accepted"
rej '.verdict="ADJUDICATED" | .basis="adjudicated" | .adjudications=[{"id":"","severity":"major","disposition":"fixed"}]' \
  || fail "an adjudication with an empty id was accepted"
rej '.basis="nonsense"' || fail "an unknown basis was accepted"
pass "empty list, unknown disposition, empty id and unknown basis are all rejected"

echo "canary-v6-adjudication: ALL PASS"
