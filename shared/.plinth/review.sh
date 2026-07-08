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
# or the resume itself fails, the round falls back to a clean-slate full
# review in a fresh session — the loop can never deadlock on a dead thread.
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
#   audit_model  optional second model; every 5th binding approval gets a cold
#                cross-model audit round (disagreement reported, not adjudicated)
cfg() { sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" .plinth/config 2>/dev/null | head -1; }
# Reviewer model (for the dashboard): whatever codex actually runs — the model
# line in ~/.codex/config.toml. Recorded in verdict.json so watch can show it
# alongside the driver model without reading the user's codex config.
REVIEWER_MODEL="$(sed -n 's/^model[[:space:]]*=[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' "${CODEX_HOME:-$HOME/.codex}/config.toml" 2>/dev/null | head -1)"
[ -n "$REVIEWER_MODEL" ] || REVIEWER_MODEL="codex"
SPEC_PATH="$(cfg spec_path)";        [ -n "$SPEC_PATH" ] || SPEC_PATH="SPEC.md"
EXEC_GATED="$(cfg exec_gated || true)"
ROUND_BUDGET="$(cfg round_budget)";  case "$ROUND_BUDGET" in ''|*[!0-9]*) ROUND_BUDGET=4000000 ;; esac
AUDIT_MODEL="$(cfg audit_model || true)"
# Cross-vendor auditor: which subscription-authenticated CLI runs the Tier-2
# second opinion. codex (OpenAI), grok (xAI), agy (Google Antigravity). Default
# codex. Using a DIFFERENT vendor here is what makes the second opinion a real
# cross-vendor check rather than same-vendor-different-model.
AUDIT_VENDOR="$(cfg audit_vendor || true)"; [ -n "$AUDIT_VENDOR" ] || AUDIT_VENDOR="codex"
EXEC_RE="$(printf '%s' "$EXEC_GATED" | tr -s ' ' '|')"

# Runs the audit prompt through the configured vendor's CLI (read-only,
# subscription-auth, no per-use cost) and writes a schema-shaped findings JSON
# to $2. Returns nonzero on failure. grok/agy emit free-form text, so we extract
# the JSON object; codex forces the schema directly.
run_auditor() {  # run_auditor <prompt> <out-findings-json>
  local prompt="$1" out="$2" pf="${2}.prompt" raw="${2}.raw"
  printf '%s' "$prompt" > "$pf"
  case "$AUDIT_VENDOR" in
    grok)
      grok --prompt-file "$pf" --output-format json --disallowed-tools 'Bash,Edit,Write' \
        ${AUDIT_MODEL:+-m "$AUDIT_MODEL"} > "$raw" 2>/dev/null || return 1
      jq -r '.text // empty' "$raw" | perl -0777 -ne 'print $1 if /(\{.*\})/s' > "${out}.j" 2>/dev/null || return 1 ;;
    agy|gemini)
      agy -p "$prompt" --sandbox ${AUDIT_MODEL:+--model "$AUDIT_MODEL"} > "$raw" 2>/dev/null || return 1
      perl -0777 -ne 'print $1 if /(\{.*\})/s' "$raw" > "${out}.j" 2>/dev/null || return 1 ;;
    codex|*)
      printf '%s' "$prompt" | codex exec ${AUDIT_MODEL:+-m "$AUDIT_MODEL"} --sandbox read-only --json \
        --output-schema "$SCHEMA" -o "${out}.j" - > /dev/null 2>&1 || return 1 ;;
  esac
  jq . "${out}.j" > "$out" 2>/dev/null || return 1
  # Fail loud, not open: an unparseable/incomplete audit must NOT be treated as
  # a concurrence. Require a real verdict + findings array.
  jq -e '(.verdict=="APPROVED" or .verdict=="CHANGES_NEEDED") and (.findings|type=="array")' "$out" >/dev/null 2>&1
}

# Root-anchored (^, not (^|/)): finding paths are repo-relative, and a looser
# anchor would also match copies of these names in subdirs — e.g. the Plinth
# repo's own shared/ sources, which are the PRODUCT there, not the instrument.
HARNESS_RE='^\.claude/hooks/|^\.claude/settings\.json$|^\.plinth/(review\.sh|risk-classify\.sh|review-schema\.json|plinth-rules\.md|MODELS\.md|protected-paths)$|^AGENTS\.md$'

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
RISK=1; RISK_JSON='{"tier":1,"reasons":["classifier unavailable"]}'
if [ -x ".plinth/risk-classify.sh" ]; then
  RISK_JSON="$(./.plinth/risk-classify.sh "$base" 2>/dev/null || echo "$RISK_JSON")"
  RISK="$(printf '%s' "$RISK_JSON" | jq -r '.tier // 1' 2>/dev/null || echo 1)"
  case "$RISK" in 0|1|2) ;; *) RISK=1 ;; esac
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

# Past here a model round WILL run (Tier 1/2) — now the codex CLI is required.
command -v codex >/dev/null 2>&1 || die_infra "codex CLI not found"

# ── Tier 1 vs Tier 2 treatment ──────────────────────────────────────────────
# Tier 1 (ordinary code): may use a cheaper reviewer model, and a resumed
#   APPROVED binds directly (skip the clean-slate confirmation) — faster
#   iterative convergence, acceptable for ordinary code with a bound digest.
# Tier 2 (high-consequence): the frontier reviewer, ALWAYS a clean-slate
#   confirmation, and a cross-vendor second opinion every time audit_model is set
#   (not just every 5th). Config knobs reviewer_model_tier1/tier2 select models;
#   unset => whatever ~/.codex/config.toml runs (no behavioral change).
MODEL_ARGS=()
if [ "$RISK" = "2" ]; then tmodel="$(cfg reviewer_model_tier2 || true)"
else tmodel="$(cfg reviewer_model_tier1 || true)"; fi
if [ -n "${tmodel:-}" ]; then MODEL_ARGS=(-m "$tmodel"); REVIEWER_MODEL="$tmodel"; fi

# Round bookkeeping. A CHANGES_NEEDED verdict with a live session continues the
# thread (fix-verification round); anything else starts a fresh task.
mode="fresh"; round=1; sid=""
if [ -f "$SDIR/verdict.json" ]; then
  prev_verdict="$(jq -r '.verdict // empty'    "$SDIR/verdict.json")"
  prev_sha="$(jq -r '.sha // empty'            "$SDIR/verdict.json")"
  prev_base="$(jq -r '.base_ref // empty'      "$SDIR/verdict.json")"
  prev_sid="$(jq -r '.session_id // empty'     "$SDIR/verdict.json")"
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
  if [ "$prev_verdict" = "CHANGES_NEEDED" ] && [ -n "$prev_sid" ] && [ "$prev_base" = "$baseref" ]; then
    mode="resume"; round=$((prev_round + 1)); sid="$prev_sid"
    # Resume only when it can plausibly work; otherwise a cheap verify round
    # (fresh session, prior findings + incremental diff — non-binding) instead
    # of a full re-read. Full reads happen once per milestone, to bind.
    fallback="fresh"
    [ -f "$SDIR/findings-${prev_round}.json" ] && fallback="verify"
    if ! git cat-file -e "${prev_sha}^{commit}" 2>/dev/null; then
      echo "Plinth review: last reviewed commit ${prev_sha} no longer exists (rebase?) — running a fresh full round."
      mode="fresh"   # no valid anchor for an incremental diff
    else
      prev_in="$(jq -r '.usage.input_tokens // 0' "$SDIR/verdict.json")"
      case "$prev_in" in ''|*[!0-9]*) prev_in=0 ;; esac
      if [ "$prev_in" -gt "${PLINTH_RESUME_MAX:-650000}" ]; then
        echo "Plinth review: prior round processed ${prev_in} input tokens (> ${PLINTH_RESUME_MAX:-650000}) — thread too large to resume; running a ${fallback} round."
        mode="$fallback"
      fi
    fi
  else
    rm -f "$SDIR"/request-*.json "$SDIR"/findings-*.json "$SDIR"/events-*.jsonl "$SDIR"/verdict.json
  fi
fi

# Runs one review round. Sets RVERDICT/RSID; writes the round's protocol files.
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
  # The spec is an instrument too: when the diff changes it, attack it.
  if git diff --name-only "${baseref}...HEAD" 2>/dev/null | grep -q "^${SPEC_PATH}"; then
    specatk="
The canonical spec itself changed in this diff: additionally ATTACK the spec
changes for ambiguity, untestability, and internal contradiction; report such
findings against the spec file at observed severity."
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
they route to the run gate instead of blocking.${specatk}

DIFF:
${diff}${evidence}${commits}"
  elif [ "$m" = "verify" ]; then
    local prior
    prior="$(cat "$SDIR/findings-$((r - 1)).json")"
    prompt="Fix-verification round ${r} (fresh session; your prior thread was too large to
resume). Apply the Verdict policy in AGENTS.md. Below: (1) the findings from the
previous round, (2) the INCREMENTAL diff from the commit that round reviewed
(${prev_sha}) to the new HEAD (${sha}).
1) For each prior finding, mark status \"resolved\" or \"open\" — resolved requires
   evidence in the incremental diff, not the driver's claim.
2) Review the incremental diff itself with first-pass rigor; new findings status
   \"open\".
This round is verification only — if everything blocking is resolved, a separate
clean-slate full review will confirm before anything binds.

PRIOR FINDINGS:
${prior}

INCREMENTAL DIFF (${prev_sha}..${sha}):
$(git diff "${prev_sha}..HEAD" 2>/dev/null || printf '%s' "$diff")${evidence}${commits}"
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
Verdict is APPROVED only if no finding remains open. (A clean-slate full review
still confirms before approval binds.)

INCREMENTAL DIFF (${prev_sha}..${sha}):
${inc}${evidence}${commits}"
  fi

  jq -n --arg sha "$sha" --arg base "$baseref" --arg mode "$m" --argjson round "$r" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg spec "$SPEC_PATH" \
        '{sha:$sha, base_ref:$base, round:$round, mode:$mode, spec_path:$spec, ts:$ts}' \
        > "$SDIR/request-$r.json"

  # 'codex exec' = non-interactive; read-only sandbox prevents edits. Prompt via
  # stdin (ARG_MAX-safe); --output-schema forces the structured verdict; --json
  # events give us the session id and token usage.
  if [ "$m" = "resume" ]; then
    if ! printf '%s' "$prompt" | codex exec resume "$s" -c 'sandbox_mode="read-only"' --json \
      --output-schema "$SCHEMA" -o "$raw" - > "$evfile" 2> "$errlog"; then
      echo "Plinth review: resume of the reviewer session failed ($(tail -1 "$errlog" 2>/dev/null | cut -c1-100)) — falling back."
      return 1
    fi
  else  # fresh and verify both start a new session (per-tier model if configured)
    printf '%s' "$prompt" | codex exec ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} --sandbox read-only --json \
      --output-schema "$SCHEMA" -o "$raw" - > "$evfile" 2> "$errlog" \
      || die_infra "codex exec failed (round $r, mode $m): $(tail -3 "$errlog" 2>/dev/null | tr '\n' ' ')"
  fi

  RSID="$(jq -r 'select(.type=="thread.started") | .thread_id // empty' "$evfile" | head -1)"
  [ -n "$RSID" ] || die_infra "no thread id in $evfile — codex --json output changed?"

  jq . "$raw" > "$SDIR/findings-$r.json" 2>/dev/null \
    || die_infra "reviewer's final message is not valid JSON — see $raw"
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

  local usage
  usage="$(jq -c 'select(.type=="turn.completed") | .usage' "$evfile" | tail -1)"
  [ -n "$usage" ] || usage="null"
  jq -n --arg verdict "$RVERDICT" --arg raw "$RRAW" --arg sha "$sha" --arg base "$baseref" \
        --argjson round "$r" --arg sid "$RSID" --argjson usage "$usage" \
        --arg model "$REVIEWER_MODEL" --argjson risk "$RISK_JSON" --arg digest "$diff_digest" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{verdict:$verdict, reviewer_verdict:$raw, sha:$sha, base_ref:$base, round:$round, session_id:$sid, model:$model, risk:$risk, diff_digest:$digest, usage:$usage, ts:$ts}' \
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

# A warm (resume) or delta-scoped (verify) approval only says "my findings were
# addressed". For TIER 2, bind APPROVED via a clean-slate full pass so neither
# continuity nor a narrow view can soften the adversarial read. TIER 1 (ordinary
# code) accepts a resumed approval directly — the speed of iterative convergence
# is worth more than a second full read here.
if [ "$RMODE" != "fresh" ] && [ "$RVERDICT" = "APPROVED" ] && [ "$RISK" = "2" ]; then
  echo "Plinth review: Tier 2 — round ${round} findings resolved; running clean-slate confirmation review..."
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
# on every 5th approval otherwise. Runs when a cross-vendor auditor is configured
# (audit_vendor != codex) or an audit_model is set. Disagreement is reported,
# never adjudicated here — a different isolated model is the authority, not a
# human.
if [ -n "$AUDIT_MODEL" ] || [ "$AUDIT_VENDOR" != "codex" ]; then
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
$( if [ -f "$SPEC_PATH" ]; then cat "$SPEC_PATH";
   elif [ -d "$SPEC_PATH" ]; then find "$SPEC_PATH" -type f \( -name '*.md' -o -name '*.rst' -o -name '*.txt' \) | sort | while IFS= read -r sf; do echo "--- $sf ---"; cat "$sf"; done;
   else echo "(spec path not found: ${SPEC_PATH})"; fi )

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
      echo "Plinth review: cross-vendor audit UNAVAILABLE (recorded; primary review stands) — is '${AUDIT_VENDOR}' signed in? see $SDIR/*.raw"
    fi
  fi
fi
echo "APPROVED recorded in $SDIR/verdict.json (Tier ${RISK}, digest ${diff_digest:0:12}) — open the PR. The CI floor runs automatically."
exit 0
