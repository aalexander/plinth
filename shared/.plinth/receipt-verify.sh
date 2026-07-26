#!/usr/bin/env bash
# receipt-verify.sh — server-side verifier for the APPROVED-at-HEAD review receipt
# (auto mode, v4.7). Verifies that a plinth.review-receipt/v1 git note minted by
# review.sh matches the PR's exact subject: head commit, head tree, merge base,
# and the canonical subject digest — and that every operator override recorded
# in the receipt's ledger is disclosed in the PR body (tuple-set equality).
#
# DETERMINISTIC AND OFFLINE: no network, no GitHub API — the calling workflow
# supplies the event facts and does its own TOCTOU re-fetch just before success.
# Runnable locally too: drivers can self-check a receipt before pushing.
#
# Usage:
#   receipt-verify.sh --receipt FILE --head-sha SHA --base-ref REF \
#                     --base-tip SHA --pr-body FILE --repo OWNER/NAME
#
# Exit codes (fail closed — the caller must NEVER treat nonzero as skippable):
#   0  receipt verified: APPROVED at exactly this head, overrides disclosed
#   1  receipt absent/malformed/stale/non-APPROVED/mismatched/undisclosed override
#   2  verifier infrastructure failure (bad invocation, missing tool/object)
#
# HONEST BOUND (same trust model as the rest of Plinth): this proves a receipt
# was minted for exactly this subject and its ledger is disclosed — a driver
# that fabricates a whole receipt without running the loop defeats it. The gate
# makes skipping DETECTABLE AND AUDITABLE (the receipt is append-only history a
# human can audit against session state), not cryptographically impossible.
set -u

RECEIPT="" HEAD_SHA="" BASE_REF="" BASE_TIP="" PR_BODY="" REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --receipt)  RECEIPT="${2:-}";  shift 2 || exit 2 ;;
    --head-sha) HEAD_SHA="${2:-}"; shift 2 || exit 2 ;;
    --base-ref) BASE_REF="${2:-}"; shift 2 || exit 2 ;;
    --base-tip) BASE_TIP="${2:-}"; shift 2 || exit 2 ;;
    --pr-body)  PR_BODY="${2:-}";  shift 2 || exit 2 ;;
    --repo)     REPO="${2:-}";     shift 2 || exit 2 ;;
    *) echo "receipt-verify: unknown argument: $1" >&2; exit 2 ;;
  esac
done

fail() { echo "RECEIPT FAIL: $1" >&2; exit 1; }
infra() { echo "RECEIPT INFRA: $1" >&2; exit 2; }

command -v jq  >/dev/null 2>&1 || infra "jq not found"
command -v git >/dev/null 2>&1 || infra "git not found"
# sha256 tool: probe FIRST, never rely on a dead fallback (upstream #30 class).
if command -v shasum >/dev/null 2>&1; then sha256() { shasum -a 256 | cut -d' ' -f1; }
elif command -v sha256sum >/dev/null 2>&1; then sha256() { sha256sum | cut -d' ' -f1; }
else infra "no shasum or sha256sum on PATH"; fi

[ -n "$RECEIPT" ] && [ -n "$HEAD_SHA" ] && [ -n "$BASE_REF" ] && [ -n "$BASE_TIP" ] \
  && [ -n "$PR_BODY" ] && [ -n "$REPO" ] || infra "missing required argument (see --help header)"
[ -f "$PR_BODY" ] || infra "PR body file not readable: $PR_BODY"
[ -f "$RECEIPT" ] || fail "no receipt found for ${HEAD_SHA} — run the review loop to APPROVED and push refs/notes/plinth-receipts alongside the branch"

# ── 1. Strict schema, bounded size, allowlisted override names ──────────────
rsize=$(wc -c < "$RECEIPT" 2>/dev/null | tr -d '[:space:]') || infra "cannot stat receipt"
case "$rsize" in ''|*[!0-9]*) infra "cannot size receipt" ;; esac
[ "$rsize" -le 65536 ] || fail "receipt exceeds 64KB bound (${rsize} bytes)"
jq -e '
  (.schema == "plinth.review-receipt/v1")
  and (.repo | type == "string" and length > 0)
  and (.head_sha | type == "string" and test("^[0-9a-f]{40}$"))
  and (.head_tree_sha | type == "string" and test("^[0-9a-f]{40}$"))
  and (.base_ref | type == "string" and length > 0)
  and (.merge_base_sha | type == "string" and test("^[0-9a-f]{40}$"))
  and (.subject_digest | type == "string" and test("^sha256:[0-9a-f]{64}$"))
  and (.verdict | type == "string")
  and (.round | type == "number")
  and (.override_ledger | type == "array" and (
        map(
          (type == "object")
          and (.round | type == "number")
          and (.name | type == "string" and IN("PLINTH_REVIEWER_VENDOR","PLINTH_REVIEWER_MODEL","PLINTH_AUDIT_VENDOR","PLINTH_AUDIT_MODEL","PLINTH_ROUND_CAP"))
          and (.value | type == "string" and length <= 128 and test("^\\S+$"))
        ) | all))
' "$RECEIPT" > /dev/null 2>&1 || fail "receipt is not a valid plinth.review-receipt/v1 (schema/bounds/override-allowlist; override values must be non-empty and whitespace-free)"

r() { jq -r ".$1" "$RECEIPT"; }

# ── 2. Head binding: the receipt is for exactly this PR head ────────────────
[ "$(r head_sha)" = "$HEAD_SHA" ] || fail "receipt head_sha $(r head_sha) != PR head ${HEAD_SHA} — the approved commit is not what this PR ships; re-run the loop at HEAD"
git cat-file -e "${HEAD_SHA}^{commit}" 2>/dev/null || infra "PR head object ${HEAD_SHA} not present in this checkout (fetch depth?)"

# ── 3. Repo + base-ref binding ───────────────────────────────────────────────
# Compare (and later digest) the repo NWO CASE-INSENSITIVELY. GitHub owner/repo
# names route case-insensitively, but `=` and the sha256 subject digest are both
# case-sensitive — so a remote written `git@github.com:MyOrg/Repo.git` would never
# match `${{ github.repository }}`'s canonical `myorg/repo` and a legitimate PR
# would fail closed. review.sh lowercases the minted field identically; the two
# MUST stay in lockstep, since $REPO is folded into the digest at step 6.
REPO="$(printf '%s' "$REPO" | tr '[:upper:]' '[:lower:]')"
# Do NOT interpolate the recorded or expected repo values into the failure text:
# owner/repo is repository identity (and may embed a secret-looking path segment
# from an unsupported origin form). Name the field and how to inspect it locally.
[ "$(r repo | tr '[:upper:]' '[:lower:]')" = "$REPO" ] \
  || fail "receipt repo field does not match the PR repository — inspect the receipt note locally (git notes --ref=plinth-receipts show <head>) and re-run the loop if origin names a different repository"
# Match review.sh canon_base: refs/heads/, refs/remotes/, origin/ in that order.
canon_base() { local b="${1:-}"; b="${b#refs/heads/}"; b="${b#refs/remotes/}"; b="${b#origin/}"; printf '%s' "$b"; }
rbase="$(canon_base "$(r base_ref)")"; nbase="$(canon_base "$BASE_REF")"
[ "$rbase" = "$nbase" ] || fail "receipt base_ref '$(r base_ref)' != PR base '${BASE_REF}' (canonical: '${rbase}' vs '${nbase}')"

# ── 4. Tree binding ──────────────────────────────────────────────────────────
htree=$(git rev-parse "${HEAD_SHA}^{tree}" 2>/dev/null) || infra "cannot resolve head tree"
[ "$(r head_tree_sha)" = "$htree" ] || fail "receipt head_tree_sha does not match the PR head's tree"

# ── 5. Merge-base binding ────────────────────────────────────────────────────
git cat-file -e "${BASE_TIP}^{commit}" 2>/dev/null || infra "base tip ${BASE_TIP} not present (fetch depth?)"
mb=$(git merge-base "$BASE_TIP" "$HEAD_SHA" 2>/dev/null) || fail "no merge base between ${BASE_TIP} and ${HEAD_SHA}"
[ "$(r merge_base_sha)" = "$mb" ] || fail "receipt merge_base_sha $(r merge_base_sha) != actual merge base ${mb} — the base moved past the reviewed subject; re-run the loop"

# ── 6. Canonical subject digest (object identities, not patch bytes) ────────
subj=$(printf 'plinth-review-subject-v1\0%s\0%s\0%s\0%s\0%s\0' \
  "$REPO" "$nbase" "$mb" "$HEAD_SHA" "$htree" | sha256) || infra "digest computation failed"
[ "$(r subject_digest)" = "sha256:${subj}" ] || fail "subject digest mismatch — receipt was not minted for this exact subject"

# ── 7. Verdict ───────────────────────────────────────────────────────────────
[ "$(r verdict)" = "APPROVED" ] || fail "receipt verdict is '$(r verdict)', not APPROVED"

# ── 8. Override disclosure: exact tuple-set equality with the PR body ───────
# The PR body must carry one disclosure line per ledger tuple, in the canonical
# form `PLINTH-OVERRIDE: NAME=VALUE (round N)`, and no disclosure lines that the
# ledger does not back (a phantom disclosure is as suspect as a missing one).
# The `[^ ]*` value group below can only match a whitespace-free value — which is
# why the schema above REQUIRES one. Without that constraint a legitimately
# disclosed value containing a space would fail to match here and be reported as
# an UNDISCLOSED override: a false positive with a misleading reason. Now such a
# receipt is rejected at the schema stage, which says what is actually wrong.
# NOTE for PR authors: this greps the WHOLE body, so a literal example of the
# disclosure form (with a real name and digits) reads as a phantom disclosure.
# Document the format with a non-digit placeholder.
lset=$(jq -r '.override_ledger[] | "PLINTH-OVERRIDE: \(.name)=\(.value) (round \(.round))"' "$RECEIPT" | sort -u)
bset=$(grep -o 'PLINTH-OVERRIDE: [A-Z_]*=[^ ]* (round [0-9]*)' "$PR_BODY" 2>/dev/null | sort -u || true)
if [ "$lset" != "$bset" ]; then
  echo "--- ledger requires ---" >&2; printf '%s\n' "$lset" >&2
  echo "--- PR body declares ---" >&2; printf '%s\n' "$bset" >&2
  fail "override disclosure mismatch: the PR body's PLINTH-OVERRIDE lines must equal the receipt ledger exactly"
fi

echo "RECEIPT OK: APPROVED at ${HEAD_SHA} (round $(r round), subject sha256:${subj}, $(jq -r '.override_ledger | length' "$RECEIPT") override(s) disclosed)"
exit 0
