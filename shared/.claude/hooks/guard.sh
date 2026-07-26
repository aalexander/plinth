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
    # Preserve trailing newlines (<<'' terminator is an empty line at EOF).
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty'; printf x)
    cmd=${cmd%x}
    # Heredoc body handling. Quoting a delimiter only disables shell expansion —
    # it does NOT make the body non-executable (`bash <<'E'` still runs the body;
    # `sqlite3 <<'E'` still runs SQL). Suppress body lines from BOTH pattern scans
    # (destructive + protected/secret-path) ONLY when ALL of:
    #   (1) delimiter is a simple quoted form we decode confidently:
    #       'D', pure "D" (no backslash), pure $'D' (no backslash), or
    #       quoted-empty <<'' / <<"" — not $"D" (locale), no ANSI-C / \x olympics,
    #   (2) FIRST command word of the simple command owning << (after the last
    #       unquoted |;&, skipping sudo/env/nice/nohup/time and VAR=) is exactly
    #       cat or tee (basename),
    #   (3) that simple command has no unquoted | or process-sub >( / <( on the
    #       same physical header segment before/after <<,
    #   (4) the physical header line is complete: no trailing unquoted \, no
    #       unclosed quote after <<, and the line is not itself a \-continuation
    #       of a previous physical line (consumer/pipe may live off-line).
    # Cross-line shell quote state is tracked so a heredoc-looking token inside an
    # unclosed quote is not treated as a real header. Word-concat / ANSI-C / mixed
    # delimiters ('X'$'Y', X$'\x59', backslash-bearing "…") are never suppressed.
    # Unquoted bodies, executable consumers, continued/incomplete headers, and
    # ambiguous parses stay fully scanned (fail closed). Header text is always
    # printed into the scan. Fixes upstream #22 without over-broad suppress.
    inert_stripped="$(printf '%s\n' "$cmd" | awk '
      function enqueue(d, suppress, t) { tail++; delim[tail]=d; suppress_body[tail]=suppress; tabs[tail]=t }
      function is_inert_consumer(c) { return (c=="cat" || c=="tee") }
      function last_unquoted_sep(s,    i,n,c,st,last) {
        n=length(s); st=""; last=0
        for (i=1;i<=n;i++) {
          c=substr(s,i,1)
          if (st=="sq") { if (c=="\047") st=""; continue }
          if (st=="dq") {
            if (c=="\\") { i++; continue }
            if (c=="\"") st=""
            continue
          }
          if (c=="\047") { st="sq"; continue }
          if (c=="\"") { st="dq"; continue }
          if (c=="\\") { i++; continue }
          if (c=="|" || c==";" || c=="&") last=i
        }
        return last
      }
      function has_unquoted_pipe_or_procsub(s,    i,n,c,st,prev,prev_esc) {
        n=length(s); st=""; prev=""; prev_esc=0
        for (i=1;i<=n;i++) {
          c=substr(s,i,1)
          if (st=="sq") { if (c=="\047") st=""; prev=c; prev_esc=0; continue }
          if (st=="dq") {
            if (c=="\\") { i++; if (i<=n) { prev=substr(s,i,1); prev_esc=1 } continue }
            if (c=="\"") st=""
            prev=c; prev_esc=0; continue
          }
          if (c=="\\") { i++; if (i<=n) { prev=substr(s,i,1); prev_esc=1 } continue }
          if (c=="#" && !prev_esc && (prev=="" || prev ~ /[[:space:];&|]/)) break
          if (c=="\047") { st="sq"; prev=c; prev_esc=0; continue }
          if (c=="\"") { st="dq"; prev=c; prev_esc=0; continue }
          if (c=="|") return 1
          if (c==">" && i<n && substr(s,i+1,1)=="(") return 1
          if (c=="<" && i<n && substr(s,i+1,1)=="(") return 1
          prev=c; prev_esc=0
        }
        return 0
      }
      # Unquoted trailing \ => physical line continues. Stops at unquoted # (comment).
      function unquoted_line_continues(s,    i,n,c,st,prev,prev_esc) {
        n=length(s); st=""; prev=""; prev_esc=0
        for (i=1;i<=n;i++) {
          c=substr(s,i,1)
          if (st=="sq") { if (c=="\047") st=""; prev=c; prev_esc=0; continue }
          if (st=="dq") {
            if (c=="\\") { i++; if (i<=n) { prev=substr(s,i,1); prev_esc=1 } continue }
            if (c=="\"") st=""
            prev=c; prev_esc=0; continue
          }
          if (st=="bt") {
            if (c=="\\") { i++; if (i<=n) { prev=substr(s,i,1); prev_esc=1 } continue }
            if (c=="`") st=""
            prev=c; prev_esc=0; continue
          }
          if (c=="\\") {
            if (i==n) return 1
            i++; if (i<=n) { prev=substr(s,i,1); prev_esc=1 }
            continue
          }
          if (c=="#" && !prev_esc && (prev=="" || prev ~ /[[:space:];&|]/)) break
          if (c=="\047") { st="sq"; prev=c; prev_esc=0; continue }
          if (c=="\"") { st="dq"; prev=c; prev_esc=0; continue }
          if (c=="`") { st="bt"; prev=c; prev_esc=0; continue }
          prev=c; prev_esc=0
        }
        return 0
      }
      # Keyword compound openers/closers per ;-separated segment (if/while/… fi/done/esac).
      function update_kw_depth(line,    s,n,a,i,w) {
        s=line
        n=split(s,a,/;/)
        for (i=1;i<=n;i++) {
          w=a[i]
          sub(/^[[:space:]]+/,"",w)
          if (w ~ /^(if|while|until|for|case|select)([^[:alnum:]_]|$)/) kw_depth++
          if (w ~ /^(fi|done|esac)([^[:alnum:]_]|$)/ && kw_depth>0) kw_depth--
        }
      }
      # Advance global qst / exp_depth / bt_open / brace_depth / paren_depth over s.
      # depth: $(...) / ${...} / <(...) / >(...). brace/paren: {…} / (… ) compound groups.
      function advance_globals(s,    i,n,c,st,depth,bt,br,pa,prev,prev_esc) {
        n=length(s); st=qst; depth=exp_depth; bt=bt_open; br=brace_depth; pa=paren_depth
        prev=""; prev_esc=0
        update_kw_depth(s)
        for (i=1;i<=n;i++) {
          c=substr(s,i,1)
          if (st=="sq") { if (c=="\047") st=""; prev=c; prev_esc=0; continue }
          if (st=="dq") {
            if (c=="\\") { i++; if (i<=n) { prev=substr(s,i,1); prev_esc=1 } continue }
            if (c=="\"") st=""
            prev=c; prev_esc=0; continue
          }
          if (bt) {
            if (c=="\\") { i++; if (i<=n) { prev=substr(s,i,1); prev_esc=1 } continue }
            if (c=="`") bt=0
            prev=c; prev_esc=0; continue
          }
          if (c=="\\") { i++; if (i<=n) { prev=substr(s,i,1); prev_esc=1 } continue }
          if (c=="#" && !prev_esc && (prev=="" || prev ~ /[[:space:];&|]/)) break
          if (c=="\047") { st="sq"; prev=c; prev_esc=0; continue }
          if (c=="\"") { st="dq"; prev=c; prev_esc=0; continue }
          if (c=="`") { bt=1; prev=c; prev_esc=0; continue }
          if (c=="$" && i<n && substr(s,i+1,1)=="(") { depth++; i++; prev="("; prev_esc=0; continue }
          if (c=="$" && i<n && substr(s,i+1,1)=="{") { depth++; i++; prev="{"; prev_esc=0; continue }
          if (c=="<" && i<n && substr(s,i+1,1)=="(") { depth++; i++; prev="("; prev_esc=0; continue }
          if (c==">" && i<n && substr(s,i+1,1)=="(") { depth++; i++; prev="("; prev_esc=0; continue }
          # << is a heredoc op, not process-sub; skip the extra <
          if (c=="<" && i<n && substr(s,i+1,1)=="<") { i++; prev="<"; prev_esc=0; continue }
          if (depth>0 && c=="(") { depth++; prev=c; prev_esc=0; continue }
          if (depth>0 && c=="{") { depth++; prev=c; prev_esc=0; continue }
          if (depth>0 && c==")") { depth--; prev=c; prev_esc=0; continue }
          if (depth>0 && c=="}") { depth--; prev=c; prev_esc=0; continue }
          if (c=="{") { br++; prev=c; prev_esc=0; continue }
          if (c=="}" && br>0) { br--; prev=c; prev_esc=0; continue }
          if (c=="(") { pa++; prev=c; prev_esc=0; continue }
          if (c==")" && pa>0) { pa--; prev=c; prev_esc=0; continue }
          prev=c; prev_esc=0
        }
        qst=st; exp_depth=depth; bt_open=bt; brace_depth=br; paren_depth=pa
      }
      # Incomplete open quote/expansion/backtick in s alone (fresh state; comment-aware).
      function has_incomplete_local(s,    i,n,c,st,depth,bt,prev,prev_esc) {
        n=length(s); st=""; depth=0; bt=0; prev=""; prev_esc=0
        for (i=1;i<=n;i++) {
          c=substr(s,i,1)
          if (st=="sq") { if (c=="\047") st=""; prev=c; prev_esc=0; continue }
          if (st=="dq") {
            if (c=="\\") { i++; if (i<=n) { prev=substr(s,i,1); prev_esc=1 } continue }
            if (c=="\"") st=""
            prev=c; prev_esc=0; continue
          }
          if (bt) {
            if (c=="\\") { i++; if (i<=n) { prev=substr(s,i,1); prev_esc=1 } continue }
            if (c=="`") bt=0
            prev=c; prev_esc=0; continue
          }
          if (c=="\\") { i++; if (i<=n) { prev=substr(s,i,1); prev_esc=1 } continue }
          if (c=="#" && !prev_esc && (prev=="" || prev ~ /[[:space:];&|]/)) break
          if (c=="\047") { st="sq"; prev=c; prev_esc=0; continue }
          if (c=="\"") { st="dq"; prev=c; prev_esc=0; continue }
          if (c=="`") { bt=1; prev=c; prev_esc=0; continue }
          if (c=="$" && i<n && substr(s,i+1,1)=="(") { depth++; i++; prev="("; prev_esc=0; continue }
          if (c=="$" && i<n && substr(s,i+1,1)=="{") { depth++; i++; prev="{"; prev_esc=0; continue }
          if (c=="<" && i<n && substr(s,i+1,1)=="(") { depth++; i++; prev="("; prev_esc=0; continue }
          if (c==">" && i<n && substr(s,i+1,1)=="(") { depth++; i++; prev="("; prev_esc=0; continue }
          if (c=="<" && i<n && substr(s,i+1,1)=="<") { i++; prev="<"; prev_esc=0; continue }
          if (depth>0 && c=="(") { depth++; prev=c; prev_esc=0; continue }
          if (depth>0 && c=="{") { depth++; prev=c; prev_esc=0; continue }
          if (depth>0 && c==")") { depth--; prev=c; prev_esc=0; continue }
          if (depth>0 && c=="}") { depth--; prev=c; prev_esc=0; continue }
          prev=c; prev_esc=0
        }
        return (st!="" || bt || depth>0)
      }
      # First command word of the simple command owning <<. "" = fail closed.
      function first_consumer(prefix,    s,n,a,i,w,sep) {
        s=prefix
        sep=last_unquoted_sep(s)
        if (sep>0) s=substr(s,sep+1)
        gsub(/[0-9]*>>?[ \t]*[^ \t;&|<>]+/," ",s)
        gsub(/[0-9]*>>?&[0-9]+/," ",s)
        gsub(/[0-9]*>>?/," ",s)
        gsub(/[0-9]*<[ \t]*[^ \t;&|<>]+/," ",s)
        gsub(/[ \t]+/," ",s)
        sub(/^ /,"",s); sub(/ $/,"",s)
        n=split(s,a," ")
        for (i=1;i<=n;i++) {
          w=a[i]
          if (w ~ /"/ || w ~ /\047/) {
            if (w ~ /^"[^"]*"$/ || w ~ /^\047[^\047]*\047$/) w=substr(w,2,length(w)-2)
            else return ""
          }
          if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue
          if (w ~ /^(sudo|command|env|nice|nohup|time)$/) {
            while (i+1<=n && a[i+1] ~ /^-/) {
              i++
              if (a[i] ~ /^--[^=]+=/) continue
              if (a[i] ~ /^--/) continue
              # short opts that take a value for these prefixes
              if ((w=="sudo" && a[i] ~ /^-[ugCTrRp]$/) || \
                  (w=="env" && a[i] ~ /^-[uCS]$/) || \
                  (w=="nice" && a[i]=="-n") || \
                  (w=="time" && a[i] ~ /^-[fo]$/)) {
                if (i+1<=n && a[i+1] !~ /^-/) i++
              }
            }
            continue
          }
          if (w ~ /^-/) continue
          sub(/.*\//,"",w)
          return w
        }
        return ""
      }
      # qst / exp_depth / bt_open: cross-line shell state (quotes, $(/<(/>(), backticks).
      # cont: previous physical line ended with unquoted \.
      # Delimiter parse uses dst (separate) so it never clobbers shell quote state.
      function scan(line,    i,j,n,c,d,q,t,st,prev,cons,qch,ok,pref,sep,simple,dst,reliable,rest,depth,bt,br,pa,closed,prev_esc) {
        n=length(line); st=qst; depth=exp_depth; bt=bt_open; br=brace_depth; pa=paren_depth
        prev=""; prev_esc=0
        for (i=1;i<=n;i++) {
          c=substr(line,i,1)
          if (st=="sq") { if (c=="\047") st=""; prev=c; prev_esc=0; continue }
          if (st=="dq") {
            if (c=="\\") { i++; if (i<=n) { prev=substr(line,i,1); prev_esc=1 } continue }
            if (c=="\"") st=""
            prev=c; prev_esc=0; continue
          }
          if (bt) {
            if (c=="\\") { i++; if (i<=n) { prev=substr(line,i,1); prev_esc=1 } continue }
            if (c=="`") bt=0
            prev=c; prev_esc=0; continue
          }
          if (c=="\\") { i++; if (i<=n) { prev=substr(line,i,1); prev_esc=1 } continue }
          if (c=="#" && !prev_esc && (prev=="" || prev ~ /[[:space:];&|]/)) break
          # track same-line expansions/quotes/groups before we consider <<
          if (c=="\047") { st="sq"; prev=c; prev_esc=0; continue }
          if (c=="\"") { st="dq"; prev=c; prev_esc=0; continue }
          if (c=="`") { bt=1; prev=c; prev_esc=0; continue }
          if (c=="$" && i<n && substr(line,i+1,1)=="(") { depth++; i++; prev="("; prev_esc=0; continue }
          if (c=="$" && i<n && substr(line,i+1,1)=="{") { depth++; i++; prev="{"; prev_esc=0; continue }
          if (c=="<" && i<n && substr(line,i+1,1)=="(") { depth++; i++; prev="("; prev_esc=0; continue }
          if (c==">" && i<n && substr(line,i+1,1)=="(") { depth++; i++; prev="("; prev_esc=0; continue }
          if (depth>0 && c=="(") { depth++; prev=c; prev_esc=0; continue }
          if (depth>0 && c=="{") { depth++; prev=c; prev_esc=0; continue }
          if (depth>0 && c==")") { depth--; prev=c; prev_esc=0; continue }
          if (depth>0 && c=="}") { depth--; prev=c; prev_esc=0; continue }
          if (c=="{") { br++; prev=c; prev_esc=0; continue }
          if (c=="}" && br>0) { br--; prev=c; prev_esc=0; continue }
          if (c=="(") { pa++; prev=c; prev_esc=0; continue }
          if (c==")" && pa>0) { pa--; prev=c; prev_esc=0; continue }
          # heredoc << (not <<<)
          if (c!="<" || substr(line,i+1,1)!="<" || substr(line,i+2,1)=="<") { prev=c; prev_esc=0; continue }
          j=i+2; t=0
          if (substr(line,j,1)=="-") { t=1; j++ }
          while (j<=n && substr(line,j,1) ~ /[[:space:]]/) j++
          d=""; q=0; dst=""; ok=1; reliable=1
          # incomplete outer state (prior lines or same-line so far) => never suppress
          if (cont || depth>0 || bt || st!="" || br>0 || pa>0 || kw_depth>0) ok=0
          # same-line keyword compound opener before <<
          pref=substr(line,1,i-1)
          if (pref ~ /(^|[[:space:];&|({])(if|while|until|for|case|select)([^[:alnum:]_]|$)/) ok=0
          # dollar-quoted delim: $'D' pure literal only (closed, no backslash).
          # $"D" is locale-translated by Bash — never suppress (cannot know the real terminator).
          if (j<=n && substr(line,j,1)=="$" && j+1<=n && substr(line,j+1,1)=="\"") {
            reliable=0; ok=0; d=""; q=1; j+=2
            while (j<=n) {
              c=substr(line,j,1)
              if (c=="\"") { j++; break }
              if (c=="\\") { j++; if (j<=n) j++; continue }
              j++
            }
          } else if (j<=n && substr(line,j,1)=="$" && j+1<=n && substr(line,j+1,1)=="\047") {
            q=1; qch="\047"; j+=2; closed=0
            while (j<=n) {
              c=substr(line,j,1)
              if (c==qch) { j++; closed=1; break }
              if (c=="\\") { reliable=0; ok=0; j++; if (j<=n) j++; continue }
              d=d c; j++
            }
            if (!closed) { reliable=0; ok=0; d="" }
            if (!reliable) d=""
            # concatenated segments after a dollar-quoted piece → fail closed
            if (closed && j<=n && substr(line,j,1) !~ /[[:space:];&|()<>]/) { reliable=0; ok=0; d="" }
          } else while (j<=n) {
            c=substr(line,j,1)
            if (dst=="sq") {
              if (c=="\047") {
                dst=""; j++
                # word-concat after a closed quoted segment → fail closed
                if (j<=n && substr(line,j,1) !~ /[[:space:];&|()<>]/) { reliable=0; ok=0; d="" }
                continue
              }
              d=d c; j++; continue
            }
            if (dst=="dq") {
              if (c=="\"") {
                dst=""; j++
                if (j<=n && substr(line,j,1) !~ /[[:space:];&|()<>]/) { reliable=0; ok=0; d="" }
                continue
              }
              # any backslash inside double-quoted delimiter: do not decode; fail closed
              if (c=="\\") {
                reliable=0; ok=0; d=""
                j++
                while (j<=n) {
                  c=substr(line,j,1)
                  if (c=="\"") { dst=""; j++; break }
                  if (c=="\\") j++
                  j++
                }
                break
              }
              d=d c; j++; continue
            }
            if (c ~ /[[:space:];&|()<>]/) break
            # mid-word $ starts a concat / ANSI-C segment we do not fully decode
            if (c=="$") { reliable=0; ok=0; d=""; break }
            # unquoted prefix already in d then a quote => mixed X'Y' / X"Y" → fail closed
            if ((c=="\047" || c=="\"") && d!="") { reliable=0; ok=0; d=""; break }
            if (c=="\047") { q=1; dst="sq"; j++; continue }
            if (c=="\"") { q=1; dst="dq"; j++; continue }
            if (c=="\\") { ok=0; reliable=0; j++; if (j<=n) j++; break }
            d=d c; j++
          }
          # unterminated delim quotes → fail closed
          if (dst!="") ok=0
          # backslash-continued header: pipe/redir may sit on the next physical line
          if (unquoted_line_continues(line)) ok=0
          # rest of physical line still incomplete (quote / $( / <( / >( / backtick); # ends rest
          rest=substr(line,j)
          if (has_incomplete_local(rest)) ok=0
          sep=last_unquoted_sep(pref)
          simple=(sep>0)?substr(pref,sep+1):pref
          if (has_unquoted_pipe_or_procsub(simple) || has_unquoted_pipe_or_procsub(substr(line,j))) ok=0
          # quoted-empty delimiter is valid (terminator = empty line)
          if (dst=="" && reliable && ok && (d!="" || q)) {
            cons=first_consumer(pref)
            # never suppress after an earlier unreliable/untracked heredoc (queue order)
            enqueue(d, (q && is_inert_consumer(cons) && !no_suppress_rest), t)
          } else if (dst=="" && reliable && d!="") {
            # track without suppress so a later terminator does not leave us inside a body
            enqueue(d, 0, t)
          } else {
            # untracked / unreliable delim: poison later suppress so a following
            # inert cat <<'B' cannot hide an earlier executable body
            no_suppress_rest=1
          }
          i=j-1
        }
      }
      BEGIN { head=1; tail=0; qst=""; cont=0; exp_depth=0; bt_open=0; brace_depth=0; paren_depth=0; kw_depth=0; no_suppress_rest=0 }
      {
        if (head<=tail) {
          body=$0; cmp=body
          if (tabs[head]) sub(/^\t*/,"",cmp)
          if (!suppress_body[head]) print body
          if (cmp==delim[head]) head++
          next
        }
        print
        scan($0)
        cont=unquoted_line_continues($0)
        advance_globals($0)
      }
    ')"
    # Strict simple-form gate (prefer fail-closed over a full shell parser): keep
    # body suppression ONLY when the whole command is one standalone cat/tee
    # heredoc (optional blank lines, optional prefixes). Anything else → full scan.
    # Awk program uses \047 for quotes so it can live inside bash single quotes.
    if ! printf '%s\n' "$cmd" | awk '
      BEGIN { state=0; delim=""; tabs=0; q=sprintf("%c",39); bad=0 }
      {
        line=$0
        if (state==0) {
          if (line ~ /^[[:space:]]*$/) next
          # header without trailing comment (space/# or ;# — not glued )#suffix)
          h=line
          sub(/[ \t]+#.*$/, "", h)
          sub(/;#.*$/, "", h)
          # reject multi-statement / pipeline / groups on the header (after comment strip)
          if (h ~ /[|;&(){}]/) { bad=1; exit }
          # optional VAR=val and bare wrappers (no option flags — fail closed on env -P etc.)
          while (match(h, /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+/)) h=substr(h, RLENGTH+1)
          while (match(h, /^[[:space:]]*(sudo|command|env|nice|nohup|time)[[:space:]]+/)) {
            # next token must not be an option (operand-taking flags are not modeled)
            nxt=substr(h, RLENGTH+1, 1)
            if (nxt=="-" || nxt=="") { bad=1; exit }
            h=substr(h, RLENGTH+1)
          }
          sub(/^[[:space:]]+/, "", h)
          if (h !~ /^(cat|tee)([[:space:]]|$)/) { bad=1; exit }
          if (h !~ /<</) { bad=1; exit }
          # only one << on the header
          t=h; nlt=0; while (match(t, /<</)) { nlt++; t=substr(t, RSTART+2) }
          if (nlt!=1) { bad=1; exit }
          tabs=(h ~ /<<-/)
          if (!match(h, /<</)) { bad=1; exit }
          rest=substr(h, RSTART+2)
          if (substr(rest,1,1)=="-") rest=substr(rest,2)
          sub(/^[[:space:]]+/, "", rest)
          if (substr(rest,1,1)==q) {
            rest=substr(rest,2)
            p=index(rest,q); if (p==0) { bad=1; exit }
            delim=substr(rest,1,p-1)
            rest=substr(rest,p+1)
          } else if (length(rest)>=2 && substr(rest,1,1)=="$" && substr(rest,2,1)==q) {
            rest=substr(rest,3)
            p=index(rest,q); if (p==0) { bad=1; exit }
            delim=substr(rest,1,p-1)
            if (delim ~ /\\/) { bad=1; exit }
            rest=substr(rest,p+1)
          } else if (substr(rest,1,1)=="\"") {
            rest=substr(rest,2)
            p=index(rest,"\""); if (p==0) { bad=1; exit }
            delim=substr(rest,1,p-1)
            if (delim ~ /\\/) { bad=1; exit }
            rest=substr(rest,p+1)
          } else { bad=1; exit }
          # after delimiter: opaque TOKENs (args / redirect ops / targets) without |;&(){}
          while (rest!="") {
            sub(/^[[:space:]]+/, "", rest)
            if (rest=="") break
            if (!match(rest, /^[^[:space:]|;&(){}]+/)) { bad=1; exit }
            rest=substr(rest, RLENGTH+1)
          }
          state=1
          next
        }
        if (state==1) {
          cmp=line
          if (tabs) sub(/^\t*/, "", cmp)
          if (cmp==delim) { state=2; next }
          next
        }
        if (state==2) {
          if (line ~ /^[[:space:]]*$/) next
          bad=1
          next
        }
      }
      END { exit (state==2 && bad==0) ? 0 : 1 }
    '; then
      inert_stripped=$(printf '%s\n' "$cmd")
    fi
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
    destructive_stripped="$(printf '%s' "$inert_stripped" | tr -d '\042\047\134')"
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
    if printf '%s' "$destructive_stripped" | grep -Eq '(^|[;&|(`])[[:space:]]*'"$PFX"'(rm[[:space:]]+([^;&|`]*[[:space:]])?(--recursive|-[A-Za-z]*[rR][A-Za-z]*)([[:space:]]|$)|git'"$OPT"'[[:space:]]+push[[:space:]]([^;&|`]*[[:space:]])?(--force[^;&|`[:space:]]*|--mirror|--prune|--delete|-[A-Za-z]*[fd][A-Za-z]*|[+][^;&|`[:space:]]*|[:][^;&|`[:space:]]*)([[:space:]]|$)|git'"$OPT"'[[:space:]]+reset[[:space:]]+--hard[[:space:]]+origin)' \
       || printf '%s' "$inert_stripped" | grep -Eiq 'DROP[[:space:]]+(TABLE|DATABASE)'; then
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
      if printf '%s' "$inert_stripped" | grep -Eq ">>?[[:space:]]*[\"']?[^;|&]*${bp}" \
         || printf '%s' "$inert_stripped" | grep -Eq "(^|[;&|[:space:]])(tee|mv|cp|rm|truncate|dd|touch|install|ln|chmod)[[:space:]][^;|&]*${bp}" \
         || printf '%s' "$inert_stripped" | grep -Eq "(^|[;&|[:space:]])sed[[:space:]]+-[a-zA-Z]*i[^;|&]*${bp}"; then
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
      if printf '%s' "$inert_stripped" | grep -Eq ">>?[[:space:]]*[\"']?[^;|&]*${sp}" \
         || printf '%s' "$inert_stripped" | grep -Eq "(^|[;&|[:space:]])(tee|mv|cp|rm|truncate|dd|touch|install|ln|chmod)[[:space:]][^;|&]*${sp}" \
         || printf '%s' "$inert_stripped" | grep -Eq "(^|[;&|[:space:]])sed[[:space:]]+-[a-zA-Z]*i[^;|&]*${sp}"; then
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
