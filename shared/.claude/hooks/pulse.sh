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
       # Redact common credential shapes before anything persists to the feed
       # (manual security review: prompts/commands can carry secrets).
       # scrub runs on the FULL string BEFORE truncation: truncating first can cut
       # a credential mid-token, leaving a fragment too short to match the regex,
       # and that fragment would persist. Scrub-then-truncate can only ever cut
       # into the "•••" replacement, never into secret material.
       def scrub: gsub("(sk-[A-Za-z0-9_-]{8,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|gho_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_-]{20,})"; "•••");
       if .hook_event_name == "UserPromptSubmit" then ((.prompt // "") | tostring | scrub | .[0:120])
       elif .tool_name == "Bash" then ((.tool_input.command // "") | tostring | scrub | .[0:160])
       elif .tool_name != null then
         ((.tool_input.file_path // .tool_input.path // .tool_input.description // "") | tostring | scrub | .[0:160])
       else null end),
     rc: (.tool_response.exit_code // null)}
  ' >> "$SDIR/events.jsonl"
} 2>/dev/null
exit 0
