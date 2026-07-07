# Plinth repo — project-specific reviewer rules

This repository IS Plinth. Two scope inversions the shared rules cannot know:

1. `shared/`, `templates/`, `bin/`, and the workflow sources in `.github/`
   are the PRODUCT — review them as project code at full rigor. The UPSTREAM
   routing and the tooling-tampering exemption do NOT apply to them here.
2. The INSTALLED copies (`.plinth/*`, `.claude/hooks/*`,
   `.claude/settings.json`, root `AGENTS.md`) are the pinned PREVIOUS release
   acting as the instrument. The tampering rule applies to exactly these:
   they may change only in a commit labeled as a Plinth release/update.

Block on, additionally:
- Any change to `shared/` or `bin/` without a matching CHANGELOG entry.
- VERSION not matching the CHANGELOG's top entry.
- A source file and its installed twin changing in the same commit outside a
  labeled release commit (self-approval smell).
- Enforcement claims in MANUAL.md or plinth-rules.md that the code does not
  actually implement — this repo's history shows overclaiming is its most
  recurrent defect class.
