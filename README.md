# Plinth

A plinth is the base a statue stands on: the statue changes, the plinth doesn't.
Plinth is a subscription-funded, multi-model development environment built on that
principle — Claude drives, Codex adversarially reviews, and a deterministic CI
floor gates every merge. The model layer swaps in minutes; the base never moves.

Read MANUAL.md for daily use, SETUP.md for one-time setup, shared/MODELS.md for
current model assignments, CHANGELOG.md for what changed in v2.

Shared files (version-pinned, propagate via `plinth update`): plinth-rules.md,
MODELS.md, guard.sh, review.sh, AGENTS.md, plinth-floor.yml.
Per-project files (copied once, never overwritten): CLAUDE.md notes, SPEC.md,
ci.yml checks, .claude/settings.json, .plinth/protected-paths, GOAL.md.
