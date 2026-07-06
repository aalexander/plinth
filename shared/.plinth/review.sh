#!/usr/bin/env bash
# Plinth adversarial review (shared, version-pinned; v3.9). Read-only review of
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
SDIR=".plinth/session/review"
SCHEMA=".plinth/review-schema.json"
die() { echo "PLINTH REVIEW FAILED: $*" >&2; exit 2; }
# Infrastructure failure (broken pipeline, NOT loop discipline): recorded so the
# review gate releases the session instead of trapping it on something only the
# human can fix. Discipline refusals (dirty tree, empty diff, unchanged HEAD)
# use plain die — they must NOT open the gate.
die_infra() {
  { mkdir -p "$SDIR" && printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" > "$SDIR/last-error"; } 2>/dev/null || true
  die "$@"
}

command -v codex >/dev/null 2>&1 || die_infra "codex CLI not found"
command -v jq    >/dev/null 2>&1 || die_infra "jq not found"
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
[ -f "$SCHEMA" ] || die_infra "missing $SCHEMA — run 'plinth update' on this project"

# Reviews are SHA-bound. A dirty tree means the diff below would not match the
# work — the old silent-false-pass path. Refuse instead.
[ -z "$(git status --porcelain)" ] || die "working tree is dirty — commit (or stash) first; the verdict binds to a commit SHA"

sha="$(git rev-parse HEAD)"

# Resolve the base ref explicitly; never fall through to an empty diff.
if git rev-parse --verify --quiet "origin/${base}" >/dev/null; then baseref="origin/${base}"
elif git rev-parse --verify --quiet "${base}" >/dev/null; then baseref="${base}"
else die_infra "base ref '${base}' not found (tried origin/${base} and ${base})"
fi

diff="$(git diff "${baseref}...HEAD")" || die_infra "git diff ${baseref}...HEAD failed"
[ -n "$diff" ] || die "empty diff against ${baseref} at ${sha} — nothing would be reviewed. Commit your work or pass the right base branch."

# Canonical spec location: .plinth/config spec_path (file or directory).
SPEC_PATH="SPEC.md"
if [ -f ".plinth/config" ]; then
  v="$(sed -n 's/^spec_path[[:space:]]*=[[:space:]]*//p' .plinth/config | head -1)"
  [ -n "$v" ] && SPEC_PATH="$v"
fi

mkdir -p "$SDIR"
[ -f ".plinth/session/.gitignore" ] || printf '*\n' > ".plinth/session/.gitignore"

# Round bookkeeping. A CHANGES_NEEDED verdict with a live session continues the
# thread (fix-verification round); anything else starts a fresh task.
mode="fresh"; round=1; sid=""
if [ -f "$SDIR/verdict.json" ]; then
  prev_verdict="$(jq -r '.verdict // empty'    "$SDIR/verdict.json")"
  prev_sha="$(jq -r '.sha // empty'            "$SDIR/verdict.json")"
  prev_base="$(jq -r '.base_ref // empty'      "$SDIR/verdict.json")"
  prev_sid="$(jq -r '.session_id // empty'     "$SDIR/verdict.json")"
  prev_round="$(jq -r '.round // 0'            "$SDIR/verdict.json")"
  if [ "$prev_sha" = "$sha" ] && [ "$prev_verdict" = "APPROVED" ]; then
    echo "Plinth review: already APPROVED at ${sha} (round ${prev_round}). Nothing new to review."
    exit 0
  fi
  if [ "$prev_sha" = "$sha" ] && [ "$prev_verdict" = "CHANGES_NEEDED" ]; then
    die "HEAD unchanged since round ${prev_round} returned CHANGES_NEEDED — commit fixes before re-running"
  fi
  if [ "$prev_verdict" = "CHANGES_NEEDED" ] && [ -n "$prev_sid" ] && [ "$prev_base" = "$baseref" ]; then
    mode="resume"; round=$((prev_round + 1)); sid="$prev_sid"
    # Resume only when it can plausibly work; otherwise fresh (same task, no wipe).
    if ! git cat-file -e "${prev_sha}^{commit}" 2>/dev/null; then
      echo "Plinth review: last reviewed commit ${prev_sha} no longer exists (rebase?) — running a fresh full round."
      mode="fresh"
    else
      prev_in="$(jq -r '.usage.input_tokens // 0' "$SDIR/verdict.json")"
      case "$prev_in" in ''|*[!0-9]*) prev_in=0 ;; esac
      if [ "$prev_in" -gt "${PLINTH_RESUME_MAX:-650000}" ]; then
        echo "Plinth review: prior round processed ${prev_in} input tokens (> ${PLINTH_RESUME_MAX:-650000}) — thread too large to resume safely; running a fresh full round."
        mode="fresh"
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
  local prompt

  if [ "$m" = "fresh" ]; then
    prompt="You are an independent adversarial reviewer. Follow the rules in AGENTS.md
AND the project-specific rules in .plinth/AGENTS-project.md.
Review this diff (${baseref}...HEAD at ${sha}) against the canonical spec at: ${SPEC_PATH}
(and GOAL.md if present). Find bugs, missing or hollow tests, security issues,
scope creep, violations of project-specific rules, and — for GOAL.md tasks —
metric gaming. Your final message is machine-parsed: verdict, summary, and
concrete findings (use line 0 for file-level findings; status \"open\").

DIFF:
${diff}"
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
${inc}"
  fi

  jq -n --arg sha "$sha" --arg base "$baseref" --arg mode "$m" --argjson round "$r" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg spec "$SPEC_PATH" \
        '{sha:$sha, base_ref:$base, round:$round, mode:$mode, spec_path:$spec, ts:$ts}' \
        > "$SDIR/request-$r.json"

  # 'codex exec' = non-interactive; read-only sandbox prevents edits. Prompt via
  # stdin (ARG_MAX-safe); --output-schema forces the structured verdict; --json
  # events give us the session id and token usage.
  if [ "$m" = "fresh" ]; then
    printf '%s' "$prompt" | codex exec --sandbox read-only --json \
      --output-schema "$SCHEMA" -o "$raw" - > "$evfile" 2> "$errlog" \
      || die_infra "codex exec failed (round $r): $(tail -3 "$errlog" 2>/dev/null | tr '\n' ' ')"
  else
    if ! printf '%s' "$prompt" | codex exec resume "$s" -c 'sandbox_mode="read-only"' --json \
      --output-schema "$SCHEMA" -o "$raw" - > "$evfile" 2> "$errlog"; then
      echo "Plinth review: resume of the reviewer session failed ($(tail -1 "$errlog" 2>/dev/null | cut -c1-100)) — falling back to a clean-slate full round."
      return 1
    fi
  fi

  RSID="$(jq -r 'select(.type=="thread.started") | .thread_id // empty' "$evfile" | head -1)"
  [ -n "$RSID" ] || die_infra "no thread id in $evfile — codex --json output changed?"

  jq . "$raw" > "$SDIR/findings-$r.json" 2>/dev/null \
    || die_infra "reviewer's final message is not valid JSON — see $raw"
  RVERDICT="$(jq -r '.verdict // empty' "$SDIR/findings-$r.json")"
  case "$RVERDICT" in APPROVED|CHANGES_NEEDED) ;; *) die_infra "invalid verdict '$RVERDICT' in findings-$r.json" ;; esac

  local usage
  usage="$(jq -c 'select(.type=="turn.completed") | .usage' "$evfile" | tail -1)"
  [ -n "$usage" ] || usage="null"
  jq -n --arg verdict "$RVERDICT" --arg sha "$sha" --arg base "$baseref" \
        --argjson round "$r" --arg sid "$RSID" --argjson usage "$usage" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{verdict:$verdict, sha:$sha, base_ref:$base, round:$round, session_id:$sid, usage:$usage, ts:$ts}' \
        > "$SDIR/verdict.json"
  rm -f "$SDIR/last-error"   # pipeline recovered — close the gate's infra escape
}

RMODE="$mode"
if [ "$mode" = "resume" ]; then
  if ! run_round "resume" "$round" "$sid"; then
    RMODE="fresh"
    run_round "fresh" "$round" ""
  fi
else
  run_round "fresh" "$round" ""
fi

# A resumed approval only says "my findings were addressed". Bind APPROVED via a
# clean-slate confirmation pass so continuity can't soften the adversarial read.
if [ "$RMODE" = "resume" ] && [ "$RVERDICT" = "APPROVED" ]; then
  echo "Plinth review: round ${round} findings resolved — running clean-slate confirmation review..."
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
echo "APPROVED recorded in $SDIR/verdict.json — open the PR. The CI floor runs automatically; verify Codex Security commented (it requires the per-repo connection, SETUP step 4)."
exit 0
