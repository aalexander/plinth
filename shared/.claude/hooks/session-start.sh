#!/usr/bin/env bash
# Plinth session-start recorder v2 (shared, version-pinned). Records HEAD at
# session start so the review gate (Stop hook) enforces only on sessions that
# create commits. Receives Claude Code SessionStart JSON on stdin.
# Never blocks. May emit additionalContext (Claude) when HANDOFF.md exists so
# the driver is nudged to read the restart file — stdout is reserved for that
# JSON only when context is injected; otherwise silent (no stdout pollution).
set -euo pipefail
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
proj="${CLAUDE_PROJECT_DIR:-.}"

[ -n "$sid" ] || exit 0
git -C "$proj" rev-parse --git-dir >/dev/null 2>&1 || exit 0

SDIR="$proj/.plinth/session"
mkdir -p "$SDIR"
[ -f "$SDIR/.gitignore" ] || printf '*\n' > "$SDIR/.gitignore"

# Don't reset the baseline when an existing session is resumed — the gate would
# stop enforcing for commits made before the resume.
if [ ! -f "$SDIR/start-head-$sid" ]; then
  git -C "$proj" rev-parse HEAD > "$SDIR/start-head-$sid" 2>/dev/null \
    || echo "none" > "$SDIR/start-head-$sid"
fi

# Hygiene: session-scoped files older than 7 days; cap the event log.
find "$SDIR" -maxdepth 1 \( -name 'start-head-*' -o -name 'gate-blocks-*' -o -name 'handoff-*.md' \) -mtime +7 -delete 2>/dev/null || true
EV="$SDIR/events.jsonl"
if [ -f "$EV" ] && [ "$(wc -c < "$EV" | tr -d ' ')" -gt 5000000 ]; then
  tail -n 2000 "$EV" > "$EV.tmp" && mv "$EV.tmp" "$EV"
fi

# Lifecycle + handoff nudge (v5): inject short context when HANDOFF exists.
ctx=""
if [ -f "$proj/HANDOFF.md" ]; then
  branch=$(git -C "$proj" symbolic-ref --short -q HEAD 2>/dev/null || echo HEAD)
  slug=$(printf '%s' "$branch" | tr '/ ' '--')
  # Missing → build; corrupt/unknown → harden (fail closed; match Stop).
  phase="build"
  if [ -f "$SDIR/phase-$slug.json" ]; then
    phase=$(jq -r '.phase // empty' "$SDIR/phase-$slug.json" 2>/dev/null || true)
    case "$phase" in
      build|harden) ;;
      *) phase=harden ;;
    esac
  fi
  head=$(git -C "$proj" rev-parse --short HEAD 2>/dev/null || echo "?")
  ctx="Plinth lifecycle: phase=${phase} branch=${branch} @ ${head}. HANDOFF.md present — READ it and continue from ## Next. Automation: keep cooking until ## Next is empty or NEEDS-HUMAN has [BLOCKING] items. Never wait for compaction (optional only). Ship needs APPROVED@HEAD (plinth harden + ./.plinth/review.sh)."
  { jq -cn --arg sid "$sid" --arg detail "handoff present phase=$phase" \
      '{ts:(now|todate),epoch:(now|floor),event:"SessionStart",sid:$sid,tool:null,detail:$detail,head:null}' \
      >> "$EV"; } 2>/dev/null || true
fi

if [ -n "$ctx" ]; then
  # Claude Code: SessionStart can return additionalContext. Other harnesses ignore JSON.
  jq -cn --arg c "$ctx" \
    '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
fi
exit 0
