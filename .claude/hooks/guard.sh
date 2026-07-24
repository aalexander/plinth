#!/usr/bin/env bash
# Plinth guard v3 (shared, version-pinned). Blocks destructive commands, edits
# to protected/secret paths, and bash-level WRITES to protected OR secret paths
# (redirections or mutating commands whose text targets a protected pattern or a
# secret path — secrets/, credentials/, .ssh/, .aws/, id_rsa, .env, …). Receives
# Claude Code PreToolUse JSON on stdin. Exit 2 = block (stderr shown to the model).
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

# Deny-ship TRIPWIRE. This is a CLAUDE `.claude/` PreToolUse hook: it fires for a Claude
# driver and its Claude subagents ONLY. Whether a non-Claude CLI executes these hooks
# is PROBEABLE, not assumed — `plinth hookprobe <grok|codex>` (grok 0.2.93 reported no
# execution (reproduce: plinth hookprobe grok); codex has its own hook system Plinth does not wire; re-run the probe on
# CLI upgrades). Under a non-executing driver neither this hook NOR the `.claude/`
# Stop review-gate fires for a non-Claude
# driver — for them the ship gate is purely SERVER-SIDE: branch protection's required
# checks (floor + checks; the cloud review is advisory comments, and the review verdict
# gains a server verifier only with the receipt check), plus the trusted driver running
# the loop. For a Claude driver this hook
# complements the Stop review-gate by
# refusing the plain `gh pr create`/`gh pr merge` command IMMEDIATELY, mid-turn, unless
# the feature branch's review verdict is APPROVED at HEAD. Wiring the guard into codex's
# own hook system (so a codex driver gets it too) is deferred future work.
# WHAT THIS IS, AND IS NOT — read before "hardening" it:
#  - It is a CLIENT-SIDE hook, therefore bypassable BY DEFINITION: the driver controls
#    its own machine. It catches the HONEST ship command a trusted driver runs; it does
#    NOT try to catch deliberate obfuscation (shell wrappers `bash -c "..."`, eval,
#    herestrings, pipes-into-a-shell, base64, …). Chasing those in a local hook is
#    security theater — a determined bypass always wins. Detection is on `stripped`
#    (an UNQUOTE: quote/backslash chars deleted, token CONTENT kept — not span removal)
#    so quoted PROSE mentioning the command stays inert; a `bash -c "gh pr create"`
#    deliberately hidden in quotes is OUT OF SCOPE.
#  - The ACTUAL gate against merging unreviewed work is SERVER-SIDE: branch protection's
#    required checks (floor + checks today; the receipt check adds the review-verdict
#    gate). A client hook can never replace those.
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
  block "$1 blocked — no APPROVED review at HEAD ($head) for branch '$branch'. Run ./.plinth/review.sh to APPROVED, then ship. (Client-side tripwire; the real gate is branch protection's required CI status checks.)"
}

case "$tool" in
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
    # rm/git patterns are anchored to command position. Upstream issue #1
    # hardenings (driver-reported): backticks open command substitutions —
    # they are boundaries too; and quotes are REMOVED (not the spans — the shell
    # concatenates quoted tokens, so `"rm" -rf` really runs rm) before matching,
    # so a mere MENTION mid-argument (a printf'd note, an issue body) is not at a
    # command boundary and no longer false-positives. Command position tolerates a PREFIX
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
    # UNQUOTE (remove quote/backslash chars, keep content), do NOT delete quoted spans:
    # the shell CONCATENATES quoted tokens, so `"rm" -rf`, `git "push" --force`, and
    # `gh "pr" create` really run rm/git/gh — deleting the spans would drop the command
    # word and let them bypass. Unquoting + the command-position anchor below keeps prose
    # inert (a MENTION like -m "please rm -rf x" leaves rm mid-line, not at a command
    # boundary) and keeps wrapper payloads out of scope (`bash -c "gh pr create"` becomes
    # `bash -c gh pr create`, gh not at command position). Residual: a command DELIMITER
    # (; | &) inside quoted prose (`-m "step; rm -rf x"`) exposes it to the matcher and
    # blocks — rare, and fail-closed (run it yourself). \042 " \047 ' \134 backslash.
    stripped="$(printf '%s' "$cmd" | tr -d '\042\047\134')"
    # PFX: a chain of command PREFIX words (sudo/command/env/... each with optional
    # -opts + one arg) or VAR=val assignments, before the command. OPT: a chain of a
    # command's own GLOBAL OPTIONS between it and its subcommand (`git -C . push`, `gh
    # -R o/r pr create`, `git -c k=v ...`, `--git-dir=…`) — a dash token, optionally
    # with a following non-dash arg. Both let ordinary invocations match without opening
    # a prose hole: OPT only accepts dash-led tokens, so `git commit -m push` is not a
    # `git … push`. Enumerative, not a shell parser (see the header).
    PFX='((sudo|command|env|nice|nohup|time)([[:space:]]+-[^[:space:]]*([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
    OPT='([[:space:]]+-[^;&|`[:space:]]*([[:space:]]+[^-][^;&|`[:space:]]*)?)*'
    # rm: any RECURSIVE flag (-r/-R, combined like -rf/-fr/-Rf, or --recursive) — the
    # catastrophic axis; force is usually paired but recursive is the danger. A short
    # flag must start right after a space so `--reflink`/`--version` (contain r, not
    # recursive) do not trip.
    # git push: a destructive remote-ref op by ANY encoding — FORCE overwrite (--force*, the
    # +refspec form `git push origin +main`, --mirror) OR remote-ref DELETION/prune (--delete,
    # a :refspec `git push origin :main`, --prune). The short flags -f (force) / -d (delete)
    # are matched WITHIN a bundle like rm's — `-[A-Za-z]*[fd][A-Za-z]*` catches `-fu` (=`-f -u`)
    # or `-df`, while a bundle with neither (`-u`, `-n`, `-v`) stays allowed. Deletion is a
    # soft "run it yourself" speed-bump: it is not in the autonomous loop (which pushes feature
    # branches and ships via gh, never `git push --delete`), so the false-block cost is a few
    # seconds vs. data loss on a miss. The +/: alternatives start right after a space (the
    # prefix group ends in whitespace), so a mid-token plus/colon — an ordinary non-destructive
    # refspec like `feature+x` or `HEAD:main` — is NOT a hit.
    if printf '%s' "$stripped" | grep -Eq '(^|[;&|(`])[[:space:]]*'"$PFX"'(rm[[:space:]]+([^;&|`]*[[:space:]])?(--recursive|-[A-Za-z]*[rR][A-Za-z]*)([[:space:]]|$)|git'"$OPT"'[[:space:]]+push[[:space:]]([^;&|`]*[[:space:]])?(--force[^;&|`[:space:]]*|--mirror|--prune|--delete|-[A-Za-z]*[fd][A-Za-z]*|[+][^;&|`[:space:]]*|[:][^;&|`[:space:]]*)([[:space:]]|$)|git'"$OPT"'[[:space:]]+reset[[:space:]]+--hard[[:space:]]+origin)' \
       || printf '%s' "$cmd" | grep -Eiq 'DROP[[:space:]]+(TABLE|DATABASE)'; then
      block "destructive command detected. If intended, run it yourself."
    fi
    # Ship tripwire: block `gh pr create`/`gh pr merge` at COMMAND POSITION on `stripped`
    # (start, or after a ;&|`( boundary, allowing the PFX prefix chain so `sudo gh pr
    # create` still matches, and the OPT global-options chain so `gh -R owner/repo pr
    # create` matches). Anchoring — the same treatment as the destructive check —
    # keeps an unquoted MENTION inert: `echo gh pr create`, `printf %s gh pr merge`, and
    # `gh pr view | grep gh pr create` have the phrase as an ARGUMENT, not the command, so
    # they do not trip — including a commit -m that mentions it (quotes were removed, but
    # the phrase is still mid-argument, not at a command boundary). Deliberately-quoted
    # obfuscation (`bash -c "gh pr create"` -> `bash -c gh pr create`, gh not at command
    # position) is OUT OF SCOPE by design (see the header): a client-side hook can't win
    # that race; branch protection can.
    if printf '%s' "$stripped" | grep -Eq '(^|[;&|(`])[[:space:]]*'"$PFX"'gh'"$OPT"'[[:space:]]+pr[[:space:]]+(create|merge)'; then
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
        block "bash write targeting protected path (pattern '${pattern}'). Protected files are off-limits to the driver; if genuinely intended, the human runs it."
      fi
    done <<PATTERNS
$(each_protected)
PATTERNS
    # Secret-path denylist for bash-level writes: the Edit/Write branch blocks these paths,
    # so a bash redirect / tee / touch / … targeting them must block too — else
    # `printf X > .env`, `tee secrets/key`, `touch .ssh/id_rsa` slip past despite the docs
    # promising secret paths are blocked at the tool level. Same 3 write-forms as above.
    # `.env` is included WHOLE (no .env.example carve-out here): the Edit/Write TOOL gets an
    # exact path and safely allows .env.example/.sample/.template, but in FREE-FORM command
    # text a target-vs-mention carve-out is bypassable (`printf X > .env # .env.example`),
    # so the Bash branch fails CLOSED on the entire .env family. Write .env.example via the
    # Write tool, or the human runs the bash form.
    for sp in 'secrets/' 'credentials/' '\.ssh/' '\.aws/' 'id_rsa' 'id_ed25519' '\.env'; do
      if printf '%s' "$cmd" | grep -Eq ">>?[[:space:]]*[\"']?[^;|&]*${sp}" \
         || printf '%s' "$cmd" | grep -Eq "(^|[;&|[:space:]])(tee|mv|cp|rm|truncate|dd|touch|install|ln|chmod)[[:space:]][^;|&]*${sp}" \
         || printf '%s' "$cmd" | grep -Eq "(^|[;&|[:space:]])sed[[:space:]]+-[a-zA-Z]*i[^;|&]*${sp}"; then
        block "bash write targeting a secret path (matched '${sp}'). Secret paths need explicit human action; if intended, the human runs it."
      fi
    done
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
        block "path matches protected pattern '$pattern': $path. This file is off-limits to the driver."
      fi
    done <<PATTERNS
$(each_protected)
PATTERNS
    ;;
esac
exit 0
