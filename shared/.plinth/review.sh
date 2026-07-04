#!/usr/bin/env bash
# Plinth adversarial review (shared, version-pinned). Read-only review of the current
# branch vs base, by the second model. Subscription-funded via the codex CLI login.
# Reviewer model is set in ~/.codex/config.toml — swap it there, not here.
set -euo pipefail
base="${1:-main}"
diff=$(git diff "origin/${base}...HEAD" 2>/dev/null || git diff "${base}...HEAD" 2>/dev/null || true)
if [ -z "$diff" ]; then
  echo "Plinth: no diff against ${base} — nothing to review."
  exit 0
fi
prompt="You are an independent adversarial reviewer. Follow the rules in AGENTS.md.
Review this diff against SPEC.md (and GOAL.md if present). Find bugs, missing or
hollow tests, security issues, scope creep, and — for GOAL.md tasks — metric gaming.
Give concrete file:line findings and end with a verdict: CHANGES_NEEDED or APPROVED.

DIFF:
${diff}"
# 'codex exec' = non-interactive; '--sandbox read-only' prevents edits.
# Verify these flag names against your installed codex version if it errors.
codex exec --sandbox read-only "$prompt"
