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
# *.key / id_rsa* / id_ed25519* / secrets/ / credentials/), but component-boundaried so real secret
# files are flagged and lookalikes are not: `.env`/`.env.local` yes but NOT `.envrc`; `id_rsa` /
# `id_rsa_backup` / `id_ed25519` yes but NOT the doc `id_rsa_format.md` (SECRET_SAFE below).
SECRET_PATS='(^|/)\.env($|\.)|(^|/)secrets/|(^|/)credentials/|(^|/)\.ssh/|(^|/)\.aws/|(^|/)id_(rsa|dsa|ecdsa|ed25519)|\.(pem|key)$'
# Known-safe lookalikes: env templates (no real values), and DOCS about a key file (not the key):
SECRET_SAFE='(^|/)\.env\.(example|sample|template|dist|defaults?)$|(^|/)id_[a-z0-9_]+\.(md|markdown|txt|rst)$'
prot_pats() { [ -f .plinth/protected-paths ] && grep -Ev '^[[:space:]]*(#|$)' .plinth/protected-paths 2>/dev/null || true; }
validate_prot_pats() {  # fail LOUD (exit 5) on an INVALID active protected-paths regex — a malformed
  # pattern must never silently narrow protection (grep exit 2 would otherwise fall through as no-match).
  # A protected-paths that is PRESENT but not a readable regular file (unreadable, a directory, a
  # broken symlink, a device…) must fail closed — prot_pats' `[ -f ]` would otherwise read it as
  # "no patterns" and silently disable all protection:
  if [ -L .plinth/protected-paths ] && [ ! -e .plinth/protected-paths ]; then
    echo "lane-guard: .plinth/protected-paths is a broken symlink — refusing to run (fail closed)" >&2; exit 5
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
sens_match() {  # <path> -> 0 if SENSITIVE: an explicit protected-paths pattern (ALWAYS wins), OR a
  # secret path minus known-safe templates. Order matters: a project that deliberately protects
  # .env.example must still have it flagged; the SECRET_SAFE carve-out only exempts from the builtin
  # secret DENYLIST, never from an explicit protected-paths entry.
  local pat; while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    printf '%s' "$1" | grep -Eq "$pat" && return 0
  done < <(prot_pats)
  printf '%s' "$1" | grep -Eq "$SECRET_SAFE" && return 1   # a template (.env.example, …) is not a *secret* per se
  printf '%s' "$1" | grep -Eq "$SECRET_PATS" && return 0
  return 1
}
hashof() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1 || sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
modeof() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null; }  # perm bits (macOS/Linux)
sens_snapshot() {  # `<sha> <mode>  <path>` for every existing sensitive file (tracked + ignored), sorted
  { git ls-files -c 2>/dev/null; git ls-files -o -i --exclude-standard 2>/dev/null; \
    git ls-files -o --exclude-standard 2>/dev/null; } | sort -u | while IFS= read -r f; do
    [ -f "$f" ] || continue
    if sens_match "$f"; then printf '%s %s  %s\n' "$(hashof "$f")" "$(modeof "$f")" "$f"; fi
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
    if [ "${1:-}" = "--snapshot" ]; then snapfile="${2:-}"; shift 2 2>/dev/null || true; fi
    [ -n "$base" ] && [ "$#" -gt 0 ] || { echo "usage: lane-guard.sh scope <baseref> [--snapshot <file>] <spec-file>..."; exit 2; }
    # Fail LOUD if the diff cannot be computed — an unresolvable base / non-repo must NOT yield an
    # empty change list that then prints "scope ok" (that would accept the lane's work unchecked).
    git rev-parse --git-dir >/dev/null 2>&1 || { echo "scope: not inside a git repo — refusing to accept the lane"; exit 5; }
    git rev-parse --verify --quiet "${base}^{commit}" >/dev/null 2>&1 || { echo "scope: cannot resolve baseref '${base}' — the diff is uncomputable; refusing to accept the lane"; exit 5; }
    validate_prot_pats  # a malformed protected-paths regex must fail loud, not silently un-protect a path
    dif="$(git diff --name-only "$base")" || { echo "scope: 'git diff' against '${base}' failed — refusing to accept the lane"; exit 5; }
    unt="$(git ls-files --others --exclude-standard)" || { echo "scope: 'git ls-files' failed — refusing to accept the lane"; exit 5; }
    changed="$( { printf '%s\n' "$dif"; printf '%s\n' "$unt"; } | sort -u )"
    # Read the protected-path POLICY from the ratified BASE and UNION it with the working tree, so a
    # lane cannot NARROW protection by editing .plinth/protected-paths in its own run (base patterns
    # always apply; tree additions are honored — only ever stricter). Mirrors review.sh reading policy
    # from the base ref. Validate the union too: an invalid base regex must fail loud, not un-protect.
    base_prot="$(git show "${base}:.plinth/protected-paths" 2>/dev/null | grep -Ev '^[[:space:]]*(#|$)' || true)"
    all_prot="$(printf '%s\n%s\n' "$base_prot" "$(prot_pats)" | grep -vE '^[[:space:]]*$' | sort -u)"
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
      [ -f "$snapfile" ] || { echo "scope: --snapshot file '$snapfile' missing — refusing to accept the lane"; exit 5; }
      after="$(sens_snapshot)"; before="$(cat "$snapfile")"
      if [ "$before" != "$after" ]; then
        touched="$(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") 2>/dev/null | grep -E '^[<>]' | sed -E 's/^[<>] +[0-9a-f]+ +[0-9]+  //' | sort -u)"
        while IFS= read -r f; do [ -n "$f" ] && viol="${viol}  ${f} — SENSITIVE path added/changed/removed by the lane (secret or protected)
"; done <<TOUCHED
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
    iga="$(git ls-files -o -i --exclude-standard 2>/dev/null | sed 's#/.*##' | sort -u | grep -v '^$' || true)"
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
