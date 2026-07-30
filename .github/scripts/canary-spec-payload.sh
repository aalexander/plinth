#!/usr/bin/env bash
# Spec payload bound canary (v5.2).
#
# A reviewer CLI is agentic: the prompt is re-sent on every turn of its loop, so the
# inlined spec is paid ~60x per round, not once. Measured on this repo, spec_path is an
# 87KB manual (~23k tokens) and one round on a 62-line diff cost 2.73M input tokens
# while a 6,000-line diff cost 5.1M — the diff was never the driver.
#
# v5.2 sends the spec BY REFERENCE: the primary runs read-only IN the repo, so it gets
# a materialized BASE copy's path plus a heading outline instead of 23k tokens of text.
# Nothing is withheld, so there is no excerpt fail-open to bound — the earlier
# excerpt machinery was deleted rather than repaired after review round 2 found four
# defects in it, all belonging to a workaround for pasting the spec at all.
# It drives the PRODUCTION functions extracted from shared/.plinth/review.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REVIEW="$ROOT/shared/.plinth/review.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

# ── (6) BY REFERENCE: the primary gets a PATH, not the document ──────────────
# The primary reviewer runs `codex exec --sandbox read-only` IN the repo and can READ
# files; the spec was only ever inlined because the working-tree copy is PR-modifiable.
# So it now receives a materialized BASE copy's path plus a heading outline. This is
# strictly better than the excerpt: ~99% smaller AND nothing is withheld, so the
# "a requirement never reached the reviewer" fail-open does not exist on this path.
python3 - "$REVIEW" "$TMP/byref.sh" <<'PY2'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text()
i = s.index("materialize_base_spec() {")
j = s.index("inline_goal() {")
Path(sys.argv[2]).write_text(s[i:j])
PY2
# shellcheck disable=SC1090
. "$TMP/byref.sh"
type materialize_base_spec >/dev/null 2>&1 || fail "materialize_base_spec not extractable"
type _spec_outline_for_prompt >/dev/null 2>&1 || fail "_spec_outline_for_prompt not extractable"

BR=$(mktemp -d)
(
  cd "$BR" || exit 1
  git init -q -b main . >/dev/null 2>&1 || exit 1
  git config user.email t@t || exit 1; git config user.name t || exit 1
  printf '# Requirements\nThe widget MUST retry.\n## Other\nprose\n' > SPEC.md || exit 1
  git add -A || exit 1; git commit -qm base >/dev/null || exit 1
  base_tip="$(git rev-parse HEAD)"; SDIR="$BR/session"; SPEC_PATH=SPEC.md
  mkdir -p "$SDIR" || exit 1
  # The PR modifies the spec in the working tree — the materialized copy must be BASE.
  printf '# Requirements\nThe widget MUST NOT retry (tampered).\n' > SPEC.md || exit 1
  out="$(materialize_base_spec 1)"
  [ -n "$out" ] || { echo "materialize_base_spec produced no path"; exit 1; }
  [ -f "$out" ] || { echo "materialized spec is not a file: $out"; exit 1; }
  grep -q "MUST retry" "$out" || { echo "materialized copy is not the BASE spec"; exit 1; }
  grep -q "tampered" "$out" && { echo "materialized the PR WORKING-TREE spec — a PR could ship the spec that judges it"; exit 1; }
  # the outline names every heading, so nothing is invisible
  BASE_SPEC_PATH="$out"
  ol="$(_spec_outline_for_prompt)"
  printf '%s' "$ol" | grep -q "Requirements" || { echo "outline missing a heading"; exit 1; }
  printf '%s' "$ol" | grep -q "Other" || { echo "outline missing a heading"; exit 1; }
  # the outline must be far smaller than the document it points at
  [ "$(printf '%s' "$ol" | wc -c)" -lt "$(wc -c < "$out")" ] || { echo "outline is not smaller than the spec"; exit 1; }
  # unavailable base spec must be announced, never silently empty
  BASE_SPEC_PATH="" 
  printf '%s' "$(_spec_outline_for_prompt)" | grep -q "unavailable" \
    || { echo "an unavailable base spec must be announced to the reviewer"; exit 1; }
) || fail "spec-by-reference is not base-pinned/announced correctly"
# the prompt must hand over the path AND forbid the working-tree copy
grep -q 'BASE_SPEC_PATH:-<unavailable>' "$REVIEW" || fail "the prompt does not hand the reviewer the base spec path"
grep -q 'that copy is PR-modifiable' "$REVIEW" || fail "the prompt does not forbid reading the working-tree spec"
grep -q 'NOTHING is withheld from you here' "$REVIEW" || fail "the prompt must state that nothing is withheld (no excerpt fail-open on this path)"
grep -q 'BASE_SPEC_PATH="$(materialize_base_spec' "$REVIEW" || fail "run_round must materialize the base spec"
pass "primary gets the spec BY REFERENCE (base-pinned, outlined, nothing withheld)"

# ── the excerpt machinery must STAY deleted ─────────────────────────────────
for gone in _spec_select _spec_relevant_re inline_spec_file SPEC_INLINE_MAX SPEC-EXCERPT:; do
  grep -q -- "$gone" "$REVIEW" \
    && fail "excerpt machinery reintroduced ($gone) — the spec goes by reference; a compressor for a payload we no longer send is a workaround, not a feature"
done
pass "excerpt machinery stays deleted (no compressor for a payload we do not send)"

echo "canary-spec-payload: ALL PASS"
