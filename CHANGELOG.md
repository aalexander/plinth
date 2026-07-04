# Plinth changelog

## v3.1 — July 4, 2026
- Fix: bin/plinth resolved PLINTH_ROOT incorrectly when invoked through the
  /usr/local/bin/plinth symlink — dirname "$BASH_SOURCE" returned /usr/local,
  so every subcommand looked for templates/shared files under /usr/local and
  failed with "No such file or directory". Replaced with a readlink loop that
  follows the symlink chain (handling relative links) to the real checkout.
  Affected init, update, goal, and migrate equally.

## v3 — July 3, 2026
- MODELS.md rewritten for the post-export-control landscape: Fable 5 suspended
  June 12 -> relaunched July 1; plan-included (50% of weekly limits) through
  July 7 ONLY; usage-credits-only after, with no automatic fallback. New default
  from July 8: Opus 4.8 driver, Fable 5 by exception via capped credits.
  Sonnet 5 added as the mechanical tier. GPT-5.5 remains reviewer; GPT-5.6 is
  gov-gated (~20 orgs), evaluate at Codex GA.
- NEW `plinth migrate`: one-shot Forge -> Plinth repo migration (carries over
  protected-paths, fixes CLAUDE.md import, ci.yml floor reference, GOAL.md paths).
- NEW PLANNING-PROMPT.md at repo root with a keep-in-sync header tying it to
  templates/SPEC.md and templates/GOAL.template.md.
- bin/plinth: in-place edits made macOS-portable (no `sed -i`).
- ci.yml template and floor workflow references bumped to @v3.

## v2 — June 9, 2026 (renamed from Forge; ForgeCode name collision)
- Project renamed Forge -> Plinth throughout.
- Driver: Claude Fable 5 at launch. Guard v2 with per-project protected-paths.
- NEW `plinth goal` auto-research mode: human-ratified metric, guard-enforced
  immutable eval, reviewer metric-integrity check.
- Rule 10 hardened per Fable 5 system card: commentary is not evidence.

## v1 — May 30, 2026 (as Forge)
- Initial versioned scaffold: shared vs per-project split, init/update CLI,
  reusable CI floor, guard hook, PR-creation review boundary.
