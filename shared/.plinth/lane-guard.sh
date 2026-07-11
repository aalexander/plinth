#!/usr/bin/env bash
# Plinth implementer-lane guard (shared, version-pinned). The safety-critical parts of the
# grok-implementer / codex-implementer lanes, as an ENFORCED, testable script — not a prompt
# convention. A delegated non-Claude implementer CLI does NOT inherit the `.claude/` guard and
# has whole-tree write, so this restores the fail-loud + scope guarantees around the delegated run.
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
SECRET_PATS='(^|/)\.env|(^|/)secrets/|(^|/)credentials/|(^|/)\.ssh/|(^|/)\.aws/|id_rsa|id_ed25519'
prot_pats() { [ -f .plinth/protected-paths ] && grep -Ev '^[[:space:]]*(#|$)' .plinth/protected-paths 2>/dev/null || true; }
sens_match() {  # <path> -> 0 if it matches a protected OR secret pattern
  printf '%s' "$1" | grep -Eq "$SECRET_PATS" && return 0
  local pat; while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    printf '%s' "$1" | grep -Eq "$pat" && return 0
  done < <(prot_pats)
  return 1
}
hashof() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1 || sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
sens_snapshot() {  # `<sha>  <path>` for every existing sensitive file (tracked + ignored), sorted
  { git ls-files -c 2>/dev/null; git ls-files -o -i --exclude-standard 2>/dev/null; \
    git ls-files -o --exclude-standard 2>/dev/null; } | sort -u | while IFS= read -r f; do
    [ -f "$f" ] || continue
    if sens_match "$f"; then printf '%s  %s\n' "$(hashof "$f")" "$f"; fi
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
    dif="$(git diff --name-only "$base")" || { echo "scope: 'git diff' against '${base}' failed — refusing to accept the lane"; exit 5; }
    unt="$(git ls-files --others --exclude-standard)" || { echo "scope: 'git ls-files' failed — refusing to accept the lane"; exit 5; }
    changed="$( { printf '%s\n' "$dif"; printf '%s\n' "$unt"; } | sort -u )"
    protected() { local p; while IFS= read -r p; do [ -n "$p" ] || continue; printf '%s' "$1" | grep -Eq "$p" && return 0; done < <(prot_pats); return 1; }
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
        touched="$(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") 2>/dev/null | grep -E '^[<>]' | sed -E 's/^[<>] +[0-9a-f]+  //' | sort -u)"
        while IFS= read -r f; do [ -n "$f" ] && viol="${viol}  ${f} — SENSITIVE path added/changed/removed by the lane (secret or protected)
"; done <<TOUCHED
$touched
TOUCHED
      fi
    else
      echo "scope: NOTE — no --snapshot given; gitignored sensitive paths (secrets, .plinth/session/) were not verified" >&2
    fi
    if [ -n "$viol" ]; then
      printf 'SCOPE VIOLATION — the lane touched paths it was not authorized to:\n%s' "$viol"
      exit 4
    fi
    echo "scope ok: tracked changes + new files within the spec; no protected path; no sensitive/secret path touched (per snapshot)" ;;

  *) echo "usage: lane-guard.sh preflight <grok|codex> | snapshot | scope <baseref> [--snapshot <file>] <spec-file>..."; exit 2 ;;
esac
