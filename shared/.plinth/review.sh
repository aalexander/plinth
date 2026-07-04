#!/usr/bin/env bash
# Plinth adversarial review (shared, version-pinned). Read-only review of the
# current branch vs base, by the second model. Subscription-funded via the codex
# CLI login. Reviewer model is set in ~/.codex/config.toml — swap it there.
set -euo pipefail
base="${1:-main}"

# Canonical spec location: .plinth/config spec_path (file or directory).
SPEC_PATH="SPEC.md"
if [ -f ".plinth/config" ]; then
  v="$(sed -n 's/^spec_path[[:space:]]*=[[:space:]]*//p' .plinth/config | head -1)"
  [ -n "$v" ] && SPEC_PATH="$v"
fi

diff=$(git diff "origin/${base}...HEAD" 2>/dev/null || git diff "${base}...HEAD" 2>/dev/null || true)
if [ -z "$diff" ]; then
  echo "Plinth: no diff against ${base} — nothing to review."
  exit 0
fi
prompt="You are an independent adversarial reviewer. Follow the rules in AGENTS.md
AND the project-specific rules in .plinth/AGENTS-project.md.
Review this diff against the canonical spec at: ${SPEC_PATH}
(and GOAL.md if present). Find bugs, missing or hollow tests, security issues,
scope creep, violations of project-specific rules, and — for GOAL.md tasks —
metric gaming. Give concrete file:line findings and end with a verdict:
CHANGES_NEEDED or APPROVED.

DIFF:
${diff}"
# 'codex exec' = non-interactive; '--sandbox read-only' prevents edits.
codex exec --sandbox read-only "$prompt"
