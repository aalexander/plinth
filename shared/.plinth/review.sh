#!/usr/bin/env bash
# Plinth adversarial review (shared, version-pinned; v3.12). Read-only review of
# committed work on the current branch vs base, by the second model, recording
# a SHA-bound structured verdict that hooks/CI/humans can consume.
# Reviewer model is set in ~/.codex/config.toml — swap it there.
#
# Fix-verification rounds resume the prior reviewer session with the
# INCREMENTAL diff only. If the thread is too large to resume safely
# (PLINTH_RESUME_MAX input tokens; default 650000 ≈ 65% of GPT-5.5's 1,005,000
# window — revisit on reviewer swap, see MODELS.md), the anchor commit is gone,
# or the resume itself fails, the round falls back to a VERIFY round (prior findings
# + the FULL diff — thorough but anchored on those findings, so it does NOT bind on
# its own) — or a clean-slate full review when there are no prior findings to verify.
# Either way an approval still gets a clean-slate full confirmation before it binds,
# so the loop can never deadlock on a dead thread.
#
# Protocol files under .plinth/session/review/ (self-gitignored, per-task):
#   request-<n>.json   what round n reviewed {sha, base_ref, round, mode, ts}
#   findings-<n>.json  reviewer output for round n {verdict, summary, findings[]}
#   verdict.json       latest verdict {verdict, sha, base_ref, round, session_id, usage, ts}
#   events-<n>.jsonl   raw codex event stream (debug)
#
# Exit codes: 0 = APPROVED at HEAD. 1 = CHANGES_NEEDED — fix, commit, re-run.
#             2 = the review DID NOT RUN; never treat as a pass.
set -euo pipefail

base="${1:-main}"
SCHEMA=".plinth/review-schema.json"
# Session state is keyed by branch so parallel branches/sessions don't fight
# over verdicts. SDIR is set after the git checks below.
SDIR=""
die() { echo "PLINTH REVIEW FAILED: $*" >&2; exit 2; }
# Infrastructure failure (broken pipeline, NOT loop discipline): recorded so the
# review gate releases the session instead of trapping it on something only the
# human can fix. Discipline refusals (dirty tree, empty diff, unchanged HEAD)
# use plain die — they must NOT open the gate.
die_infra() {
  { mkdir -p "$SDIR" && printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" > "$SDIR/last-error"; } 2>/dev/null || true
  die "$@"
}

# NB: the codex CLI is required only for a model round (Tier 1/2); the check is
# deferred to just before the first round so a Tier-0 (deterministic-floor)
# approval genuinely needs no model infrastructure.
command -v jq    >/dev/null 2>&1 || die_infra "jq not found"
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
[ -f "$SCHEMA" ] || die_infra "missing $SCHEMA — run 'plinth update' on this project"

# Reviews are SHA-bound. A dirty tree means the diff below would not match the
# work — the old silent-false-pass path. Refuse instead. Exemption: the
# NEEDS-HUMAN queue (this script appends to it; it is a human channel, not
# reviewable code — the driver commits it with its next real commit).
[ -z "$(git status --porcelain | grep -vE '\.plinth/NEEDS-HUMAN\.md$')" ] \
  || die "working tree is dirty — commit (or stash) first; the verdict binds to a commit SHA"

sha="$(git rev-parse HEAD)"

# Resolve the base ref explicitly; never fall through to an empty diff.
if git rev-parse --verify --quiet "origin/${base}" >/dev/null; then baseref="origin/${base}"
elif git rev-parse --verify --quiet "${base}" >/dev/null; then baseref="${base}"
else die_infra "base ref '${base}' not found (tried origin/${base} and ${base})"
fi

diff="$(git diff "${baseref}...HEAD")" || die_infra "git diff ${baseref}...HEAD failed"
[ -n "$diff" ] || die "empty diff against ${baseref} at ${sha} — nothing would be reviewed. Commit your work or pass the right base branch."

# Per-project config (.plinth/config — agent-immutable via protected-paths):
#   spec_path    canonical spec (file or directory)
#   exec_gated   grep -E patterns (space-separated) for execution-gated paths;
#                RUNTIME: findings on these don't block — they join the run gate
#   round_budget advisory warning threshold for per-round input tokens
#                (default 4000000; warns and continues — never blocks)
#   audit_vendor a DIFFERENT-vendor CLI for the cross-vendor second opinion; the
#                audit runs only when audit_vendor != codex (the primary reviewer),
#                on every Tier-2 approval (and every 5th otherwise). Disagreement
#                reported, not adjudicated.
#   audit_model  optional MODEL OVERRIDE for audit_vendor (not a trigger)
cfg() { sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" .plinth/config 2>/dev/null | head -1; }
# Reviewer model (for the dashboard): whatever codex actually runs — the model
# line in ~/.codex/config.toml. Recorded in verdict.json so watch can show it
# alongside the driver model without reading the user's codex config.
# `|| true`: sed exits non-zero when the config is ABSENT, and under
# `set -o pipefail` that would abort the whole review here — before the Tier-0
# gate, which needs no codex config at all. Absent/unset just falls back to "codex".
REVIEWER_MODEL="$(sed -n 's/^model[[:space:]]*=[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' "${CODEX_HOME:-$HOME/.codex}/config.toml" 2>/dev/null | head -1 || true)"
[ -n "$REVIEWER_MODEL" ] || REVIEWER_MODEL="codex"
# spec_path from the BASE config (like risk-classify.sh): a PR must not repoint the
# review target to a weaker/empty spec in its own diff. Read the base config with
# `|| true` FIRST — under set -euo pipefail a failing `git show` (base has no
# .plinth/config: first spec / new project) would abort before the fallback runs.
basecfg="$(git show "${baseref}:.plinth/config" 2>/dev/null || true)"
# bcfg reads a knob from the BASE config. The knobs that GOVERN this review — spec
# path, reviewer models, cross-vendor audit vendor/model, exec-gating, round budget —
# come from the ratified base, NOT the working tree: else a PR could weaken its OWN
# review (pick a weak reviewer model, set audit_vendor=codex to drop the cross-vendor
# audit, route its own findings to the run gate). Mirrors risk-classify.sh + spec_path.
bcfg() { printf '%s' "$basecfg" | sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" | head -1; }
SPEC_PATH="$(bcfg spec_path)"
[ -n "$SPEC_PATH" ] || SPEC_PATH="$(cfg spec_path || true)"
[ -n "$SPEC_PATH" ] || SPEC_PATH="SPEC.md"
EXEC_GATED="$(bcfg exec_gated)"
ROUND_BUDGET="$(bcfg round_budget)";  case "$ROUND_BUDGET" in ''|*[!0-9]*) ROUND_BUDGET=4000000 ;; esac
AUDIT_MODEL="$(bcfg audit_model)"
# Cross-vendor auditor: which subscription-authenticated CLI runs the Tier-2
# second opinion. codex (OpenAI), grok (xAI), agy (Google Antigravity). Default
# codex. Using a DIFFERENT vendor here is what makes the second opinion a real
# cross-vendor check rather than same-vendor-different-model.
AUDIT_VENDOR="$(bcfg audit_vendor)"; [ -n "$AUDIT_VENDOR" ] || AUDIT_VENDOR="codex"
# Primary reviewer VENDOR — codex | claude | grok. DISTINCT from audit_vendor (the
# cross-vendor second opinion): this is who runs the PRIMARY adversarial review.
# Default codex (no behavior change). RV_WARM_RESUME=1 means the vendor reports
# headless token usage, so its warm thread can be size-gated and resumed across fix
# rounds; grok reports none, so it always runs fresh/verify. REVIEWER_MODEL (for the
# dashboard) is the codex config model for codex, else the vendor name; a per-tier
# reviewer model (RV_MODEL, set below) overrides it.
REVIEWER_VENDOR="$(bcfg reviewer_vendor)"; [ -n "$REVIEWER_VENDOR" ] || REVIEWER_VENDOR="codex"
case "$REVIEWER_VENDOR" in
  codex|claude) RV_WARM_RESUME=1 ;;
  grok)         RV_WARM_RESUME=0 ;;
  *) die_infra "unknown reviewer_vendor '$REVIEWER_VENDOR' (supported: codex|claude|grok)" ;;
esac
[ "$REVIEWER_VENDOR" = "codex" ] || REVIEWER_MODEL="$REVIEWER_VENDOR"
# Vendor-aware resume threshold ≈ 65% of the reviewer's context window: a bigger
# window keeps the warm thread resumable far longer before falling back. env
# PLINTH_RESUME_MAX still overrides. (grok never resumes — RV_WARM_RESUME=0.)
case "$REVIEWER_VENDOR" in claude) RESUME_DEFAULT=650000 ;; grok) RESUME_DEFAULT=330000 ;; *) RESUME_DEFAULT=650000 ;; esac
RESUME_MAX="${PLINTH_RESUME_MAX:-$RESUME_DEFAULT}"
EXEC_RE="$(printf '%s' "$EXEC_GATED" | tr -s ' ' '|')"

# Runs the audit prompt through the configured vendor's CLI (read-only,
# subscription-auth, no per-use cost) and writes a schema-shaped findings JSON
# to $2. Returns nonzero on failure. grok/agy emit free-form text, so we extract
# the JSON object; codex forces the schema directly.
# Inline the canonical spec for the tools-forbidden auditor. A file spec is cat'd;
# a directory-tree spec has EVERY text file inlined (any extension) so the auditor
# judges against the WHOLE spec — MANUAL documents spec_path as a file or a tree
# with no extension restriction, and .md/.rst/.txt-only would silently drop
# YAML/JSON/other spec files. Binaries are skipped (grep -Iq) so a stray blob in
# the tree can't corrupt the prompt. Pure fn of SPEC_PATH -> testable.
inline_spec() {
  if [ -f "$SPEC_PATH" ]; then cat "$SPEC_PATH"; return; fi
  if [ -d "$SPEC_PATH" ]; then
    find "$SPEC_PATH" -type f | sort | while IFS= read -r sf; do
      grep -Iq . "$sf" 2>/dev/null || continue
      echo "--- $sf ---"; cat "$sf"
    done
    return
  fi
  echo "(spec path not found: ${SPEC_PATH})"
}

# Inline GOAL.md for the tools-forbidden auditor. AGENTS.md carries the metric-
# integrity rules; the auditor also needs the GOAL's actual eval/score contract to
# judge metric gaming, and it cannot read files. Pure fn -> testable.
inline_goal() {
  [ -f GOAL.md ] || { echo "(no GOAL.md — metric-integrity review not applicable)"; return; }
  echo "--- GOAL.md ---"; cat GOAL.md
}

run_auditor() {  # run_auditor <prompt> <out-findings-json>
  local prompt="$1" out="$2" pf="${2}.prompt" raw="${2}.raw"
  printf '%s' "$prompt" > "$pf"
  # Model flag as a proper 2-element array — an unquoted ${VAR:+-m "$VAR"} would
  # collapse to a SINGLE argv token "-m model" and the override would be ignored.
  local mflag margs=()
  case "$AUDIT_VENDOR" in agy|gemini) mflag="--model" ;; *) mflag="-m" ;; esac
  [ -n "$AUDIT_MODEL" ] && margs=("$mflag" "$AUDIT_MODEL")
  case "$AUDIT_VENDOR" in
    grok)
      grok --prompt-file "$pf" --output-format json --disallowed-tools 'Bash,Edit,Write' \
        ${margs[@]+"${margs[@]}"} > "$raw" 2>/dev/null || return 1
      jq -r '.text // empty' "$raw" | perl -0777 -ne 'print $1 if /(\{.*\})/s' > "${out}.j" 2>/dev/null || return 1 ;;
    agy|gemini)
      agy -p "$prompt" --sandbox ${margs[@]+"${margs[@]}"} > "$raw" 2>/dev/null || return 1
      perl -0777 -ne 'print $1 if /(\{.*\})/s' "$raw" > "${out}.j" 2>/dev/null || return 1 ;;
    codex)
      printf '%s' "$prompt" | codex exec ${margs[@]+"${margs[@]}"} --sandbox read-only --json \
        --output-schema "$SCHEMA" -o "${out}.j" - > /dev/null 2>&1 || return 1 ;;
    *)
      # Unknown vendor (a config typo like audit_vendor=gork). Do NOT fall
      # through to codex: that would silently run the SAME vendor as the primary
      # reviewer and record it under the bogus name — a false cross-vendor
      # guarantee AND a fail-open. Fail so the caller records it UNAVAILABLE.
      return 1 ;;
  esac
  jq . "${out}.j" > "$out" 2>/dev/null || return 1
  # Fail loud, not open: an unparseable/incomplete audit must NOT be treated as
  # a concurrence. Require a real verdict + findings array.
  jq -e '(.verdict=="APPROVED" or .verdict=="CHANGES_NEEDED") and (.findings|type=="array")' "$out" >/dev/null 2>&1
}

# Root-anchored (^, not (^|/)): finding paths are repo-relative, and a looser
# anchor would also match copies of these names in subdirs — e.g. the Plinth
# repo's own shared/ sources, which are the PRODUCT there, not the instrument.
# NB: protected-paths is DELIBERATELY NOT here — AGENTS.md excludes it from the
# UPSTREAM/tooling exemption, so a bad protected-paths change must stay blocking.
HARNESS_RE='^\.claude/hooks/|^\.claude/settings\.json$|^\.plinth/(review\.sh|risk-classify\.sh|review-schema\.json|plinth-rules\.md|MODELS\.md)$|^AGENTS\.md$'

branch="$(git symbolic-ref --short -q HEAD 2>/dev/null || echo detached)"
slug="$(printf '%s' "$branch" | tr '/ ' '--')"
SDIR=".plinth/session/review/${slug}"
RECEIPT=".plinth/session/run/${slug}/receipt.json"

mkdir -p "$SDIR"
[ -f ".plinth/session/.gitignore" ] || printf '*\n' > ".plinth/session/.gitignore"

# ── Risk routing ────────────────────────────────────────────────────────────
# The tier is computed deterministically from the diff by version-pinned tooling
# the driver cannot edit or de-escalate. It routes review DEPTH: Tier 0 (inert
# docs/text) is granted by the deterministic floor without a model round; Tier
# 1/2 get adversarial review. diff_digest is recorded in the verdict as a
# forensic fingerprint of the reviewed diff (dashboard/audit only — it is not
# a merge-time enforcement point; that hardening is deferred until real use
# shows it is needed).
diff_digest="$(printf '%s' "$diff" | shasum -a 256 2>/dev/null | cut -d' ' -f1)"
[ -n "$diff_digest" ] || diff_digest="$(printf '%s' "$diff" | sha256sum 2>/dev/null | cut -d' ' -f1)"
# Fail CLOSED: a missing/broken classifier must not de-escalate. Default Tier 2
# (full review + clean-slate confirmation + cross-vendor audit) so an unclassified
# high-consequence diff is over-reviewed, never under-reviewed.
RISK=2; RISK_JSON='{"tier":2,"reasons":["classifier unavailable — failing closed to Tier 2"]}'
if [ -x ".plinth/risk-classify.sh" ]; then
  out="$(./.plinth/risk-classify.sh "$base" 2>/dev/null || true)"
  t="$(printf '%s' "$out" | jq -r '.tier // empty' 2>/dev/null || true)"
  case "$t" in 0|1|2) RISK="$t"; RISK_JSON="$out" ;; *) : ;; esac  # unparseable => keep Tier 2
fi
echo "Plinth review: risk Tier ${RISK} ($(printf '%s' "$RISK_JSON" | jq -r '.reasons[0] // "n/a"'))"


# Tier 0: granted by the floor, no model round. Records a bound verdict so the
# Stop gate and dashboard see APPROVED-at-HEAD like any other. The floor scanners
# still run at PR; any code file would have bumped the tier above 0.
if [ "$RISK" = "0" ]; then
  jq -n --arg sha "$sha" --arg base "$baseref" --arg digest "$diff_digest" \
        --argjson risk "$RISK_JSON" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{verdict:"APPROVED", reviewer_verdict:"TIER0_AUTO", sha:$sha, base_ref:$base,
          round:0, session_id:"", model:"deterministic-floor", risk:$risk,
          diff_digest:$digest, usage:null, ts:$ts}' > "$SDIR/verdict.json"
  rm -f "$SDIR/last-error"
  echo "Plinth review: Tier 0 (inert docs/text) — APPROVED by the deterministic floor, no model round. Open the PR; CI runs the scanners."
  exit 0
fi

# Past here a model round WILL run (Tier 1/2) — now the reviewer's CLI is required.
command -v "$REVIEWER_VENDOR" >/dev/null 2>&1 || die_infra "$REVIEWER_VENDOR CLI not found (reviewer_vendor=$REVIEWER_VENDOR)"

# ── Tier 1 vs Tier 2 treatment ──────────────────────────────────────────────
# Tier 1 (ordinary code): may use a cheaper reviewer model, and a resumed
#   APPROVED binds directly (skip the clean-slate confirmation) — faster
#   iterative convergence, acceptable for ordinary code with a bound digest.
# Tier 2 (high-consequence): the frontier reviewer, ALWAYS a clean-slate
#   confirmation, and — when a genuinely cross-vendor auditor is configured
#   (audit_vendor != codex) — a cross-vendor second opinion on EVERY Tier-2
#   approval (not just every 5th). Config knobs reviewer_model_tier1/tier2 select
#   models; unset => whatever ~/.codex/config.toml runs (no behavioral change).
# Per-tier reviewer model (base config). Each vendor adapter maps RV_MODEL to its own
# flag (codex/grok -m, claude --model). Unset => the vendor's own default model.
if [ "$RISK" = "2" ]; then RV_MODEL="$(bcfg reviewer_model_tier2)"
else RV_MODEL="$(bcfg reviewer_model_tier1)"; fi
if [ -n "${RV_MODEL:-}" ]; then REVIEWER_MODEL="$RV_MODEL"; fi

# Only resume a prior session that (a) asked for changes, (b) has a live thread on
# the SAME base, and (c) is a warm UNANCHORED full-read thread. A VERIFY session is
# a fresh session seeded with the prior findings (prior findings + full diff) —
# thorough, but ANCHORED on those findings, not the warm unanchored round-1 thread
# that binds_directly trusts a resume to carry. So a verify-origin session is NOT
# resumable — the next round goes fresh (unanchored) before binding. Pure fn -> testable.
resumable_prev() {  # resumable_prev <prev_verdict> <prev_sid> <prev_base> <baseref> <prev_mode>
  [ "$1" = "CHANGES_NEEDED" ] || return 1
  [ -n "$2" ] || return 1
  [ "$3" = "$4" ] || return 1
  # Only resume a mode that carries a warm UNANCHORED full read: fresh, or a prior
  # resume that continues such a thread. verify is anchored on prior findings; an
  # empty/unknown mode (e.g. a verdict.json written before the `mode` field existed)
  # is treated the same — fail CLOSED, go fresh, re-read the full diff before any bind.
  case "${5:-}" in fresh|resume) return 0 ;; *) return 1 ;; esac
}

# Round bookkeeping. A CHANGES_NEEDED verdict with a live (resumable) session
# continues the thread (fix-verification round); anything else starts a fresh task.
mode="fresh"; round=1; sid=""
if [ -f "$SDIR/verdict.json" ]; then
  prev_verdict="$(jq -r '.verdict // empty'    "$SDIR/verdict.json")"
  prev_sha="$(jq -r '.sha // empty'            "$SDIR/verdict.json")"
  prev_base="$(jq -r '.base_ref // empty'      "$SDIR/verdict.json")"
  prev_sid="$(jq -r '.session_id // empty'     "$SDIR/verdict.json")"
  prev_mode="$(jq -r '.mode // empty'          "$SDIR/verdict.json")"
  prev_round="$(jq -r '.round // 0'            "$SDIR/verdict.json")"
  prev_in="$(jq -r '.usage.input_tokens // 0'  "$SDIR/verdict.json")"
  case "$prev_in" in ''|*[!0-9]*) prev_in=0 ;; esac
  # Budget is ADVISORY: warn loudly and continue — never park the loop on a
  # human. Runaway protection is the verdict arithmetic (v3.14) plus the
  # spend being visible in plinth watch; the human can always interrupt.
  if [ "$prev_in" -gt "$ROUND_BUDGET" ]; then
    echo "Plinth review: NOTE — last round cost ${prev_in} input tokens (> ${ROUND_BUDGET}). Continuing; spend is on the dashboard. Consider 'plinth smoke' if findings are RUNTIME-class."
  fi
  if [ "$prev_sha" = "$sha" ] && [ "$prev_verdict" = "APPROVED" ]; then
    echo "Plinth review: already APPROVED at ${sha} (round ${prev_round}). Nothing new to review."
    exit 0
  fi
  if [ "$prev_sha" = "$sha" ] && [ "$prev_verdict" = "CHANGES_NEEDED" ]; then
    die "HEAD unchanged since round ${prev_round} returned CHANGES_NEEDED — commit fixes before re-running"
  fi
  if [ "${RV_WARM_RESUME:-1}" = "1" ] && resumable_prev "$prev_verdict" "$prev_sid" "$prev_base" "$baseref" "$prev_mode"; then
    mode="resume"; round=$((prev_round + 1)); sid="$prev_sid"
    # Resume only when it can plausibly work; otherwise a verify round (fresh session,
    # prior findings + FULL diff — non-binding) instead of a warm re-read. Full reads
    # happen once per milestone, to bind.
    fallback="fresh"
    [ -f "$SDIR/findings-${prev_round}.json" ] && fallback="verify"
    if ! git cat-file -e "${prev_sha}^{commit}" 2>/dev/null; then
      echo "Plinth review: last reviewed commit ${prev_sha} no longer exists (rebase?) — running a fresh full round."
      mode="fresh"   # no valid anchor for an incremental diff
    else
      prev_in="$(jq -r '.usage.input_tokens // 0' "$SDIR/verdict.json")"
      case "$prev_in" in ''|*[!0-9]*) prev_in=0 ;; esac
      if [ "$prev_in" -gt "$RESUME_MAX" ]; then
        echo "Plinth review: prior round processed ${prev_in} input tokens (> ${RESUME_MAX}) — thread too large to resume; running a ${fallback} round."
        mode="$fallback"
      fi
    fi
  elif [ "$prev_verdict" = "CHANGES_NEEDED" ] && [ "$prev_base" = "$baseref" ] && [ -f "$SDIR/findings-${prev_round}.json" ]; then
    # Non-warm-resume reviewer (grok: no headless token usage → no size-gateable warm
    # thread) can't resume, but prior findings on the SAME base exist → a verify round
    # continues the fix loop (prior findings + full diff, non-binding).
    mode="verify"; round=$((prev_round + 1))
  else
    rm -f "$SDIR"/request-*.json "$SDIR"/findings-*.json "$SDIR"/events-*.jsonl "$SDIR"/verdict.json
  fi
fi

# Whether a completed round's APPROVED binds on its own, or a clean-slate
# confirmation must run first. A fresh full review binds. A warm RESUME holds the
# full round-1 read in its thread, so a Tier-1 resume binds directly (Tier 2 still
# gets a frontier reconfirm). A fallback VERIFY is a FRESH session seeded with the
# prior findings + the FULL diff — thorough, but ANCHORED on those findings, so it
# never binds on its own, at ANY tier: a clean-slate confirmation (full diff, NO
# prior findings — an unbiased read) is what binds. Single source of truth for both
# the post-round gate and the reviewer-facing note. Pure fn -> testable.
binds_directly() {  # binds_directly <mode> <risk-tier>  (exit 0 = binds, 1 = needs clean-slate)
  case "${1:-}" in
    fresh)  return 0 ;;
    resume) [ "${2:-}" != "2" ] ;;
    *)      return 1 ;;
  esac
}

# Tell the reviewer the TRUTH about its stakes so it neither relaxes rigor
# expecting a later pass that won't come, nor treats a non-binding round as final.
bind_note() {  # bind_note <mode> <risk-tier>
  if binds_directly "${1:-}" "${2:-}"; then
    printf '%s' "You hold the full diff from your first pass in this thread and this is an ordinary-code (Tier 1) change: your verdict BINDS DIRECTLY — no separate confirmation follows, so apply full first-pass rigor now."
  else
    printf '%s' "Your verdict does NOT bind on its own — a separate clean-slate full review still confirms before anything binds. Report findings faithfully; approving to move things along only defers to that pass."
  fi
}

# Runs one review round. Sets RVERDICT/RSID; writes the round's protocol files.
# ── Reviewer vendor adapters ────────────────────────────────────────────────
# reviewer_run <mode> dispatches to the configured reviewer_vendor. Each adapter
# runs the vendor CLI headless (read-only), writes the schema-validated verdict to
# $SDIR/findings-$r.json, and sets globals RSID (session id or "") and RUSAGE (usage
# JSON or "null"). Returns 1 ONLY on a recoverable resume failure (caller falls back);
# die_infra on a hard failure. Reads run_round's locals ($prompt/$s/$m/$r/$raw/$evfile/
# $errlog) by dynamic scope, plus $SCHEMA/$SDIR/$RV_MODEL.
reviewer_run() {
  local m="$1"; RSID=""; RUSAGE="null"
  case "$REVIEWER_VENDOR" in
    codex)  _reviewer_codex  "$m" ;;
    claude) _reviewer_claude "$m" ;;
    grok)   _reviewer_grok   "$m" ;;
  esac
}

_reviewer_codex() {  # hard --output-schema; thread_id + usage from the --json event stream
  local m="$1" margs=(); [ -n "${RV_MODEL:-}" ] && margs=(-m "$RV_MODEL")
  if [ "$m" = "resume" ]; then
    printf '%s' "$prompt" | codex exec resume "$s" -c 'sandbox_mode="read-only"' --json \
      --output-schema "$SCHEMA" -o "$raw" - > "$evfile" 2> "$errlog" || return 1
  else
    printf '%s' "$prompt" | codex exec ${margs[@]+"${margs[@]}"} --sandbox read-only --json \
      --output-schema "$SCHEMA" -o "$raw" - > "$evfile" 2> "$errlog" \
      || die_infra "codex exec failed (round $r, mode $m): $(tail -3 "$errlog" 2>/dev/null | tr '\n' ' ')"
  fi
  RSID="$(jq -r 'select(.type=="thread.started") | .thread_id // empty' "$evfile" | head -1)"
  [ -n "$RSID" ] || die_infra "no thread id in $evfile — codex --json output changed?"
  jq . "$raw" > "$SDIR/findings-$r.json" 2>/dev/null \
    || die_infra "reviewer's final message is not valid JSON — see $raw"
  RUSAGE="$(jq -c 'select(.type=="turn.completed") | .usage' "$evfile" | tail -1)"; [ -n "$RUSAGE" ] || RUSAGE="null"
}

_reviewer_claude() {  # hard --json-schema -> .structured_output; --bare skips the repo's CLAUDE.md
  local m="$1" margs=() rargs=(); [ -n "${RV_MODEL:-}" ] && margs=(--model "$RV_MODEL")
  [ "$m" = "resume" ] && rargs=(--resume "$s")
  printf '%s' "$prompt" | claude -p --bare --output-format json \
    --json-schema "$(cat "$SCHEMA")" --allowed-tools "Read,Grep,Glob" --permission-mode dontAsk \
    ${margs[@]+"${margs[@]}"} ${rargs[@]+"${rargs[@]}"} > "$raw" 2> "$errlog" \
    || { [ "$m" = "resume" ] && return 1; die_infra "claude -p failed (round $r, mode $m): $(tail -3 "$errlog" 2>/dev/null | tr '\n' ' ')"; }
  jq -e '.structured_output | objects' "$raw" > "$SDIR/findings-$r.json" 2>/dev/null \
    || die_infra "claude returned no schema-structured verdict — see $raw"
  RSID="$(jq -r '.session_id // empty' "$raw" 2>/dev/null)"
  RUSAGE="$(jq -c '.usage // "null"' "$raw" 2>/dev/null)"; [ -n "$RUSAGE" ] || RUSAGE="null"
}

_reviewer_grok() {  # SOFT schema: demand raw JSON, read .structuredOutput else extract from .text
  local m="$1" margs=() pf="$SDIR/reviewer-prompt-$r.txt"; [ -n "${RV_MODEL:-}" ] && margs=(-m "$RV_MODEL")
  printf '%s\n\nOUTPUT REQUIREMENT: respond with ONLY a single raw JSON object matching {verdict,summary,findings:[{file,line,severity,description,status}]}. No prose, no markdown, no code fences; the first character MUST be "{".' "$prompt" > "$pf"
  grok --prompt-file "$pf" --output-format json --json-schema "$(cat "$SCHEMA")" \
    --sandbox read-only ${margs[@]+"${margs[@]}"} > "$raw" 2> "$errlog" \
    || die_infra "grok failed (round $r, mode $m): $(tail -3 "$errlog" 2>/dev/null | tr '\n' ' ')"
  if ! jq -e '.structuredOutput | objects' "$raw" > "$SDIR/findings-$r.json" 2>/dev/null; then
    jq -r '.text // empty' "$raw" | perl -0777 -ne 'print $1 if /(\{.*\})/s' | jq . > "$SDIR/findings-$r.json" 2>/dev/null \
      || die_infra "grok returned no parseable verdict JSON — see $raw"
  fi
  RSID="$(jq -r '.sessionId // empty' "$raw" 2>/dev/null)"
  RUSAGE="null"   # grok headless reports no token usage
}

run_round() {  # run_round <fresh|resume> <round> <session-id-if-resume>
  local m="$1" r="$2" s="${3:-}"
  local evfile="$SDIR/events-$r.jsonl" raw="$SDIR/raw-$r.json" errlog="$SDIR/stderr-$r.log"
  local prompt evidence="" specatk="" commits=""
  # Clean-slate rounds can't run git themselves reliably — give them the commit
  # labels the tooling-tamper policy needs (certeus driver feedback).
  commits="

COMMITS IN RANGE (${baseref}..HEAD — for the tooling-tamper policy):
$(git log --format='%h %s' "${baseref}..HEAD" 2>/dev/null | head -50)"

  # Execution evidence: the latest run receipt turns runtime guessing into
  # observation — RUNTIME findings get verified against it.
  if [ -f "$RECEIPT" ]; then
    evidence="

LATEST RUN RECEIPT (execution evidence — verify RUNTIME findings against it):
$(cat "$RECEIPT")"
  fi
  # The spec is an instrument too: when the diff changes it, attack it. SPEC_PATH is
  # the BASE spec_path, so this catches edits/deletions to the PRIOR canonical spec.
  # If the PR also repoints spec_path, attack the new path too and flag the repoint.
  WSPEC="$(cfg spec_path)"
  spec_changed=""
  for sp in "$SPEC_PATH" "$WSPEC"; do
    [ -n "$sp" ] || continue
    git diff --name-only "${baseref}...HEAD" 2>/dev/null | grep -q "^${sp}" && spec_changed=1
  done
  [ -n "$WSPEC" ] && [ "$WSPEC" != "$SPEC_PATH" ] && spec_changed=1
  if [ -n "$spec_changed" ]; then
    specatk="
The canonical spec itself changed in this diff: additionally ATTACK the spec
changes for ambiguity, untestability, internal contradiction, and any weakening
or deletion of the prior contract; report such findings against the spec file at
observed severity."
    if [ -n "$WSPEC" ] && [ "$WSPEC" != "$SPEC_PATH" ]; then
      specatk="${specatk}
NOTE: this PR REPOINTS spec_path from '${SPEC_PATH}' (base) to '${WSPEC}' — a
same-PR redirect of the review target. Treat as high-consequence and attack BOTH
the prior spec ('${SPEC_PATH}') and the new one ('${WSPEC}')."
    fi
  fi

  if [ "$m" = "fresh" ]; then
    prompt="You are an independent adversarial reviewer. Follow the rules in AGENTS.md
AND the project-specific rules in .plinth/AGENTS-project.md — including the
Verdict policy (blockers/majors in project code block; minors and UPSTREAM
tooling findings are reported but non-blocking; tooling tampering blocks).
Review this diff (${baseref}...HEAD at ${sha}) against the canonical spec at: ${SPEC_PATH}
(and GOAL.md if present). Find bugs, missing or hollow tests, security issues,
scope creep, violations of project-specific rules, and — for GOAL.md tasks —
metric gaming. Your final message is machine-parsed: verdict, summary, and
concrete findings (use line 0 for file-level findings; status \"open\").
Findings on execution-gated paths whose truth depends on real libraries or
hardware you cannot observe statically: prefix the description \"RUNTIME:\" —
they route to the run gate instead of blocking.
BE EXHAUSTIVE WITHIN THIS PASS: when a finding is one instance of a general defect
class (a bug pattern, a missing/weak-test pattern, a claim-vs-behavior mismatch, an
unhandled input or edge case), SWEEP the entire diff for EVERY sibling instance and
report them all now — report every independent, substantiated finding this round,
not just the most salient one. Each missed sibling costs a full extra review
round-trip, so within-pass exhaustiveness is far cheaper than another round.${specatk}

DIFF:
${diff}${evidence}${commits}"
  elif [ "$m" = "verify" ]; then
    local prior
    prior="$(cat "$SDIR/findings-$((r - 1)).json")"
    prompt="Fix-verification round ${r} (fresh session; your prior thread was too large to
resume). Apply the Verdict policy in AGENTS.md. This is a FRESH session — assume
nothing from prior rounds beyond the findings listed. Below: (1) the findings from
the previous round, (2) the FULL diff (${baseref}...HEAD at ${sha}).
1) For each prior finding, mark status \"resolved\" or \"open\" — resolved requires
   evidence in the diff, not the driver's claim.
2) Re-review the FULL diff with first-pass rigor; new findings status \"open\".
   BE EXHAUSTIVE: when a finding is one instance of a defect class (a bug pattern,
   a missing/weak-test pattern, a claim-vs-behavior mismatch, an unhandled edge
   case), SWEEP the whole diff for EVERY sibling and report them all this round,
   not just the most salient — each missed sibling costs a full extra round-trip.
$(bind_note "$m" "$RISK")

PRIOR FINDINGS:
${prior}

DIFF (${baseref}...HEAD at ${sha}):
${diff}${evidence}${commits}"
  else
    # Incremental only: the thread already holds the prior full diff. Re-sending
    # everything is what overflowed large threads (the anvil deadlock).
    local inc
    inc="$(git diff "${prev_sha}..HEAD" 2>/dev/null || true)"
    [ -n "$inc" ] || inc="$diff"
    prompt="Fix-verification round ${r}. The driver has committed changes since your last
review; HEAD is now ${sha}. Below is the INCREMENTAL diff from the commit you
last reviewed (${prev_sha}) to the new HEAD — you already hold the prior full
diff in this conversation.
1) Re-check each finding you previously reported and mark its status \"resolved\"
   or \"open\" — resolved requires evidence in the changes, not the driver's claim.
2) Review the new changes below with the same rigor as a first pass; report new
   findings with status \"open\".
Verdict is APPROVED only if no finding remains open. $(bind_note "$m" "$RISK")

INCREMENTAL DIFF (${prev_sha}..${sha}):
${inc}${evidence}${commits}"
  fi

  jq -n --arg sha "$sha" --arg base "$baseref" --arg mode "$m" --argjson round "$r" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg spec "$SPEC_PATH" \
        '{sha:$sha, base_ref:$base, round:$round, mode:$mode, spec_path:$spec, ts:$ts}' \
        > "$SDIR/request-$r.json"

  # Dispatch to the configured reviewer vendor (codex|claude|grok). The adapter runs
  # the CLI read-only, writes the validated verdict to findings-$r.json, and sets RSID
  # + RUSAGE. A recoverable resume failure returns 1 → the caller falls back.
  reviewer_run "$m" \
    || { echo "Plinth review: resume of the reviewer session failed — falling back."; return 1; }
  RVERDICT="$(jq -r '.verdict // empty' "$SDIR/findings-$r.json")"
  case "$RVERDICT" in APPROVED|CHANGES_NEEDED) ;; *) die_infra "invalid verdict '$RVERDICT' in findings-$r.json" ;; esac

  # Verdict arithmetic is the instrument's job, not the reviewer's judgment
  # (anvil round 12: the reviewer labeled a tooling finding UPSTREAM per policy,
  # then blocked on it anyway). Effective verdict, computed from findings:
  # open blocker/major findings on PROJECT paths block; harness-path findings
  # never do; commits touching harness paths without 'plinth' in the subject
  # are treated as tampering and always block. Raw verdict recorded alongside.
  local blocking tamper RRAW
  # RUNTIME: findings on declared exec-gated paths don't block (dual-keyed:
  # reviewer prefix AND config path match) — they join the run gate instead.
  blocking="$(jq -r --arg re "$HARNESS_RE" --arg xre "$EXEC_RE" \
    '[.findings[] | select(.status == "open" and (.severity == "blocker" or .severity == "major"))
       | select((.file | test($re)) | not)
       | select( (($xre != "") and ((.description // "") | startswith("RUNTIME:")) and (.file | test($xre))) | not )
     ] | length' \
    "$SDIR/findings-$r.json")"
  tamper="$(git log --format='%s' "${baseref}..HEAD" -- .claude/hooks .claude/settings.json \
      .plinth/review.sh .plinth/risk-classify.sh .plinth/review-schema.json .plinth/plinth-rules.md \
      .plinth/MODELS.md .plinth/protected-paths AGENTS.md 2>/dev/null | { grep -civ 'plinth' || true; })"
  RRAW="$RVERDICT"
  if [ "${tamper:-0}" -gt 0 ] 2>/dev/null; then
    RVERDICT="CHANGES_NEEDED"
    echo "Plinth review: ${tamper} commit(s) touch version-pinned tooling without 'plinth' in the subject — treated as tampering; effective verdict CHANGES_NEEDED."
  elif [ "$blocking" -eq 0 ] && [ "$RRAW" = "CHANGES_NEEDED" ]; then
    RVERDICT="APPROVED"
    echo "Plinth review: reviewer said CHANGES_NEEDED but no open blocker/major finding is in project scope — effective verdict APPROVED per policy (non-blocking findings listed below)."
  elif [ "$blocking" -gt 0 ] && [ "$RRAW" = "APPROVED" ]; then
    RVERDICT="CHANGES_NEEDED"
    echo "Plinth review: reviewer said APPROVED but ${blocking} open blocker/major project finding(s) exist — effective verdict CHANGES_NEEDED."
  fi

  local usage="$RUSAGE"; [ -n "$usage" ] || usage="null"
  jq -n --arg verdict "$RVERDICT" --arg raw "$RRAW" --arg sha "$sha" --arg base "$baseref" \
        --argjson round "$r" --arg sid "$RSID" --arg mode "$m" --argjson usage "$usage" \
        --arg model "$REVIEWER_MODEL" --argjson risk "$RISK_JSON" --arg digest "$diff_digest" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{verdict:$verdict, reviewer_verdict:$raw, sha:$sha, base_ref:$base, round:$round, session_id:$sid, mode:$mode, model:$model, risk:$risk, diff_digest:$digest, usage:$usage, ts:$ts}' \
        > "$SDIR/verdict.json"
  jq -cn --argjson round "$r" --arg mode "$m" --argjson usage "$usage" \
    '{round: $round, mode: $mode, usage: $usage}' >> "$SDIR/usage.jsonl" 2>/dev/null || true
  rm -f "$SDIR/last-error"   # pipeline recovered — close the gate's infra escape
}

RMODE="$mode"
case "$mode" in
  resume)
    if ! run_round "resume" "$round" "$sid"; then
      RMODE="${fallback:-fresh}"
      run_round "$RMODE" "$round" ""
    fi ;;
  *)
    run_round "$mode" "$round" "" ;;
esac

# A warm (resume) or findings-anchored (verify) approval only says "my findings were
# addressed". Bind it directly only when the round that produced it held a warm
# UNANCHORED read: a Tier-1 RESUME does (its thread carries the round-1 full read).
# A Tier-2 approval, and ANY fallback VERIFY (a fresh session anchored on the prior
# findings + the full diff), get a clean-slate full pass first so neither continuity
# nor an anchored view can soften the adversarial read.
# binds_directly() is the single source of truth, shared with the reviewer note.
if [ "$RVERDICT" = "APPROVED" ] && ! binds_directly "$RMODE" "$RISK"; then
  echo "Plinth review: round ${round} findings resolved (mode ${RMODE}, Tier ${RISK}) — running clean-slate confirmation review before binding..."
  round=$((round + 1))
  run_round "fresh" "$round" ""
fi

echo "Plinth review — round ${round}: ${RVERDICT} at ${sha} vs ${baseref}"
jq -r '"  summary: " + .summary' "$SDIR/findings-$round.json"
if [ "$RVERDICT" = "CHANGES_NEEDED" ]; then
  jq -r '.findings[] | select(.status=="open") | "  [\(.severity)] \(.file):\(.line) — \(.description)"' \
    "$SDIR/findings-$round.json"
  echo "Fix the findings, commit, and re-run ./.plinth/review.sh (state: $SDIR/)."
  exit 1
fi
nonblocking="$(jq -r '.findings[] | select(.status=="open") | "  [\(.severity)] \(.file):\(.line) — \(.description)"' "$SDIR/findings-$round.json")"
if [ -n "$nonblocking" ]; then
  echo "Non-blocking findings (minors -> '## Noticed'; UPSTREAM -> Plinth repo; RUNTIME -> the run gate, burn down with 'plinth smoke'):"
  printf '%s\n' "$nonblocking"
fi

# Reviewer error bar (cross-vendor second opinion). Fires on EVERY Tier 2
# approval (high-consequence -> always a second, DIFFERENT-VENDOR adversary), and
# on every 5th approval otherwise. Runs ONLY when a genuinely cross-vendor auditor
# is configured (audit_vendor != the primary reviewer's codex) — audit_model alone
# must NOT trigger it, or a project carrying only the legacy audit_model would get
# a SAME-vendor codex audit falsely framed/recorded as cross-vendor. audit_model
# is a model override for that different vendor, not a trigger. Disagreement is
# reported, never adjudicated here — a different isolated model is the authority.
if [ "$AUDIT_VENDOR" != "codex" ]; then
  ac="$(cat .plinth/session/audit-count 2>/dev/null || echo 0)"
  case "$ac" in ''|*[!0-9]*) ac=0 ;; esac
  ac=$((ac + 1)); echo "$ac" > .plinth/session/audit-count
  if [ "$RISK" = "2" ] || [ $((ac % 5)) -eq 0 ]; then
    echo "Plinth review: cross-vendor audit (Tier ${RISK}, approval #$ac) — ${AUDIT_VENDOR}${AUDIT_MODEL:+ / $AUDIT_MODEL}..."
    afind="$SDIR/findings-audit-$round.json"
    # Self-contained: agentic auditor CLIs (grok/agy) would otherwise try to
    # READ the spec/rules as tool calls. Everything is inlined; tools forbidden.
    aprompt="You are a cold AUDIT reviewer from a DIFFERENT vendor than the primary
reviewer. Everything you need is INLINE below. Do NOT use any tools, do NOT try
to read files or gather more context — output your verdict directly and NOW.
Apply the reviewer Verdict policy: open blocker/major findings in PROJECT code
block; findings in version-pinned tooling are UPSTREAM (non-blocking). Catch
what the primary reviewer systematically misses.
Output ONLY a JSON object (no prose, no markdown fences):
{\"verdict\":\"APPROVED\"|\"CHANGES_NEEDED\",\"summary\":string,\"findings\":[{\"file\":string,\"line\":number,\"severity\":\"blocker\"|\"major\"|\"minor\",\"description\":string,\"status\":\"open\"|\"resolved\"}]}

=== REVIEWER RULES (mandatory project blocking policy — apply these) ===
$( for f in AGENTS.md .plinth/AGENTS-project.md; do [ -f "$f" ] && { echo "--- $f ---"; cat "$f"; }; done )

=== CANONICAL SPEC (${SPEC_PATH}) ===
$(inline_spec)

=== OPTIMIZATION GOAL (if present, apply the AGENTS.md metric-integrity rules) ===
$(inline_goal)

=== DIFF (${baseref}...HEAD at ${sha}) ===
$(git diff "${baseref}...HEAD")"
    if run_auditor "$aprompt" "$afind"; then
      ablk="$(jq -r --arg re "$HARNESS_RE" --arg xre "$EXEC_RE" \
        '[.findings[] | select(.status == "open" and (.severity == "blocker" or .severity == "major"))
           | select((.file | test($re)) | not)
           | select( (($xre != "") and ((.description // "") | startswith("RUNTIME:")) and (.file | test($xre))) | not )
         ] | length' "$afind" 2>/dev/null || echo 0)"
      case "$ablk" in ''|*[!0-9]*) ablk=0 ;; esac
      averd="$(jq -r '.verdict // "?"' "$afind" 2>/dev/null || echo '?')"
      jq --arg vn "$AUDIT_VENDOR" --arg m "${AUDIT_MODEL:-default}" --arg v "$averd" --argjson b "$ablk" \
        '. + {audit: {vendor: $vn, model: $m, verdict: $v, blocking: $b}}' "$SDIR/verdict.json" > "$SDIR/verdict.json.tmp" \
        && mv "$SDIR/verdict.json.tmp" "$SDIR/verdict.json"
      if [ "$ablk" -gt 0 ]; then
        echo "PLINTH AUDIT DISAGREEMENT: cross-vendor ${AUDIT_VENDOR} found ${ablk} blocking project finding(s) the primary reviewer did not — see $afind. Verdict unchanged; a different isolated model flagged it; adjudicate."
      else
        echo "Plinth review: cross-vendor audit concurs (${averd}, 0 blocking)."
      fi
    else
      # The audit is best-effort defense-in-depth ON TOP of a COMPLETED full
      # primary review (the Tier-2 gate that already approved) — not a second
      # gate. run_auditor never false-concurs (it returns error rather than
      # treating an unparseable/empty audit as agreement), so this branch means
      # the audit could not RUN, not that it concurred. We record that it was
      # unavailable (no silent omission) but do NOT block: a hard dependency on a
      # second vendor's availability would be exactly the tool bottleneck the
      # no-bottleneck axiom forbids. The primary review remains the gate.
      jq --arg vn "$AUDIT_VENDOR" '. + {audit: {vendor: $vn, verdict: "UNAVAILABLE", blocking: 0}}' \
        "$SDIR/verdict.json" > "$SDIR/verdict.json.tmp" && mv "$SDIR/verdict.json.tmp" "$SDIR/verdict.json"
      echo "Plinth review: cross-vendor audit UNAVAILABLE (recorded; primary review stands) — is '${AUDIT_VENDOR}' a supported vendor (codex|grok|agy) and signed in? see $SDIR/*.raw"
    fi
  fi
fi
echo "APPROVED recorded in $SDIR/verdict.json (Tier ${RISK}, digest ${diff_digest:0:12}) — open the PR. The CI floor runs automatically."
exit 0
