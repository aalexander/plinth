# Plinth changelog

## v3.4 — July 5, 2026
- NEW templates/.gitignore (per-project, copied once): secrets, model weights
  (*.gguf/*.safetensors/etc.), OS junk, and build artifacts for the four
  detected stacks. Closes the gap where `git add -A` could commit weights or a
  stray .env — the guard blocks edits, not adds, and gitleaks fires post-commit.
- `plinth init` now reports every per-project file as "created" or
  "kept (yours)" — replaces manual post-init verification. (Note: init never
  rewrote existing files; the [ -f ] || guard predates this. The reporting
  makes that visible instead of trusted.)
- PLANNING-PROMPT: project notes must pin exact toolchain versions;
  requirements must be dependency-ordered (each testable using only its
  predecessors).

## v3.3 — July 5, 2026
- Zero-edit scaffolding: `plinth init` auto-detects the GitHub owner (target
  origin -> Plinth checkout origin -> git config github.user) and injects it
  into ci.yml; warns if undetectable.
- NEW reusable `plinth-checks.yml`: runtime stack detection (Rust/Node/Python/Go)
  runs conventional check commands at CI time — works for greenfield repos where
  nothing exists at scaffold time. Template ci.yml is now two `uses:` lines with
  an optional macos-latest runner input. Nonstandard stacks: replace the checks
  job locally (ci.yml is per-project, never overwritten).
- Tradeoff, stated: auto-detected checks run conventional commands, not
  project-specific ones. The driver still runs the project's real checks locally
  (Rule 10); CI detection is the backstop.

## v3.2 — July 5, 2026
- NEW `.plinth/config` (per-project, never overwritten): `spec_path` declares the
  canonical spec location — a file (SPEC.md) or a directory tree (ARCH/, spec/).
  Kills the reserved-SPEC collision at the harness level instead of forcing every
  project to work around it. review.sh, plinth-rules.md, AGENTS.md, and the
  CLAUDE.md template now reference spec_path instead of hardcoding SPEC.md.
- NEW `.plinth/AGENTS-project.md` (per-project, never overwritten): project-
  specific reviewer blocking criteria that extend the shared AGENTS.md. Fixes the
  defect where domain rules added to AGENTS.md were clobbered by plinth update.
- Rules: "Noticed" logging goes to the canonical spec, or NOTICED.md at repo root
  when the spec is a directory tree.

## v3.1 — July 4, 2026
- Fix: `bin/plinth` resolved PLINTH_ROOT via `dirname "$BASH_SOURCE"`, which
  returned /usr/local when invoked through the /usr/local/bin/plinth symlink,
  breaking init/update/goal/migrate. Now follows the symlink chain with a
  readlink loop (handles relative and chained links). Regression cause: the CLI
  had only ever been tested via `bash <path>`, never through the symlink. All
  CLI changes must now be tested through the symlink.


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
