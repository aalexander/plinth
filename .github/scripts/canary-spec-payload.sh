#!/usr/bin/env bash
# Spec payload bound canary (v5.2).
#
# A reviewer CLI is agentic: the prompt is re-sent on every turn of its loop, so the
# inlined spec is paid ~60x per round, not once. Measured on this repo, spec_path is an
# 87KB manual (~23k tokens) and one round on a 62-line diff cost 2.73M input tokens
# while a 6,000-line diff cost 5.1M — the diff was never the driver.
#
# Excerpting a spec is a FAIL-OPEN: a requirement that never reaches the reviewer
# cannot be enforced. This canary is the bound on that. If it passes:
#   1. a spec at or below the cap is sent VERBATIM (ordinary projects unaffected);
#   2. above the cap the reviewer is told LOUDLY that it holds an excerpt, and that
#      absence is not evidence — with a named escape hatch;
#   3. the COMPLETE heading outline is always sent, so nothing is invisible;
#   4. omitted sections are named, not silently dropped;
#   5. the byte cap actually binds — the guarantee cannot rest on regex quality.
# It drives the PRODUCTION functions extracted from shared/.plinth/review.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REVIEW="$ROOT/shared/.plinth/review.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

# ── extract the production functions (no re-implementation) ─────────────────
python3 - "$REVIEW" "$TMP/specfns.sh" <<'PY'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text()
i = s.index("SPEC_INLINE_MAX_DEFAULT=")
j = s.index("inline_goal() {")
Path(sys.argv[2]).write_text(s[i:j])
PY
# shellcheck disable=SC1090
. "$TMP/specfns.sh"
for fn in _spec_relevant_re _spec_select inline_spec_file inline_spec; do
  type "$fn" >/dev/null 2>&1 || fail "$fn not extractable from review.sh"
done
[ -n "${SPEC_INLINE_MAX_DEFAULT:-}" ] || fail "SPEC_INLINE_MAX_DEFAULT not extractable"

# ── (1) at/below the cap → VERBATIM (no behaviour change for normal specs) ──
small="$TMP/small.md"
{ echo "# Requirements"; echo "The widget MUST retry."; } > "$small"
REVIEWED_FILES_FULL="src/widget.py"
SPEC_PATH="$small"
out="$(inline_spec)"
printf '%s' "$out" | grep -q "EXCERPTED" && fail "a small spec must be sent verbatim, not excerpted"
[ "$(printf '%s' "$out")" = "$(cat "$small")" ] || fail "small spec was altered: $out"
pass "spec at/below the cap is sent verbatim"

# ── (2)(3)(4)(5) above the cap → honest, outlined, capped excerpt ───────────
big="$TMP/big.md"
: > "$big"
i=0
while [ "$i" -lt 40 ]; do
  printf '## Section %s\n' "$i" >> "$big"
  printf 'Filler prose about unrelated matters. %s\n' "$(head -c 700 < /dev/zero | tr '\0' 'x')" >> "$big"
  i=$((i + 1))
done
printf '## Acceptance criteria\nThe retry path MUST return failure.\n' >> "$big"
printf '## Widget interface\nsrc/widget.py exposes retry().\n' >> "$big"
total=$(wc -c < "$big" | tr -d '[:space:]')
[ "$total" -gt "$SPEC_INLINE_MAX_DEFAULT" ] || fail "fixture spec ($total B) must exceed the cap to test excerpting"
SPEC_PATH="$big"
out="$(inline_spec)"
n_out=$(printf '%s' "$out" | wc -c | tr -d '[:space:]')

# the cap actually binds
[ "$n_out" -lt "$total" ] || fail "excerpt ($n_out B) is not smaller than the spec ($total B) — the cap does not bind"
# and the reduction is material, not cosmetic
[ "$n_out" -lt $(( total * 80 / 100 )) ] || fail "excerpt is >=80% of the spec ($n_out/$total) — no material reduction"
# honesty: the reviewer must KNOW it holds an excerpt and that absence proves nothing
printf '%s' "$out" | grep -q "SPEC EXCERPTED" || fail "excerpt lacks the loud banner"
printf '%s' "$out" | grep -q "ABSENCE OF A SECTION BELOW IS NOT EVIDENCE" \
  || fail "excerpt lacks the fail-open warning — a reviewer could read absence as 'not specified'"
printf '%s' "$out" | grep -q "SPEC-EXCERPT:" || fail "excerpt lacks the named escape hatch for the reviewer"
printf '%s' "$out" | grep -q "PLINTH_SPEC_INLINE_MAX=0" || fail "excerpt does not say how to get the whole document"
# the COMPLETE outline is always present, so no heading is invisible
want=$(grep -cE '^#{1,6} ' "$big")
got=$(printf '%s' "$out" | sed -n '/COMPLETE HEADING OUTLINE/,/INCLUDED SECTIONS/p' | grep -cE ':#{1,6} ')
[ "$want" = "$got" ] || fail "outline sent $got of $want headings — a heading would be invisible"
# requirement-shaped sections survive selection
printf '%s' "$out" | grep -q "The retry path MUST return failure" \
  || fail "an 'Acceptance criteria' section was dropped — requirement-bearing sections must be kept"
# diff-relevant sections survive selection
printf '%s' "$out" | grep -q "exposes retry()" \
  || fail "a section naming a file in the diff was dropped"
# omissions are NAMED, never silent
printf '%s' "$out" | grep -qE "NOT SELECTED|DROPPED AT THE CAP" \
  || fail "sections were omitted without naming them"
pass "excerpt is loud, outlined in full, keeps requirements + diff-relevant sections, names omissions"

# ── the escape hatch really disables excerpting ─────────────────────────────
# Compare via a FILE: command substitution strips trailing newlines, which would make
# a byte-for-byte assertion fail for a reason that has nothing to do with the product.
PLINTH_SPEC_INLINE_MAX=0 inline_spec > "$TMP/full.out"
grep -q "EXCERPTED" "$TMP/full.out" && fail "PLINTH_SPEC_INLINE_MAX=0 must send the whole document"
cmp -s "$TMP/full.out" "$big" || fail "PLINTH_SPEC_INLINE_MAX=0 did not reproduce the spec byte-for-byte"
# a garbage cap falls back to the default rather than disabling the bound silently
out_bad="$(PLINTH_SPEC_INLINE_MAX=banana inline_spec)"
printf '%s' "$out_bad" | grep -q "SPEC EXCERPTED" \
  || fail "an invalid PLINTH_SPEC_INLINE_MAX silently disabled the bound (must fall back to the default)"
pass "PLINTH_SPEC_INLINE_MAX=0 sends the whole spec; an invalid value falls back to the default"

# ── a generic basename must not select the entire document ──────────────────
# `bin/plinth` → basename `plinth` matched nearly every line of this repo's own manual,
# which selected everything and produced a 0% reduction. Distinctive tokens only.
REVIEWED_FILES_FULL="bin/plinth"
re="$(cd "$ROOT" && _spec_relevant_re)"
printf '%s' "$re" | grep -qx "plinth" \
  && fail "the project's own name is used as a selection token — it matches everything"
pass "selection tokens exclude the project name (no whole-document selection)"

echo "canary-spec-payload: ALL PASS"
