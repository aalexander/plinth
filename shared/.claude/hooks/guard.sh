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

# Deny-ship TRIPWIRE (vendor-universal). The Stop review-gate only BLOCKS on
# Claude/codex; a grok/gemini driver's Stop is advisory, so it could open a PR on
# unreviewed work. This PreToolUse hook runs for EVERY vendor (codex/grok/claude all
# honor .claude/), so it refuses the plain `gh pr create`/`gh pr merge` command unless
# the feature branch's review verdict is APPROVED at HEAD.
# WHAT THIS IS, AND IS NOT — read before "hardening" it:
#  - It is a CLIENT-SIDE hook, therefore bypassable BY DEFINITION: the driver controls
#    its own machine. It catches the HONEST ship command a trusted driver runs; it does
#    NOT try to catch deliberate obfuscation (shell wrappers `bash -c "..."`, eval,
#    herestrings, pipes-into-a-shell, base64, …). Chasing those in a local hook is
#    security theater — a determined bypass always wins. Detection is on `stripped`
#    (quoted spans removed) so quoted PROSE mentioning the command stays inert; a
#    `bash -c "gh pr create"` deliberately hidden in quotes is OUT OF SCOPE.
#  - The ACTUAL gate against merging unreviewed work is SERVER-SIDE: required CI checks
#    + branch protection + the cloud review. A client hook can never replace those.
#    This tripwire only turns "ship without review" from a reflexive one-liner into a
#    deliberate act.
#  - Direct base-branch pushes are likewise left to branch protection (the Stop gate
#    logs+releases base commits); client-side base detection was fragile and redundant.
# Fails OPEN (allows) outside a git repo or on the base branch. With no verdict, a
# stale verdict, or a non-APPROVED verdict for this branch's HEAD it BLOCKS — that
# is the tripwire: the plain ship command requires APPROVED@HEAD, everything else passes.
ship_gate() {  # <what> — called only when the command is a ship action
  git -C "$proj" rev-parse --git-dir >/dev/null 2>&1 || return 0
  local branch head slug vf v vsha
  branch="$(git -C "$proj" symbolic-ref --short -q HEAD 2>/dev/null || echo HEAD)"
  case "$branch" in main|master|HEAD) return 0 ;; esac   # base branch: PR-from-base is moot; not gated
  head="$(git -C "$proj" rev-parse HEAD 2>/dev/null)" || return 0
  slug="$(printf '%s' "$branch" | tr '/ ' '--')"
  vf="$proj/.plinth/session/review/$slug/verdict.json"
  if [ -f "$vf" ]; then
    v="$(jq -r '.verdict // empty' "$vf" 2>/dev/null || echo)"
    vsha="$(jq -r '.sha // empty' "$vf" 2>/dev/null || echo)"
    [ "$v" = "APPROVED" ] && [ "$vsha" = "$head" ] && return 0
  fi
  block "$1 blocked — no APPROVED review at HEAD ($head) for branch '$branch'. Run ./.plinth/review.sh to APPROVED, then ship. (Vendor-universal backstop; the Stop gate is advisory on some vendors.)"
}

case "$tool" in
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
    # rm/git patterns are anchored to command position. Upstream issue #1
    # hardenings (driver-reported): backticks open command substitutions —
    # they are boundaries too; and QUOTED spans are stripped before matching,
    # so prose that merely mentions these commands (printf'd notes, issue
    # bodies) no longer false-positives. Command position tolerates a PREFIX
    # CHAIN — sudo/command/env/nice/nohup/time, each with optional -opts and
    # one optional non-dash argument per option (`sudo -u root`, `nice -n 10`,
    # `env -i`, `command --`), plus VAR=val assignments — so prefixed forms
    # are still caught. This is ENUMERATIVE, not a shell parser: a deliberately
    # obfuscated invocation can still evade text matching (the guard's stated
    # design limit); the CI harness check is the hard layer.
    # Newlines need no handling: grep matches per line, so ^ anchors every
    # line of a multiline command. DROP stays unanchored and UNstripped:
    # real destructive SQL sits inside quotes (psql -c "..."); prose naming
    # DROP TABLE still trips it — use a --body-file / heredoc for such text.
    # Quote-stripping is escape-aware for double quotes: a \" inside a "..." span
    # must not terminate it, or the pairing shifts and quoted prose leaks into (or
    # hides from) `stripped` — e.g. -m "block bash -c \"gh pr create\" forms" would
    # otherwise strand `gh pr create` outside any span. Single quotes take no
    # escapes in shell, so their span stays simple.
    stripped="$(printf '%s' "$cmd" | sed -E -e "s/'[^']*'//g" -e 's/"(\\.|[^"\\])*"//g')"
    # One prefix unit: a prefix word with optional "-opt [arg]" groups, OR a VAR=val
    # assignment; PFX is any chain of them (used only by the destructive matcher — the
    # ship tripwire below matches plain unquoted `gh pr create/merge`, where prefixes
    # ride on the same line and need no special handling).
    PFX='((sudo|command|env|nice|nohup|time)([[:space:]]+-[^[:space:]]*([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
    if printf '%s' "$stripped" | grep -Eq '(^|[;&|(`])[[:space:]]*'"$PFX"'(rm[[:space:]]+-rf|git[[:space:]]+push[[:space:]]+(--force|-f)([[:space:]]|$)|git[[:space:]]+reset[[:space:]]+--hard[[:space:]]+origin)' \
       || printf '%s' "$cmd" | grep -Eq 'DROP[[:space:]]+(TABLE|DATABASE)'; then
      block "destructive command detected. If intended, run it yourself."
    fi
    # Ship tripwire: block `gh pr create`/`gh pr merge` at COMMAND POSITION on `stripped`
    # (start, or after a ;&|`( boundary, allowing the PFX prefix chain so `sudo gh pr
    # create` still matches). Anchoring — the same treatment as the destructive check —
    # keeps an unquoted MENTION inert: `echo gh pr create`, `printf %s gh pr merge`, and
    # `gh pr view | grep gh pr create` have the phrase as an ARGUMENT, not the command, so
    # they do not trip. Quoted spans are already stripped, so a commit -m mentioning it is
    # inert too. Deliberately-quoted obfuscation (`bash -c "gh pr create"`) is OUT OF SCOPE
    # by design (see the header): a client-side hook can't win that race; branch protection can.
    if printf '%s' "$stripped" | grep -Eq '(^|[;&|(`])[[:space:]]*'"$PFX"'gh[[:space:]]+pr[[:space:]]+(create|merge)'; then
      ship_gate "gh pr create/merge"
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
    if printf '%s' "$path" | grep -Eq '(^|/)secrets/|(^|/)credentials/|(^|/)\.ssh/|(^|/)\.aws/|id_rsa|id_ed25519'; then
      block "attempt to edit a protected/secret path: $path. Needs explicit human action."
    fi
    # .env* is secret — but .env.example/.sample/.template are conventionally
    # committed documentation, not secrets.
    if printf '%s' "$path" | grep -Eq '(^|/)\.env' \
       && ! printf '%s' "$path" | grep -Eq '\.(example|sample|template)$'; then
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
