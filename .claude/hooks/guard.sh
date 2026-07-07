#!/usr/bin/env bash
# Plinth guard v3 (shared, version-pinned). Blocks destructive commands, edits
# to protected paths, and bash-level WRITES to protected paths (redirections or
# mutating commands whose text targets a protected pattern). Receives Claude
# Code PreToolUse JSON on stdin. Exit 2 = block (stderr shown to the model).
# Exit 0 = allow. Applies to every tool call, including subagents.
#
# `.plinth/session/` (verdict + event state) is protected BUILTIN — agents can
# never write it, with or without a project protected-paths file. Projects
# EXTEND protection by adding one grep -E pattern per line to
# .plinth/protected-paths (blank lines / # comments ignored).
#
# The bash-write check is heuristic by design: obfuscated writes can evade
# text matching. It raises forgery from trivial to deliberate; the planned CI
# hash-manifest job is the hard guarantee. Reads (cat/jq/grep) stay allowed.
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

BUILTIN_PROTECTED='(^|/)\.plinth/session/'
each_protected() {  # builtin pattern + project patterns, one per line
  printf '%s\n' "$BUILTIN_PROTECTED"
  if [ -f "$proj/.plinth/protected-paths" ]; then
    grep -Ev '^[[:space:]]*(#|$)' "$proj/.plinth/protected-paths" 2>/dev/null || true
  fi
}

case "$tool" in
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
    if printf '%s' "$cmd" | grep -Eq 'rm[[:space:]]+-rf|git[[:space:]]+push[[:space:]]+(--force|-f)([[:space:]]|$)|git[[:space:]]+reset[[:space:]]+--hard[[:space:]]+origin|DROP[[:space:]]+(TABLE|DATABASE)'; then
      block "destructive command detected. If intended, run it yourself."
    fi
    while IFS= read -r pattern; do
      # Path patterns are anchored for bare paths ((^|/)…$); in command TEXT a
      # relative path sits mid-string after a space, so strip the anchors and
      # match the bare pattern. Over-matching blocks (fail closed) — fine.
      bp="${pattern#"(^|/)"}"; bp="${bp#^}"; bp="${bp%\$}"
      if printf '%s' "$cmd" | grep -Eq ">>?[[:space:]]*[\"']?[^;|&]*${bp}" \
         || printf '%s' "$cmd" | grep -Eq "(^|[;&|[:space:]])(tee|mv|cp|rm|truncate|dd|touch|install|ln|chmod)[[:space:]][^;|&]*${bp}" \
         || printf '%s' "$cmd" | grep -Eq "(^|[;&|[:space:]])sed[[:space:]]+-[a-zA-Z]*i[^;|&]*${bp}"; then
        block "bash write targeting protected path (pattern '${pattern}'). Protected files are agent-immutable; if genuinely intended, the human runs it."
      fi
    done <<PATTERNS
$(each_protected)
PATTERNS
    ;;
  Edit|Write|MultiEdit)
    path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')
    if printf '%s' "$path" | grep -Eq '(^|/)\.env|(^|/)secrets/|(^|/)credentials/|(^|/)\.ssh/|(^|/)\.aws/|id_rsa|id_ed25519'; then
      block "attempt to edit a protected/secret path: $path. Needs explicit human action."
    fi
    while IFS= read -r pattern; do
      if printf '%s' "$path" | grep -Eq "$pattern"; then
        block "path matches protected pattern '$pattern': $path. This file is immutable by agents."
      fi
    done <<PATTERNS
$(each_protected)
PATTERNS
    ;;
esac
exit 0
