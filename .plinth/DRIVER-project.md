# Project-Specific Driver Notes

This repository is Plinth itself — the scope INVERSION below overrides the
usual "tooling is off-limits" instinct, so read it before touching anything:

- `shared/`, `templates/`, `bin/`, and the `.github/workflows/` sources (the
  reusable `plinth-floor.yml`/`plinth-checks.yml` that downstream repos pin by
  SHA, plus this repo's `plinth-canary.yml` regression suite and `ci.yml`) are
  the PRODUCT — edit them freely.
- The installed `.plinth/` and `.claude/` copies are the pinned previous
  release judging your work: never edit them; they refresh only via the
  release flow (`plinth update`, run against this repo).
- Every `shared/` or `bin/` change needs a CHANGELOG entry and VERSION bump.
- Work on branches — the Stop gate and review loop apply here like any
  project.
- The canonical spec is `MANUAL.md` (see `spec_path` in `.plinth/config`);
  review-loop findings against the INSTALLED tooling are fixed in the
  `shared/`/`bin/` SOURCES (product work), never in the installed copies.
