#!/usr/bin/env bash
# Plinth review gate v2 (shared, version-pinned). Stop hook: lifecycle-aware.
#
# Default (BUILD): a session that committed may end without APPROVED@HEAD.
#   Logs event build_defer so watch/dash stay honest. Ship is unchanged
#   (guard still requires APPROVED for gh pr create|merge).
# HARDEN (plinth harden): same as v1 — block until APPROVED@HEAD.
#
# Phase file: .plinth/session/phase-<slug>.json  {"phase":"build"|"harden",...}
# Missing file => build (default).
#
# Receives Claude Code Stop JSON on stdin. Exit 2 = block (stderr to model).
# Exit 0 = allow.
#
# Still narrow: no git / no session / no baseline / no commits / base branch
# fail open. Infra last-error escape and PLINTH_GATE_MAX_BLOCKS remain.
set -euo pipefail
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
proj="${CLAUDE_PROJECT_DIR:-.}"
SDIR="$proj/.plinth/session"
block() { echo "PLINTH REVIEW GATE: $1" >&2; exit 2; }

git -C "$proj" rev-parse --git-dir >/dev/null 2>&1 || exit 0
[ -n "$sid" ] || exit 0
[ -f "$SDIR/start-head-$sid" ] || exit 0
head=$(git -C "$proj" rev-parse HEAD 2>/dev/null) || exit 0
[ "$(cat "$SDIR/start-head-$sid")" != "$head" ] || exit 0

log_event() {
  local event="$1" detail="$2"
  { jq -cn --arg sid "$sid" --arg head "$head" --arg detail "$detail" --arg event "$event" \
      '{ts:(now|todate), epoch:(now|floor), event:$event, sid:$sid, tool:null, detail:$detail, head:$head}' \
      >> "$SDIR/events.jsonl"; } 2>/dev/null || true
}
log_release() { log_event "gate_release" "$1"; }

branch=$(git -C "$proj" symbolic-ref --short -q HEAD 2>/dev/null || echo HEAD)
case "$branch" in
  main|master|HEAD)
    log_release "commits landed directly on '$branch' — base branch is never gated"
    exit 0 ;;
esac
# Encoded slug (feat/a-b ≠ feat/a/b); legacy tr '/ ' '--' for older session dirs.
slug=$(printf '%s' "$branch" | sed 's/\//%2F/g; s/ /%20/g')
slug_legacy=$(printf '%s' "$branch" | tr '/ ' '--')

# Lifecycle phase: default build (no forced review). Harden restores v1 Stop.
# Corrupt/invalid phase file → fail CLOSED as harden (do not silently build_defer).
phase="build"
pfile="$SDIR/phase-$slug.json"
[ -f "$pfile" ] || pfile="$SDIR/phase-$slug_legacy.json"
if [ -f "$pfile" ]; then
  if phase=$(jq -er '.phase' "$pfile" 2>/dev/null) && { [ "$phase" = "build" ] || [ "$phase" = "harden" ]; }; then
    :
  else
    phase="harden"
    log_event "phase_corrupt" "phase file invalid — treating as harden (fail closed)"
    echo "PLINTH REVIEW GATE: phase file corrupt/invalid — treating as HARDEN (fail closed)." >&2
  fi
fi
# Migration hint: open review CHANGES_NEEDED/UNBOUND without phase file → harden.
if [ ! -f "$SDIR/phase-$slug.json" ] && [ ! -f "$SDIR/phase-$slug_legacy.json" ]; then
  vtry="$SDIR/review/$slug/verdict.json"
  [ -f "$vtry" ] || vtry="$SDIR/review/$slug_legacy/verdict.json"
  if [ -f "$vtry" ]; then
    vv=$(jq -r '.verdict // empty' "$vtry" 2>/dev/null || true)
    case "$vv" in
      CHANGES_NEEDED|UNBOUND)
        phase="harden"
        log_event "phase_migrate" "open verdict $vv without phase file — harden"
        ;;
    esac
  fi
fi
# Prefer encoded slug for review session paths; fall back to legacy.
[ -d "$SDIR/review/$slug" ] || slug="$slug_legacy"
case "$phase" in
  harden) ;;
  *)
    log_event "build_defer" "phase=${phase:-build} — Stop allows without APPROVED; ship still needs APPROVED@HEAD (plinth harden when ready)"
    exit 0
    ;;
esac

err="$SDIR/review/$slug/last-error"
if [ -f "$err" ] && [ -n "$(find "$err" -mmin -30 2>/dev/null)" ]; then
  log_release "infra escape: $(cat "$err" 2>/dev/null | head -c 120)"
  echo "PLINTH REVIEW GATE: allowing stop despite missing approval — review.sh failed mechanically: $(cat "$err")" >&2
  exit 0
fi

maxblocks="${PLINTH_GATE_MAX_BLOCKS:-10}"
cnt=$(cat "$SDIR/gate-blocks-$sid" 2>/dev/null || echo 0)
if [ "$cnt" -ge "$maxblocks" ]; then
  log_release "block cap reached ($cnt/$maxblocks) — unreviewed work released at $head"
  echo "PLINTH REVIEW GATE: cap reached ($cnt blocks) — allowing stop WITHOUT an approved review. Committed work at $head is unreviewed." >&2
  exit 0
fi

vfile="$SDIR/review/$slug/verdict.json"
[ -f "$vfile" ] || vfile="$SDIR/review/$slug_legacy/verdict.json"
if [ -f "$vfile" ]; then
  v=$(jq -r '.verdict // empty' "$vfile" 2>/dev/null || echo "")
  vsha=$(jq -r '.sha // empty' "$vfile" 2>/dev/null || echo "")
  rph=$(jq -r '.review_phase // empty' "$vfile" 2>/dev/null || echo "")
  # HARDEN requires an approval produced under harden rigor (or pre-v5 missing field
  # only if not explicitly build — BUILD-phase approvals do not satisfy Stop in harden).
  if [ "$v" = "APPROVED" ] && [ "$vsha" = "$head" ]; then
    case "$rph" in
      build)
        block "HARDEN phase: APPROVED@HEAD was produced under BUILD — re-run ./.plinth/review.sh under harden (or plinth build to leave harden)."
        ;;
      *)
        exit 0
        ;;
    esac
  fi
fi
# Bound residual land (human adjudicated) — same rules as ship residual.
if [ -f "$proj/.plinth/RESIDUAL.json" ]; then
  rb="$(jq -r '.bound // false' "$proj/.plinth/RESIDUAL.json" 2>/dev/null || echo false)"
  rsha="$(jq -r '.sha // empty' "$proj/.plinth/RESIDUAL.json" 2>/dev/null || true)"
  if [ "$rb" = "true" ] && [ -n "$rsha" ] \
     && git -C "$proj" rev-parse --verify --quiet "$rsha^{commit}" >/dev/null 2>&1 \
     && git -C "$proj" merge-base --is-ancestor "$rsha" HEAD 2>/dev/null; then
    ch="$(git -C "$proj" diff --name-only "$rsha" HEAD 2>/dev/null || true)"
    if [ -z "$ch" ] || ! printf '%s\n' "$ch" | grep -Ev '^\.plinth/RESIDUAL\.json$|^HANDOFF\.md$|^\.plinth/NEEDS-HUMAN\.md$|^NEEDS-HUMAN\.md$' | grep -q .; then
      log_release "residual land bound at $rsha (HEAD $head)"
      exit 0
    fi
  fi
fi

echo $((cnt + 1)) > "$SDIR/gate-blocks-$sid"
if [ -n "$(git -C "$proj" status --porcelain 2>/dev/null)" ]; then
  block "HARDEN phase: dirty tree + no APPROVED@HEAD/residual. Commit/stash, then review or: plinth residual --bind. Or: plinth build to leave harden."
fi
block "HARDEN phase: no APPROVED@HEAD ($head) and no bound residual. Run review to APPROVED, or: plinth residual --bind && commit. Or: plinth build."
