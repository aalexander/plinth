#!/usr/bin/env bash
# Entry-point tests for diff_digest fallback and receipt-verify base canon.
set -euo pipefail
ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/../.." && pwd)}"
# 1) Production probes exist
grep -q 'command -v shasum' "$ROOT/shared/.plinth/review.sh"
grep -q 'command -v sha256sum' "$ROOT/shared/.plinth/review.sh"
grep -q 'b#refs/remotes/' "$ROOT/shared/.plinth/receipt-verify.sh"
# 2) review.sh entry-point with PATH that has sha256sum but not shasum
BIN="$(mktemp -d)"
printf '%s\n' '#!/bin/sh' 'echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' > "$BIN/sha256sum"
chmod +x "$BIN/sha256sum"
for b in bash sh cat cut git jq sed awk tr mkdir date env rm ls cp mv chmod ln head printf tail grep mktemp basename dirname uname; do
  s="$(command -v "$b" 2>/dev/null || true)"
  [ -n "$s" ] && ln -sf "$s" "$BIN/" 2>/dev/null || true
done
RDIR="$(mktemp -d)"
(
  cd "$RDIR"
  git init -q -b main; git config user.email t@x; git config user.name t
  "$ROOT/bin/plinth" init "$RDIR" >/dev/null 2>&1
  cp "$ROOT/shared/.plinth/review.sh" .plinth/review.sh
  cp "$ROOT/shared/.plinth/risk-classify.sh" .plinth/risk-classify.sh
  git remote add origin https://github.com/owner/repo.git
  echo REQ > SPEC.md; git add -A; git commit -qm base >/dev/null
  git checkout -qb feat >/dev/null 2>&1
  echo a > app.py; git add -A; git commit -qm c1 >/dev/null
  M="$(mktemp -d)"
  printf '%s\n' \
    '#!/bin/sh' \
    'out=""; prev=""' \
    'for a in "$@"; do if [ "$prev" = "-o" ]; then out="$a"; fi; prev="$a"; done' \
    'cat >/dev/null' \
    'if [ -n "$out" ]; then printf %s "{\"verdict\":\"APPROVED\",\"summary\":\"s\",\"findings\":[]}" > "$out"; fi' \
    'echo "{\"type\":\"thread.started\",\"thread_id\":\"d\"}"' \
    'echo "{\"type\":\"turn.completed\",\"usage\":{\"input_tokens\":1}}"' \
    > "$M/codex"
  chmod +x "$M/codex"
  rc=0
  OUTF="$(mktemp)"; PATH="$BIN:$M" ./.plinth/review.sh main >"$OUTF" 2>&1 || rc=$?
  [ "$rc" = 0 ] || { echo "::error::review.sh rc=$rc without shasum: $(tail -c 500 "$OUTF")"; exit 1; }
  dig="$(jq -r .diff_digest .plinth/session/review/feat/verdict.json)"
  [ -n "$dig" ] && [ "$dig" != "null" ] || { echo "::error::empty diff_digest"; exit 1; }
  echo "OK review.sh entry-point digest without shasum"
)
# 3) receipt-verify four base forms
VDIR="$(mktemp -d)"
(
  cd "$VDIR"
  git init -q -b main; git config user.email t@x; git config user.name t
  echo x > f; git add -A; git commit -qm b >/dev/null
  H="$(git rev-parse HEAD)"; HT="$(git rev-parse HEAD^{tree})"; MB="$H"
  if command -v shasum >/dev/null 2>&1; then
    SD="$(printf 'plinth-review-subject-v1\0%s\0%s\0%s\0%s\0%s\0' owner/repo main "$MB" "$H" "$HT" | shasum -a 256 | awk '{print $1}')"
  else
    SD="$(printf 'plinth-review-subject-v1\0%s\0%s\0%s\0%s\0%s\0' owner/repo main "$MB" "$H" "$HT" | sha256sum | awk '{print $1}')"
  fi
  jq -n --arg h "$H" --arg ht "$HT" --arg mb "$MB" --arg sd "sha256:$SD" \
    '{schema:"plinth.review-receipt/v1",repo:"owner/repo",base_ref:"main",merge_base_sha:$mb,head_sha:$h,head_tree_sha:$ht,subject_digest:$sd,verdict:"APPROVED",round:1,override_ledger:[]}' > rec.json
  : > body.txt
  cp "$ROOT/shared/.plinth/receipt-verify.sh" ./rv.sh; chmod +x ./rv.sh
  for form in main origin/main refs/heads/main refs/remotes/origin/main; do
    set +e
    out="$(./rv.sh --receipt rec.json --head-sha "$H" --base-ref "$form" --base-tip "$H" --pr-body body.txt --repo owner/repo 2>&1)"
    rc=$?
    set -e
    [ "$rc" = 0 ] || { echo "::error::receipt-verify failed for $form: $out"; exit 1; }
  done
  echo "OK receipt-verify entry-point for four base spellings"
  # 3b) receipt-verify on a sha256sum-only PATH (no shasum). Section 2 already forces
  # review.sh onto that class of host; the server verifier's fallback must not be the
  # only unexercised sibling — ambient PATH often has shasum and would hide a regression.
  RBIN="$(mktemp -d)"
  for b in bash sh cat cut git jq sed awk tr mkdir date env rm ls cp mv chmod ln head \
           printf tail grep mktemp basename dirname uname wc sha256sum; do
    s="$(command -v "$b" 2>/dev/null || true)"
    [ -n "$s" ] && ln -sf "$s" "$RBIN/" 2>/dev/null || true
  done
  command -v sha256sum >/dev/null 2>&1 || { echo "::error::host has no sha256sum — cannot force receipt-verify fallback"; exit 1; }
  [ -x "$RBIN/sha256sum" ] || { echo "::error::curated PATH missing sha256sum"; exit 1; }
  [ ! -e "$RBIN/shasum" ] || { echo "::error::curated PATH must not expose shasum"; exit 1; }
  set +e
  out="$(PATH="$RBIN" ./rv.sh --receipt rec.json --head-sha "$H" --base-ref main --base-tip "$H" --pr-body body.txt --repo owner/repo 2>&1)"
  rc=$?
  set -e
  [ "$rc" = 0 ] || { echo "::error::receipt-verify failed on sha256sum-only PATH (rc=$rc): $out"; exit 1; }
  echo "OK receipt-verify entry-point without shasum (sha256sum fallback)"
)
echo "OK canary-digest-base.sh"
