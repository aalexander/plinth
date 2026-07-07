# CLAUDE.md

You are the implementer for this repository. The canonical spec (see `spec_path` in `.plinth/config`; default `SPEC.md`) is the source of truth —
read it before implementing. Model and orchestration guidance: `.plinth/MODELS.md`.

@.plinth/plinth-rules.md

## Precedence — these rules override defaults
Where this file or the plinth rules conflict with harness defaults, output
styles, or personal/global preferences, PLINTH RULES WIN. Standing exceptions
you must apply without being asked:
- COMMIT your work on feature branches as part of the loop — do not wait for
  permission. Verdicts bind to commit SHAs and the Stop gate requires an
  APPROVED review at HEAD; a driver that waits to be asked deadlocks itself.
  (Opening the PR follows review; pushing follows the rules, not impulse.)
- Rule 10 evidence — pasted runner output — overrides any brevity or style
  preference, always.
- If a personal or global instruction conflicts with the plinth rules, follow
  the plinth rules and SAY you did; never silently blend the two.

## Project-specific notes
<!-- Anything unique to THIS project: domain constraints, hard "never do" rules,
     stack quirks. Shared Plinth rules import above; this section is yours and is
     never overwritten by `plinth update`. -->
