#!/usr/bin/env bash
# Plinth guard v2 (shared, version-pinned). Blocks destructive commands and edits to
# protected paths. Receives Claude Code PreToolUse JSON on stdin.
# Exit 2 = block (stderr shown to the model). Exit 0 = allow.
# Applies to every tool call, including dynamic-workflow subagents.
#
# Projects EXTEND the protected-path list without editing this file by adding one
# grep -E pattern per line to .plinth/protected-paths (e.g. the immutable eval
# script of a GOAL.md task). Blank lines and lines starting with # ignored.
set -euo pipefail
input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
proj="${CLAUDE_PROJECT_DIR:-.}"
block() {
  # Log the block for `plinth watch` (best-effort; never affects the verdict).
  { mkdir -p "$proj/.plinth/session" && jq -cn --arg tool "$tool" --arg detail "$1" \
      '{ts:(now|todate), epoch:(now|floor), event:"guard_block", sid:null, tool:$tool, detail:($detail|.[0:160])}' \
      >> "$proj/.plinth/session/events.jsonl"; } 2>/dev/null || true
  echo "PLINTH BLOCKED: $1" >&2; exit 2
}

case "$tool" in
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
    if printf '%s' "$cmd" | grep -Eq 'rm[[:space:]]+-rf|git[[:space:]]+push[[:space:]]+(--force|-f)([[:space:]]|$)|git[[:space:]]+reset[[:space:]]+--hard[[:space:]]+origin|DROP[[:space:]]+(TABLE|DATABASE)'; then
      block "destructive command detected. If intended, run it yourself."
    fi ;;
  Edit|Write|MultiEdit)
    path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')
    if printf '%s' "$path" | grep -Eq '(^|/)\.env|(^|/)secrets/|(^|/)credentials/|(^|/)\.ssh/|(^|/)\.aws/|id_rsa|id_ed25519'; then
      block "attempt to edit a protected/secret path: $path. Needs explicit human action."
    fi
    if [ -f "$proj/.plinth/protected-paths" ]; then
      while IFS= read -r pattern; do
        case "$pattern" in ''|'#'*) continue ;; esac
        if printf '%s' "$path" | grep -Eq "$pattern"; then
          block "path matches project protected pattern '$pattern': $path. This file is immutable by agents."
        fi
      done < "$proj/.plinth/protected-paths"
    fi ;;
esac
exit 0
