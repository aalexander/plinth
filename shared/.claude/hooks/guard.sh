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

# Deny-ship backstop (vendor-universal). The Stop review-gate only BLOCKS on
# Claude/codex; a grok/gemini driver's Stop is advisory, so it could open a PR on
# unreviewed work. This PreToolUse hook runs for EVERY vendor (codex/grok/claude all
# honor .claude/), so gate the SHIP action here: refuse `gh pr create`/`gh pr merge`
# unless the feature branch's review verdict is APPROVED at HEAD.
# SCOPE, deliberately narrow:
#  - Direct pushes to the base branch are NOT gated here. That is server-side branch
#    protection's job (and the Stop gate already logs+releases base-branch commits);
#    detecting the base ref client-side was fragile (the base is not always
#    main/master) and redundant with protection — so it is not attempted.
#  - HEURISTIC, not malicious-proof: detection strips quoted spans (so prose that
#    merely mentions the command is inert) and also scans the raw command when a shell
#    wrapper (bash -c/eval) is present; a deeper deliberate obfuscation still evades
#    it, exactly like the destructive-command check. CI + branch protection are the
#    hard layers; this raises "ship without review" from trivial to deliberate.
# Fails OPEN (allows) outside a git repo, on the base branch, or with no verdict.
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
    stripped="$(printf '%s' "$cmd" | sed -e "s/'[^']*'//g" -e 's/"[^"]*"//g')"
    # One prefix unit: a prefix word with optional "-opt [arg]" groups, OR a VAR=val
    # assignment; PFX is any chain of them. Shared by the destructive matcher and the
    # ship gate's shell-wrapper rescan below.
    PFX='((sudo|command|env|nice|nohup|time)([[:space:]]+-[^[:space:]]*([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
    if printf '%s' "$stripped" | grep -Eq '(^|[;&|(`])[[:space:]]*'"$PFX"'(rm[[:space:]]+-rf|git[[:space:]]+push[[:space:]]+(--force|-f)([[:space:]]|$)|git[[:space:]]+reset[[:space:]]+--hard[[:space:]]+origin)' \
       || printf '%s' "$cmd" | grep -Eq 'DROP[[:space:]]+(TABLE|DATABASE)'; then
      block "destructive command detected. If intended, run it yourself."
    fi
    # Ship gate: only pay the git/jq cost when the command IS a ship action. Detect on
    # `stripped` (quoted prose inert, e.g. a commit -m mentioning "gh pr create"), PLUS
    # the raw cmd when a shell wrapper (bash -c/eval) could smuggle it past stripping —
    # the wrapper itself may be prefixed too (`env bash -c ...`, `sudo sh -c ...`,
    # `FOO=1 sh -c ...`), so the same PFX chain is tolerated before it.
    shipsan="$stripped"
    printf '%s' "$cmd" | grep -Eq '(^|[;&|(`])[[:space:]]*'"$PFX"'(bash|sh|zsh|eval)([[:space:]]|$)' && shipsan="$cmd"
    if printf '%s' "$shipsan" | grep -Eq 'gh[[:space:]]+pr[[:space:]]+(create|merge)'; then
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
