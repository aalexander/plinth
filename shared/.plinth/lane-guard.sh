#!/usr/bin/env bash
# Plinth implementer-lane guard (shared, version-pinned). The safety-critical parts of the
# grok-implementer / codex-implementer lanes, as an ENFORCED, testable script — not a prompt
# convention. A delegated non-Claude implementer CLI does NOT inherit the `.claude/` guard, so
# this restores the fail-loud and protected-path/scope guarantees around the delegated run.
#
#   lane-guard.sh preflight <grok|codex>
#       Binary present AND authenticated. Prints an "unavailable: <reason>" line and exits 3 if
#       not — the lane must return STATUS: unavailable, never silently implement the task itself.
#
#   lane-guard.sh scope <baseref> <spec-file>...
#       After the lane run, every changed/new path (vs baseref, plus untracked) must be one of the
#       spec's files AND must not match any .plinth/protected-paths pattern. Prints
#       "SCOPE VIOLATION: ..." and exits 4 otherwise — the lane reports partial and does NOT accept
#       the diff (a delegated CLI can write anywhere; this is where that is caught, in-session).
set -uo pipefail

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
  scope)
    base="${1:-}"; shift 2>/dev/null || true
    [ -n "$base" ] && [ "$#" -gt 0 ] || { echo "usage: lane-guard.sh scope <baseref> <spec-file>..."; exit 2; }
    changed="$( { git diff --name-only "$base" 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | sort -u )"
    pats=""; [ -f .plinth/protected-paths ] && pats="$(grep -Ev '^[[:space:]]*(#|$)' .plinth/protected-paths 2>/dev/null || true)"
    protected() {  # <path> -> 0 if it matches any active protected pattern
      [ -n "$pats" ] || return 1
      printf '%s\n' "$pats" | while IFS= read -r pat; do
        [ -n "$pat" ] || continue
        printf '%s' "$1" | grep -Eq "$pat" && { echo hit; break; }
      done | grep -q hit
    }
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
    if [ -n "$viol" ]; then
      printf 'SCOPE VIOLATION — the lane edited paths it was not authorized to:\n%s' "$viol"
      exit 4
    fi
    echo "scope ok: all changes are spec files; no protected path touched" ;;
  *) echo "usage: lane-guard.sh preflight <grok|codex> | scope <baseref> <spec-file>..."; exit 2 ;;
esac
