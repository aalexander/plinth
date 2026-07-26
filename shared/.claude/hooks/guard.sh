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
# is PROBEABLE, not assumed — `plinth hookprobe <grok|codex>` (grok 0.2.112 reported no
# execution (reproduce: plinth hookprobe grok); codex has its own hook system Plinth does not wire; re-run the probe on
# CLI upgrades). Under a non-executing driver neither this hook NOR the `.claude/`
# Stop review-gate fires for a non-Claude
# driver — for them the ship gate is purely SERVER-SIDE: branch protection's required
# checks (floor + checks; the cloud review is advisory comments, and the review verdict
# is verified server-side only where `receipt / verify` is required), plus the trusted driver running
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
#    required checks (floor + checks, plus `receipt / verify` where the operator has
#    required it — that is what puts the review verdict itself under branch
#    protection). A client hook can never replace those.
#    This tripwire only turns "ship without review" from a reflexive one-liner into a
#    deliberate act.
#  - Direct base-branch pushes are likewise left to branch protection (the Stop gate
#    logs+releases base commits); client-side base detection was fragile and redundant.
# A BARE current-branch ship keeps the old fail-open behavior outside a git repo
# and on the base branch. A targeted merge is different: its PR is resolved against
# the checkout's origin (always `gh pr view … -R <origin-owner/repo>`) and every
# error blocks. The actionable merge must ALSO be origin- and head-bound: either a
# same-repo PR URL or an explicit -R/--repo naming origin, plus
# --match-head-commit equal to the origin-resolved head (so GH_REPO / default-repo
# and a racing new push cannot desync authorize-from-vs-merge-into). Multi-segment:
# each real create/merge segment is gated on its own — an APPROVED targeted merge
# must not authorize an unreviewed create. Quote-stripped argv is not a shell
# parser: any quote/apostrophe/backslash OR expansion metacharacter
# ($ ` * ? { }) in the *merge* original segment fail-closes that segment
# (multi-word --body values and `$BODY` expansions would otherwise invent a
# false PR target). Sibling create segments may still use quotes/expansions.
ship_gate() {  # <what> <unquoted-command> [original-command]
  local what="$1" command="${2:-}" orig="${3:-$2}"
  local segments segments_o segment oseg tok state need_value
  local target_ref target_repo match_head parse_error merge_seen
  local local_url local_repo url_repo n_repo resolved
  local resolved_branch resolved_sha branch head slug vf v vsha

  # Bare current-branch path (create, or merge with no PR number/URL/-R).
  _ship_bare() {
    git -C "$proj" rev-parse --git-dir >/dev/null 2>&1 || return 0
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
    block "$what blocked — no APPROVED review at HEAD ($head) for branch '$branch'. Run ./.plinth/review.sh to APPROVED, then ship. (Client-side tripwire; the real gate is branch protection's required CI status checks.)"
  }

  # owner/repo from origin or -R/URL forms (github.com host only; no GHE olympics).
  _ship_norm_repo() {
    local r="$1"
    case "$r" in
      git@github.com:*) r="${r#git@github.com:}" ;;
      ssh://git@github.com/*) r="${r#ssh://git@github.com/}" ;;
      http://github.com/*) r="${r#http://github.com/}" ;;
      https://github.com/*) r="${r#https://github.com/}" ;;
      github.com/*) r="${r#github.com/}" ;;
    esac
    r="${r%.git}"; r="${r%/}"
    printf '%s' "$r" | tr '[:upper:]' '[:lower:]'
  }

  # Targeted merge: bind to origin, resolve PR head, require APPROVED at that SHA.
  # The command under review must itself name origin and pin the head SHA.
  _ship_targeted() {
    git -C "$proj" rev-parse --git-dir >/dev/null 2>&1 \
      || block "$what blocked — targeted merge cannot be bound to a local repository checkout."
    local_url="$(git -C "$proj" remote get-url origin 2>/dev/null)" \
      || block "$what blocked — targeted merge but the local repository has no resolvable origin."
    case "$local_url" in
      git@github.com:*|ssh://git@github.com/*|http://github.com/*|https://github.com/*) ;;
      *) block "$what blocked — targeted merge but origin is not a recognizable GitHub repository." ;;
    esac
    local_repo="$(_ship_norm_repo "$local_url")"
    case "$local_repo" in
      */*) case "${local_repo#*/}" in */*) block "$what blocked — targeted merge but origin repository parsing was ambiguous." ;; esac ;;
      *) block "$what blocked — targeted merge but origin repository parsing failed." ;;
    esac

    # Actionable command must bind the repository: -R/--repo matching origin, or a
    # same-repo PR URL. Unqualified `gh pr merge 42` follows GH_REPO/default-repo.
    case "$target_ref" in
      http://github.com/*/pull/*|https://github.com/*/pull/*)
        url_repo="${target_ref#*://github.com/}"; url_repo="${url_repo%%/pull/*}"
        url_repo="$(_ship_norm_repo "github.com/$url_repo")"
        case "$url_repo" in
          */*) case "${url_repo#*/}" in */*) block "$what blocked — PR URL repository is ambiguous." ;; esac ;;
          *) block "$what blocked — PR URL repository could not be parsed." ;;
        esac
        [ "$url_repo" = "$local_repo" ] \
          || block "$what blocked — PR URL names '$url_repo', not local repository '$local_repo'."
        ;;
      https://*|http://*) block "$what blocked — PR URL is not a recognizable GitHub pull-request URL." ;;
      *)
        [ -n "$target_repo" ] \
          || block "$what blocked — targeted merge must include -R/--repo naming the local origin repository (unqualified PR numbers follow gh default-repo/GH_REPO, not origin)."
        ;;
    esac

    if [ -n "$target_repo" ]; then
      n_repo="$(_ship_norm_repo "$target_repo")"
      case "$n_repo" in
        */*) case "${n_repo#*/}" in */*) block "$what blocked — -R/--repo must name one owner/repository." ;; esac ;;
        *) block "$what blocked — -R/--repo must name owner/repository." ;;
      esac
      [ "$n_repo" = "$local_repo" ] \
        || block "$what blocked — -R/--repo names '$target_repo', not local repository '$local_repo'; a local verdict cannot authorize another repository."
    fi

    # Always bind resolve to origin — never gh's implicit default repo (upstream #16).
    if [ -n "$target_ref" ]; then
      resolved="$(gh pr view "$target_ref" -R "$local_repo" \
        --json headRefName,headRefOid,headRepository 2>/dev/null)" \
        || block "$what blocked — could not resolve targeted pull request."
    else
      resolved="$(gh pr view -R "$local_repo" \
        --json headRefName,headRefOid,headRepository 2>/dev/null)" \
        || block "$what blocked — could not resolve targeted pull request."
    fi
    resolved_branch="$(printf '%s' "$resolved" | jq -r '.headRefName // empty' 2>/dev/null)" \
      || block "$what blocked — resolved pull-request branch was unreadable."
    resolved_sha="$(printf '%s' "$resolved" | jq -r '.headRefOid // empty' 2>/dev/null)" \
      || block "$what blocked — resolved pull-request head SHA was unreadable."
    [ -n "$resolved_branch" ] \
      || block "$what blocked — pull-request resolution returned incomplete head metadata."
    printf '%s' "$resolved_sha" | grep -Eq '^[0-9a-fA-F]{40}$' \
      || block "$what blocked — pull-request resolution returned an invalid head SHA."

    # Actionable command must pin the head so the merge cannot race past the verdict.
    [ -n "$match_head" ] \
      || block "$what blocked — targeted merge must include --match-head-commit <origin-resolved-head-sha> so the ship is bound to the APPROVED head."
    printf '%s' "$match_head" | grep -Eq '^[0-9a-fA-F]{40}$' \
      || block "$what blocked — --match-head-commit is not a 40-char commit SHA."
    [ "$match_head" = "$resolved_sha" ] \
      || block "$what blocked — --match-head-commit does not match the origin-resolved PR head ($resolved_sha)."

    branch="$resolved_branch"
    head="$resolved_sha"
    slug="$(printf '%s' "$branch" | tr '/ ' '--')"
    # Verdict lives in the worktree that ran the review; do not search other worktrees.
    vf="$proj/.plinth/session/review/$slug/verdict.json"
    if [ -f "$vf" ]; then
      v="$(jq -r '.verdict // empty' "$vf" 2>/dev/null || echo)"
      vsha="$(jq -r '.sha // empty' "$vf" 2>/dev/null || echo)"
      [ "$v" = "APPROVED" ] && [ "$vsha" = "$head" ] && return 0
    fi
    block "$what blocked — no APPROVED review at targeted PR head ($head) for branch '$branch'. Run the merge from the checkout/worktree that holds its verdict."
  }

  # Parse only ordinary, directly-invoked gh forms. Unknown merge argv blocks
  # instead of falling back to the current checkout. Walk stripped and original
  # segments in lockstep so quote/backslash fail-closed is merge-segment-local
  # (a quoted create sibling must not poison an independent bound merge).
  segments="$(printf '%s' "$command" | tr ';&|`()' '\n')" \
    || block "$what blocked — could not parse gh arguments."
  segments_o="$(printf '%s' "$orig" | tr ';&|`()' '\n')" \
    || block "$what blocked — could not parse gh arguments."
  # FD 3 carries original segments parallel to stripped (bash-3.2 portable).
  # Route exec failure through block (exit 2): set -e on a bare failed exec would
  # exit 1 and fail-open the ship inspection.
  exec 3<<ORIGSEGS || block "$what blocked — could not open merge-segment parse state (TMPDIR/heredoc failure)."
$segments_o
ORIGSEGS
  while IFS= read -r segment; do
    IFS= read -r oseg <&3 || oseg=""
    # Real create segment → bare current-branch gate (independent of sibling merges).
    if printf '%s' "$segment" | grep -Eq '^[[:space:]]*'"$PFX"'gh'"$OPT"'[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'; then
      _ship_bare
      continue
    fi
    # Real merge segment only (argument-position prose in another segment is ignored).
    printf '%s' "$segment" | grep -Eq '^[[:space:]]*'"$PFX"'gh'"$OPT"'[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)' \
      || continue

    set -f
    # Intentional word splitting on the unquoted token approximation; globbing off.
    # shellcheck disable=SC2086
    set -- $segment
    set +f
    state=seek
    need_value=""
    target_ref=""
    target_repo=""
    match_head=""
    parse_error=0
    merge_seen=0
    # Unquote deletes " ' \ — multi-word values and escaped spaces lose boundaries.
    # Unexpanded $BODY / globs / braces change argv after this inspection. Fail
    # closed on quote/escape/expansion metacharacters in THIS merge segment only.
    if printf '%s' "$oseg" | grep -q '["'\''\\$`*?{}]'; then
      parse_error=1
    fi
    for tok in "$@"; do
      if [ -n "$need_value" ]; then
        case "$need_value" in
          repo) target_repo="$tok" ;;
          match_head)
            [ -z "$match_head" ] || parse_error=1
            match_head="$tok"
            ;;
        esac
        need_value=""
        continue
      fi
      case "$state:$tok" in
        seek:gh) state=gh ;;
        gh:pr) state=pr ;;
        pr:merge) state=merge; merge_seen=$((merge_seen + 1)) ;;
        gh:-R|gh:--repo|merge:-R|merge:--repo) need_value=repo ;;
        gh:-R=*|gh:--repo=*|merge:-R=*|merge:--repo=*) target_repo="${tok#*=}" ;;
        gh:-R?*|merge:-R?*) target_repo="${tok#-R}" ;;
        gh:--hostname) need_value=ignore ;;
        gh:--hostname=*) ;;
        gh:-*) ;;
        gh:*) state=seek ;;
        pr:*) state=seek ;;
        merge:--match-head-commit)
          [ -z "$match_head" ] || parse_error=1
          need_value=match_head
          ;;
        merge:--match-head-commit=*)
          [ -z "$match_head" ] || parse_error=1
          match_head="${tok#*=}"
          ;;
        merge:-A|merge:--author-email|merge:-b|merge:--body|merge:-F|merge:--body-file|merge:-t|merge:--subject)
          need_value=ignore
          ;;
        merge:-A?*|merge:-b?*|merge:-F?*|merge:-t?*|merge:--author-email=*|merge:--body=*|merge:--body-file=*|merge:--subject=*) ;;
        merge:--admin|merge:--auto|merge:-d|merge:--delete-branch|merge:--disable-auto|merge:-m|merge:--merge|merge:-r|merge:--rebase|merge:-s|merge:--squash) ;;
        merge:[0-9]*)
          case "$tok" in *[!0-9]*) parse_error=1 ;; *) [ -z "$target_ref" ] && target_ref="$tok" || parse_error=1 ;; esac
          ;;
        merge:http://*|merge:https://*)
          [ -z "$target_ref" ] && target_ref="$tok" || parse_error=1
          ;;
        merge:--) ;;
        merge:-*|merge:*) parse_error=1 ;;
      esac
    done
    [ -z "$need_value" ] || parse_error=1
    [ "$merge_seen" = 1 ] || parse_error=1
    [ "$parse_error" = 0 ] \
      || block "$what blocked — targeted gh pr merge arguments could not be parsed safely (quotes, backslashes, or expansion metacharacters (\$, \`, globs, braces) in the merge segment are not supported by this tripwire; use literal unquoted single-token flag values, --body=…, or --body-file, and pin -R plus --match-head-commit)."

    if [ -n "$target_ref" ] || [ -n "$target_repo" ]; then
      _ship_targeted
    else
      _ship_bare
    fi
  done <<< "$segments"
  exec 3<&-
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
      ship_gate "gh pr create/merge" "$stripped" "$cmd"
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
