#!/usr/bin/env bash
# Plinth pulse v1 (shared, version-pinned). Appends one JSONL event per hook
# firing to .plinth/session/events.jsonl — the raw feed for `plinth watch`.
# Wire it to: SessionStart, UserPromptSubmit, PostToolUse, SubagentStop,
# PreCompact, Stop. Events are raw facts; all interpretation (stages, rates)
# lives in the renderer, so heuristics can improve without invalidating logs.
# Must never break the session: no -e, always exit 0, one jq call + one append.
set -uo pipefail
input=$(cat)
proj="${CLAUDE_PROJECT_DIR:-.}"
SDIR="$proj/.plinth/session"
{
  mkdir -p "$SDIR"
  [ -f "$SDIR/.gitignore" ] || printf '*\n' > "$SDIR/.gitignore"
  printf '%s' "$input" | jq -c '
    {ts: (now | todate),
     epoch: (now | floor),
     event: (.hook_event_name // "unknown"),
     sid: (.session_id // null),
     transcript: (.transcript_path // null),
     tool: (.tool_name // null),
     detail: (
       if .hook_event_name == "UserPromptSubmit" then ((.prompt // "") | tostring | .[0:120])
       elif .tool_name == "Bash" then ((.tool_input.command // "") | tostring | .[0:160])
       elif .tool_name != null then
         ((.tool_input.file_path // .tool_input.path // .tool_input.description // "") | tostring | .[0:160])
       else null end),
     rc: (.tool_response.exit_code // null)}
  ' >> "$SDIR/events.jsonl"
} 2>/dev/null
exit 0
