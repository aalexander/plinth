#!/usr/bin/env bash
# Plinth implementer-lane guard (shared, version-pinned). The safety-critical parts of the
# grok-implementer / codex-implementer lanes, as an ENFORCED, testable script — not a prompt
# convention. A delegated non-Claude implementer CLI does NOT inherit the `.claude/` guard and
# has whole-tree write, so this restores the fail-loud + scope guarantees around the delegated run.
#
# WHAT THIS IS, AND IS NOT — it catches ERRORS, not an adversarial sandbox. It flags a lane that
# went off-script: edited a tracked file outside the spec, a protected/version-pinned file, or a
# secret/sensitive path (`.env`, `secrets/`, `.plinth/session/`, …) — the mistakes a fallible
# implementer actually makes. It DELIBERATELY does NOT reject non-sensitive gitignored artifacts
# (node_modules/, dist/, build output): those are legitimate lane output, are not shipped
# (gitignored), and rejecting them would only break normal work (npm install, builds). It DOES
# report them — `scope` prints a non-blocking note that the lane's verification is not hermetic
# (it ran against un-reviewed ignored state), so the driver's Rule-10 re-run and CI's fresh install
# stay the authority. Bugs over adversarial intent: report, don't reject.
#
# EXPLICITLY OUT OF SCOPE (the lane runs a TRUSTED-but-fallible model, not an adversary — the
# security boundary is the vendor sandbox + human review, not this script). scope does NOT try
# to defeat a MALICIOUS lane's deliberate evasion: secret exfiltration through the CLI's
# web-search/fetch (web search is left ON — the worker needs it), a `chmod` on the far side of a
# pre-existing sensitive symlink, or a decoy status-check reference crafted to fool an advisory
# warning. Those are red-team hypotheticals against a trusted party; chasing them would trade the
# worker's real capability for hypothetical coverage. What scope DOES guarantee is that a fallible
# lane's ERRORS — off-spec tracked/staged edits (incl. rename/skip-worktree), protected-path or
# secret/session writes (incl. gitignored, content-through-a-file-symlink, git control-plane), and
# forged verdicts — are caught, or it fails closed.
#
#   lane-guard.sh preflight <grok|codex>
#       Binary present AND authenticated. Prints an "unavailable: <reason>" line and exits 3 if
#       not — the lane must return STATUS: unavailable, never silently implement the task itself.
#
#   lane-guard.sh snapshot
#       Print `<sha256>  <path>` for every existing SENSITIVE file — protected paths
#       (.plinth/protected-paths) OR secret paths (.env, secrets/, credentials/, .ssh/, .aws/,
#       id_rsa, id_ed25519), INCLUDING gitignored ones. The lane captures this BEFORE the run.
#
#   lane-guard.sh scope <baseref> [--snapshot <file>] <spec-file>...
#       After the run: every TRACKED change + NEW (non-ignored) file (vs baseref) must be a spec
#       file AND must not match a protected pattern; AND, given the pre-run --snapshot, no SENSITIVE
#       file (protected or secret, even gitignored) may have been added/changed/removed — that
#       catches a whole-tree-write lane planting secrets in `.env`/`secrets/` or a fake verdict under
#       `.plinth/session/`. Any breach prints "SCOPE VIOLATION: ..." and exits 4 (lane reports
#       partial, does NOT accept). Exits 5 (fail LOUD) if the diff is uncomputable (non-repo /
#       unresolvable base) — never accepts on an empty change list.
set -uo pipefail

# ── shared: the SENSITIVE set = protected-paths patterns + a builtin secret denylist ──
# Aligned with Plinth's own starter secret policy (templates/.gitignore: .env / .env.* / *.pem /
# *.key / id_rsa* / id_ed25519* / secrets/ / credentials/), component-boundaried at the NAME level
# (`.env`/`.env.local` yes but NOT `.envrc` — a different name entirely). Template/doc lookalikes
# (`.env.example`, `id_rsa_format.md`) are RECORDED like secrets and SPEC-GATED at scope time
# (SECRET_SAFE below) — not blind-exempt: those names are usually gitignored, so the snapshot is
# the only check that can see a lane writing real secrets into them.
# A file INSIDE an inherently-sensitive DIRECTORY is ALWAYS a secret regardless of its basename — no
# template/doc carve-out applies (secrets/.env.example / .ssh/id_rsa_format.md are still secrets):
SECRET_DIRS='(^|/)secrets/|(^|/)credentials/|(^|/)\.ssh/|(^|/)\.aws/|(^|/)\.env/|\.(pem|key)/'
# Secret FILES themselves; the SECRET_SAFE carve-out applies ONLY to these (a lookalike not in a dir):
SECRET_FILES='(^|/)\.env($|\.)|(^|/)id_(rsa|dsa|ecdsa|ed25519)|\.(pem|key)$'
# Template/doc LOOKALIKES: env templates, and DOCS *about* a key — the key basename plus a
# DESCRIPTIVE suffix and a doc extension (id_rsa_format.md, id_rsa_notes.txt). NOT the bare key
# basename + extension (id_rsa.txt / id_ed25519.md), which could be a real key dumped to a doc ext.
# These are a SUBSET of SECRET_FILES (recorded in the snapshot like any secret name); at scope
# time a snapshot-diff on one is AUTHORIZED only when the spec explicitly lists it:
SECRET_SAFE='(^|/)\.env\.(example|sample|template|dist|defaults?)$|(^|/)id_(rsa|dsa|ecdsa|ed25519)_[a-z0-9_]+\.(md|markdown|txt|rst)$'
prot_pats() { [ -f .plinth/protected-paths ] && grep -Ev '^[[:space:]]*(#|$)' .plinth/protected-paths 2>/dev/null || true; }
# The ACTIVE pattern set for sensitivity checks. scope sets LG_PROT_UNION to the
# BASE-unioned policy before re-snapshotting, so a lane that NARROWS the working-tree
# .plinth/protected-paths cannot hide a base-pattern-matching gitignored addition from
# the post-run snapshot (the tracked-path check already uses the same union).
active_pats() { if [ -n "${LG_PROT_UNION:-}" ]; then printf '%s\n' "$LG_PROT_UNION"; else prot_pats; fi; }
validate_prot_pats() {  # fail LOUD (exit 5) on an INVALID active protected-paths regex — a malformed
  # pattern must never silently narrow protection (grep exit 2 would otherwise fall through as no-match).
  # FIRST prove we can actually CREATE a temp file in the dir bash uses for here-doc/here-string temps
  # (${TMPDIR:-/tmp}). scope's violation loops rely on those redirections; if creation fails (read-only,
  # non-searchable, ACL, quota, ENOSPC, …) they fail SILENTLY, the loops are skipped, and scope would
  # print "scope ok" for an out-of-spec diff. A real create/remove probe (not a weak `-w`) catches
  # every create-time failure. mktemp WITH a path template respects the dir (bare mktemp falls back).
  local __td="${TMPDIR:-/tmp}" __p
  __p="$(mktemp "$__td/lg-probe.XXXXXX" 2>/dev/null)" || { echo "lane-guard: cannot create a temp file in '$__td' — refusing to run (fail closed)" >&2; exit 5; }
  rm -f "$__p"
  # A protected-paths that is PRESENT but not a readable regular file (unreadable, a directory, a
  # device, or ANY symlink) must fail closed — prot_pats' `[ -f ]` follows symlinks and would read it
  # as "no patterns"; worse, scope's `git show base:.plinth/protected-paths` returns a symlink's
  # TARGET TEXT rather than the pointed-to policy, silently narrowing the base-union defense:
  if [ -L .plinth/protected-paths ]; then
    echo "lane-guard: .plinth/protected-paths is a symlink — refusing to run (fail closed; policy must be a real file)" >&2; exit 5
  fi
  if [ -e .plinth/protected-paths ] && { [ ! -f .plinth/protected-paths ] || [ ! -r .plinth/protected-paths ]; }; then
    echo "lane-guard: .plinth/protected-paths is present but not a readable regular file — refusing to run (fail closed)" >&2; exit 5
  fi
  local pat
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    grep -E "$pat" </dev/null 2>/dev/null; [ "$?" -le 1 ] || {
      echo "lane-guard: .plinth/protected-paths has an INVALID regex ($pat) — refusing to run (fail closed)" >&2; exit 5; }
  done < <(prot_pats)
}
sens_match() {  # <path> -> 0 if SENSITIVE (a git-visible secret/protected path). Git control-plane
  # files are NOT classified here — sens_snapshot records them DIRECTLY (it resolves the real
  # gitdir and knows they are control-plane), so no path-name heuristic can miss an unusual
  # gitdir layout (separate-git-dir, linked worktree). ORDER: an explicit
  # protected-paths pattern ALWAYS wins; then anything inside a secret DIRECTORY is sensitive
  # regardless of basename; then the secret-FILE names — which INCLUDE the SECRET_SAFE lookalikes
  # (they are recorded here, and spec-gated at scope time, never blind-exempt).
  local pat; while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    printf '%s' "$1" | grep -Eq "$pat" && return 0
  done < <(active_pats)
  printf '%s' "$1" | grep -Eq "$SECRET_DIRS"  && return 0   # inside secrets/ credentials/ .ssh/ .aws/ .env/ *.pem/ *.key/
  printf '%s' "$1" | grep -Eq "$SECRET_FILES" && return 0   # secret names incl. template lookalikes (.env*, id_rsa*, *.pem, *.key)
  return 1
}
hashof() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1 || sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
modeof() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null; }  # perm bits — GNU (-c) first;
modeof_deref() { stat -L -c '%a' "$1" 2>/dev/null || stat -Lf '%p' "$1" 2>/dev/null | sed 's/.*\(...\)$/\1/'; }  # FOLLOW the link:
  # referent mode, not the link's own. GNU -L; BSD -Lf '%p' (full mode; take the low 3 perm digits).
  # BSD stat rejects -c and falls through to -f. The reverse order is WRONG: GNU `stat -f` SUCCEEDS
  # (filesystem status, not the file's mode) so the `||` would never fall through on Linux.
sens_snapshot() {  # `<f1> <f2>  <path>` per sensitive node: `<sha> <mode>` for a regular file, or
  # `symlink <target>` for a symlink — so a secret replaced by (or repointed to) a symlink is detected.
  # Enumerates git-visible paths (tracked + ignored + untracked FILES incl. secrets under a
  # secret-named dir). BOUND: an EMPTY sensitive directory (e.g. an empty `secrets/`) is not git-
  # enumerated and so isn't recorded — but an empty dir holds no secret, so this is vacuous; any
  # secret FILE placed inside it IS enumerated and caught. (efficiency-over-adversarial on a trusted lane.)
  # Git CONTROL-PLANE state is never git-enumerated but is writable by a whole-tree lane,
  # and these surfaces weaponize silently: a planted .git/hooks/* (regular OR SYMLINK)
  # executes code on the driver's next git command, .git/config can redirect
  # remotes/hooks-path, .git/info/exclude can hide files from every git listing, and a ref
  # rewrite (.git/HEAD, .git/refs/**, .git/packed-refs) can move what the branch points at.
  # Snapshot them all; symlinks are recorded by target (below), so a symlinked hook is caught.
  # BOUND (deliberate): .git/index is excluded — a read-side `git status`/`git diff` refreshes
  # its stat cache on a CLEAN run, so covering it would false-flag; and it is not a content
  # authority anyway (the scope check diffs against the immutable BEFORE *sha*, not a ref, so
  # neither an index-flag change nor a ref rewrite can hide a working-tree content change).
  # Resolve the REAL git dirs — `.git` is a directory in a normal clone but a FILE in a
  # linked worktree (the lane docs recommend one worktree per lane), so hardcoding `.git/`
  # would miss the control plane there. GIT_DIR = per-worktree (HEAD, refs, index);
  # GIT_COMMON = shared (config, hooks, packed-refs, info/exclude). Both may equal `.git`.
  local GITDIR GITCOMMON
  GITDIR="$(git rev-parse --git-dir 2>/dev/null)"; GITCOMMON="$(git rev-parse --git-common-dir 2>/dev/null)"
  # TWO tagged sources into one record loop (tab-separated tag<TAB>path):
  #   G = git-visible file — GATE through sens_match (secret/protected classification)
  #   C = control-plane file — the enumeration ALREADY knows it is control-plane (it resolved
  #       the real gitdir), so record it UNCONDITIONALLY; no path-name heuristic to miss an
  #       unusual gitdir layout (separate-git-dir, linked worktree, arbitrarily-named gitdir).
  { { git ls-files -c 2>/dev/null; git ls-files -o -i --exclude-standard 2>/dev/null; \
      git ls-files -o --exclude-standard 2>/dev/null; } | sed 's/^/G\t/'; \
    { for cp in "$GITCOMMON/config" "$GITDIR/config.worktree" "$GITCOMMON/info/exclude" "$GITCOMMON/packed-refs" "$GITDIR/HEAD"; do \
        [ -n "${cp#/}" ] && [ -e "$cp" ] && printf '%s\n' "$cp"; done; \
      find "$GITCOMMON/hooks" "$GITDIR/refs" "$GITCOMMON/refs" \( -type f -o -type l \) 2>/dev/null | grep -v '\.sample$'; :; } | sed 's/^/C\t/'; } \
    | sort -u | while IFS="$(printf '\t')" read -r tag f; do
    if [ "$tag" = G ]; then
      # ONLY the hook-appended event log is excluded — pulse.sh appends `.plinth/session/events.jsonl`
      # on every PostToolUse DURING the lane run, so comparing it would false-flag every clean lane.
      # The REST of `.plinth/session/` (verdict.json, run receipts) stays in scope: a whole-tree lane
      # bypasses the Claude guard and could otherwise forge local gate/dashboard state.
      # ROOT feed only: a SUBDIR copy (subdir/.plinth/session/events.jsonl) matches the protected
      # policy and stays fully enforced (an overbroad glob here was a carve-out escape).
      case "$f" in .plinth/session/events.jsonl) continue ;; esac
      sens_match "$f" || continue
    fi
    if [ -L "$f" ]; then
      # Record the link TARGET (so a repoint is caught) AND, when the target resolves to a
      # regular file, the referent's content hash — else a WRITE-THROUGH a pre-existing
      # sensitive symlink (target string unchanged, content changed) would compare equal.
      # Fail closed if the target is present-but-unhashable (a forgeable empty record).
      lt="$(readlink "$f" 2>/dev/null || echo '?')"
      if [ -f "$f" ]; then   # -f follows the link: true iff it resolves to a regular file
        th="$(hashof "$f")"; tm="$(modeof_deref "$f")"   # deref: referent content + referent MODE (chmod-on-target caught)
        { [ -n "$th" ] && [ -n "$tm" ]; } || { echo "lane-guard: cannot hash/stat symlink referent for '$f' — refusing (fail closed)" >&2; exit 5; }
        printf 'symlink %s %s %s  %s\n' "$lt" "$th" "$tm" "$f"   # target + referent content + mode
      elif [ -d "$f" ]; then
        # A sensitive path that is a symlink to a DIRECTORY is the write-through vector
        # (a lane writes `<sensitive>/x`, which lands in the external target dir, invisible
        # to git under the sensitive name). A legitimate secret is never a dir-symlink —
        # fail closed rather than record target-only.
        echo "lane-guard: sensitive path '$f' is a symlink to a DIRECTORY — refusing (fail closed; a secret path must not be a dir-symlink)" >&2
        exit 5
      else
        printf 'symlink %s - -  %s\n' "$lt" "$f"   # dangling / special target: no content to hide
      fi
    elif [ -f "$f" ]; then
      h="$(hashof "$f")"; m="$(modeof "$f")"
      # FAIL CLOSED if a sensitive file cannot be hashed OR statted (e.g. an unreadable mode-000 .env):
      # an empty hash/mode is a forgeable-looking record a lane could chmod/modify/restore past.
      if [ -z "$h" ] || [ -z "$m" ]; then
        echo "lane-guard: cannot hash/stat sensitive file '$f' — refusing (fail closed)" >&2
        exit 5
      fi
      printf '%s %s  %s\n' "$h" "$m" "$f"
    else
      printf 'special present  %s\n' "$f"   # a dir/FIFO/socket/device at a sensitive path — record its presence
    fi
  done | sort
}

sub="${1:-}"; shift 2>/dev/null || true
case "$sub" in
  preflight)
    v="${1:-}"
    case "$v" in
      grok)
        command -v grok >/dev/null 2>&1 || { echo "unavailable: grok not on PATH — install https://x.ai/cli"; exit 3; }
        grok models >/dev/null 2>&1     || { echo "unavailable: grok not signed in — run 'grok login'"; exit 3; } ;;
      codex)
        command -v codex >/dev/null 2>&1   || { echo "unavailable: codex not on PATH — install the codex CLI"; exit 3; }
        codex login status >/dev/null 2>&1 || { echo "unavailable: codex not signed in — run 'codex login'"; exit 3; } ;;
      *) echo "usage: lane-guard.sh preflight <grok|codex>"; exit 2 ;;
    esac
    echo "ready: $v" ;;

  snapshot)
    git rev-parse --git-dir >/dev/null 2>&1 || { echo "snapshot: not inside a git repo" >&2; exit 5; }
    validate_prot_pats
    sens_snapshot ;;

  scope)
    base="${1:-}"; shift 2>/dev/null || true
    snapfile=""
    # --snapshot given with an empty/missing value must FAIL, not silently drop to
    # no-snapshot mode — the caller asked for the sensitive baseline; a typo that
    # skips it would fail open. (With a non-empty value, `shift 2` is safe.)
    if [ "${1:-}" = "--snapshot" ]; then
      snapfile="${2:-}"
      [ -n "$snapfile" ] || { echo "scope: --snapshot requires a file argument — refusing to run without the sensitive baseline (fail closed)" >&2; exit 2; }
      shift 2
    fi
    [ -n "$base" ] && [ "$#" -gt 0 ] || { echo "usage: lane-guard.sh scope <baseref> [--snapshot <file>] <spec-file>..."; exit 2; }
    # Fail LOUD if the diff cannot be computed — an unresolvable base / non-repo must NOT yield an
    # empty change list that then prints "scope ok" (that would accept the lane's work unchecked).
    git rev-parse --git-dir >/dev/null 2>&1 || { echo "scope: not inside a git repo — refusing to accept the lane"; exit 5; }
    git rev-parse --verify --quiet "${base}^{commit}" >/dev/null 2>&1 || { echo "scope: cannot resolve baseref '${base}' — the diff is uncomputable; refusing to accept the lane"; exit 5; }
    validate_prot_pats  # a malformed protected-paths regex must fail loud, not silently un-protect a path
    # --no-renames: with diff.renames enabled, a rename from an OUT-OF-SPEC path to an
    # in-spec name would list only the new path — the old file's deletion would escape
    # the scope check. Force delete+add so BOTH paths are checked against the spec.
    # BOTH working-tree AND staged (--cached) vs base: a lane could `git add` an out-of-spec
    # change and revert the working tree, leaving `git diff $base` clean while the INDEX holds
    # the change (the driver's later `git commit` would ship it) — union catches that.
    dif="$( { git diff --name-only --no-renames "$base"; git diff --cached --name-only --no-renames "$base"; } | sort -u )" \
      || { echo "scope: 'git diff' against '${base}' failed — refusing to accept the lane"; exit 5; }
    # HIDDEN INDEX BITS: assume-unchanged (lowercase status letter) / skip-worktree (S) make
    # git diff/ls-files SKIP a modified tracked file — a lane could set them to sneak an
    # out-of-spec edit past the enumeration above. They are never normal lane state; fail closed.
    hidden="$(git ls-files -v 2>/dev/null | grep -E '^([a-z]|S)' | sed 's/^..//' || true)"
    if [ -n "$hidden" ]; then
      echo "scope: tracked paths carry assume-unchanged/skip-worktree bits (git diff would skip them) — refusing (fail closed):" >&2
      printf '  %s\n' $hidden >&2
      exit 4
    fi
    unt="$(git ls-files --others --exclude-standard)" || { echo "scope: 'git ls-files' failed — refusing to accept the lane"; exit 5; }
    # The hook-appended event feed is excluded here as well as in the snapshot: pulse.sh
    # appends it on every tool use during a hooked lane run, and a project whose preserved
    # .gitignore does not ignore it would otherwise false-flag every clean lane.
    changed="$( { printf '%s\n' "$dif"; printf '%s\n' "$unt"; } | sort -u | grep -vE '^\.plinth/session/events\.jsonl$' || true )"
    # Read the protected-path POLICY from the ratified BASE and UNION it with the working tree, so a
    # lane cannot NARROW protection by editing .plinth/protected-paths in its own run (base patterns
    # always apply; tree additions are honored — only ever stricter). Mirrors review.sh reading policy
    # from the base ref. Validate the union too: an invalid base regex must fail loud, not un-protect.
    # The BASE policy object must be a regular file blob. If base has .plinth/protected-paths as a
    # SYMLINK (mode 120000) or a TREE (040000), `git show base:` returns the link's target text or
    # nothing — silently narrowing the base-union defense. Fail closed on any non-regular base object.
    bmode="$(git ls-tree "$base" -- .plinth/protected-paths 2>/dev/null | awk '{print $1}')"
    case "$bmode" in
      ''|100644|100755) : ;;  # absent (nothing to narrow) or a regular blob — OK
      *) echo "scope: base .plinth/protected-paths is not a regular file (git mode $bmode) — refusing to run (fail closed)" >&2; exit 5 ;;
    esac
    base_prot="$(git show "${base}:.plinth/protected-paths" 2>/dev/null | grep -Ev '^[[:space:]]*(#|$)' || true)"
    # `|| true`: an EMPTY pattern set (no protected-paths anywhere) is legitimate — grep -v
    # then exits 1 under pipefail, which must read as "no patterns", not as a failure.
    all_prot="$(printf '%s\n%s\n' "$base_prot" "$(prot_pats)" | grep -vE '^[[:space:]]*$' | sort -u || true)"
    while IFS= read -r p; do [ -n "$p" ] || continue; grep -E "$p" </dev/null 2>/dev/null; [ "$?" -le 1 ] || { echo "scope: .plinth/protected-paths (base or tree) has an INVALID regex ($p) — refusing to run (fail closed)" >&2; exit 5; }; done <<< "$all_prot"
    protected() { local p; while IFS= read -r p; do [ -n "$p" ] || continue; printf '%s' "$1" | grep -Eq "$p" && return 0; done <<< "$all_prot"; return 1; }
    in_spec() { local f="$1" a; shift; for a in "$@"; do [ "$f" = "$a" ] && return 0; done; return 1; }
    viol=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if protected "$f"; then viol="${viol}  ${f} — PROTECTED path (a version-pinned/off-limits file)
"
      elif ! in_spec "$f" "$@"; then viol="${viol}  ${f} — outside the spec's file list
"
      fi
    done <<CHANGED
$changed
CHANGED
    # Sensitive-path guard: catches gitignored writes (secrets, .plinth/session/, …) that git diff
    # cannot attribute. Requires the pre-run snapshot; without it, those paths are NOT verified.
    if [ -n "$snapfile" ]; then
      [ -f "$snapfile" ] && [ -r "$snapfile" ] || { echo "scope: --snapshot file '$snapfile' missing or unreadable — refusing to accept the lane"; exit 5; }
      # Re-snapshot against the BASE-unioned policy (all_prot), not the working tree's —
      # a lane-narrowed .plinth/protected-paths must not shrink the sensitive set here:
      LG_PROT_UNION="$all_prot"
      after="$(sens_snapshot)" || { echo "scope: could not re-snapshot sensitive files (a sensitive file is unhashable/unstattable) — refusing (fail closed)" >&2; exit 5; }
      LG_PROT_UNION=""
      # A failed read must not become an empty baseline (it would mis-attribute or, with no
      # sensitive files present, silently verify nothing) — fail closed instead.
      before="$(cat "$snapfile")" || { echo "scope: cannot read --snapshot file '$snapfile' — refusing (fail closed)" >&2; exit 5; }
      if [ "$before" != "$after" ]; then
        # strip the diff marker + the two record fields (`<sha> <mode>` or `symlink <target>`) + the
        # two-space separator, leaving just the path:
        # Split the diff from the extraction and gate on ITS exit code: rc=1 is the expected
        # "files differ"; rc>1 is diff TROUBLE, and letting it yield an empty `touched` would
        # silently pass a lane that changed sensitive paths (fail closed instead). Note the
        # script runs pipefail WITHOUT -e, so a failing assignment never aborts by itself.
        drc=0; dout="$(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") 2>/dev/null)" || drc=$?
        [ "$drc" -le 1 ] || { echo "scope: could not diff the sensitive snapshots (diff rc=$drc) — refusing to accept the lane (fail closed)" >&2; exit 5; }
        touched="$(printf '%s\n' "$dout" | grep -E '^[<>]' | sed -E 's/^[<>] +[^ ]+ +[^ ]+  //' | sort -u || true)"
        while IFS= read -r f; do
          [ -n "$f" ] || continue
          # SPEC-GATED template lookalikes: a SECRET_SAFE name (.env.example, id_rsa_notes.txt)
          # explicitly listed in the spec is legitimate project work — authorize exactly that.
          # Never authorizable: a real secret name, anything inside a secret DIRECTORY, or a
          # protected path (same precedence as sens_match).
          if printf '%s' "$f" | grep -Eq "$SECRET_SAFE" \
             && ! printf '%s' "$f" | grep -Eq "$SECRET_DIRS" \
             && ! protected "$f" && in_spec "$f" "$@"; then
            continue
          fi
          viol="${viol}  ${f} — SENSITIVE path added/changed/removed by the lane (secret or protected)
"
        done <<TOUCHED
$touched
TOUCHED
      fi
    else
      echo "scope: NOTE — no --snapshot given; gitignored sensitive paths (secrets, .plinth/session/) were not verified" >&2
    fi
    # Non-blocking HERMETICITY note (report, don't reject). Ignored build artifacts (node_modules/,
    # dist/, …) are legitimate lane output and are NOT rejected — but the lane's verification ran
    # against them, so that Rule-10 evidence may not reproduce in a clean env. Surface the top-level
    # ignored entries so the driver's independent re-run accounts for it; CI's fresh install is the
    # authority. This closes "silently accepted" without breaking npm install / builds.
    # Exclude Plinth's own session state from the note: it is not un-reviewed build input
    # (verdicts/receipts are sensitive-COMPARED above; the event feed is hook-appended), and
    # naming `.plinth` here would false-fire the warning on every hooked Claude lane run.
    iga="$(git ls-files -o -i --exclude-standard 2>/dev/null | grep -Ev '^\.plinth/session(/|$)' | sed 's#/.*##' | sort -u | grep -v '^$' || true)"
    if [ -n "$iga" ]; then
      echo "scope note: verification is NOT hermetic — ignored artifacts in the tree (not in the reviewed diff): $(printf '%s' "$iga" | tr '\n' ' ')" >&2
      echo "  -> your independent Rule-10 re-run may depend on this un-reviewed state; treat CI's fresh install as the authority." >&2
    fi
    if [ -n "$viol" ]; then
      printf 'SCOPE VIOLATION — the lane touched paths it was not authorized to:\n%s' "$viol"
      exit 4
    fi
    if [ -n "$snapfile" ]; then
      echo "scope ok: tracked changes + new files within the spec; no protected path; no sensitive/secret path touched (per snapshot); ignored build artifacts reported, not rejected"
    else
      echo "scope ok: tracked changes + new files within the spec; no protected path. NOTE: no --snapshot given — gitignored sensitive paths (secrets, .plinth/session/) were NOT verified"
    fi ;;

  *) echo "usage: lane-guard.sh preflight <grok|codex> | snapshot | scope <baseref> [--snapshot <file>] <spec-file>..."; exit 2 ;;
esac
