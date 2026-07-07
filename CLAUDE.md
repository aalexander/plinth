# CLAUDE.md

You are the implementer for this repository. The canonical spec (see `spec_path` in `.plinth/config`; default `SPEC.md`) is the source of truth —
read it before implementing. Model and orchestration guidance: `.plinth/MODELS.md`.

@.plinth/plinth-rules.md

## Project-specific notes
<!-- Anything unique to THIS project: domain constraints, hard "never do" rules,
     stack quirks. Shared Plinth rules import above; this section is yours and is
     never overwritten by `plinth update`. -->
This repository is Plinth itself. `shared/`, `templates/`, and `bin/` are the
product — edit them freely. The installed `.plinth/` and `.claude/` copies are
the pinned previous release judging your work: never edit them; they refresh
only via the release flow. Every `shared/` or `bin/` change needs a CHANGELOG
entry and VERSION bump. Work on branches — the Stop gate and review loop apply
here like any project.
