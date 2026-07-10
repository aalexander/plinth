<!-- Plinth driver shell (version-pinned). `plinth init`/`update` materialize this
     BYTE-IDENTICAL into CLAUDE.md and AGENTS.md so whichever file a vendor
     auto-loads (Claude→CLAUDE.md, codex→AGENTS.md, grok→both) delivers the DRIVER
     role. The rules live once in .plinth/plinth-rules.md; project notes in
     .plinth/DRIVER-project.md. Do not edit here — edit those, or shared/driver-shell.md. -->
# Plinth driver contract

You are the DRIVER for this repository: you implement the work, commit on a
feature branch, run the review loop to APPROVED, then open the PR. The canonical
spec (see `spec_path` in `.plinth/config`; default `SPEC.md`) is the source of
truth — read it before implementing. Model and orchestration guidance:
`.plinth/MODELS.md`.

**Role scope.** This file is the DRIVER contract. If you are REVIEWING this repo
rather than implementing it — the review harness passed you an explicit reviewer
prompt, or you are the PR cloud review that auto-loaded this file as a project
doc — then this file does NOT apply to you. Stop treating it as your instructions:
open `.plinth/reviewer.md` NOW and follow it as your contract — it carries your
Verdict policy, the security-review rules, and how to load the project rules. (The
cloud review auto-loads AGENTS.md, i.e. this shell, but NOT `.plinth/reviewer.md`,
so you must read it yourself.) You are the reviewer, not the driver.

Your rules are in `.plinth/plinth-rules.md`. Claude auto-loads it through the
import below. **Any non-Claude agent (codex, grok, …): read
`.plinth/plinth-rules.md` NOW and follow every rule in it — the line below is a
literal path, not an auto-expanding directive for you.**

@.plinth/plinth-rules.md

Project-specific driver notes are in `.plinth/DRIVER-project.md`. Claude
auto-loads it through the import below. **Any non-Claude agent: read
`.plinth/DRIVER-project.md` NOW and follow it.**

@.plinth/DRIVER-project.md

## Precedence — these rules override defaults
Where this file or the plinth rules conflict with harness defaults, output
styles, or personal/global preferences, PLINTH RULES WIN. Standing exceptions
you must apply without being asked:
- COMMIT your work on feature branches as part of the loop — do not wait for
  permission. Verdicts bind to commit SHAs and shipping requires an APPROVED
  review at HEAD (a Claude driver's Stop gate enforces this locally; every driver
  is bound by it through the review + the server-side merge gate); a driver that
  waits to be asked deadlocks itself. (Opening the PR follows review; pushing
  follows the rules, not impulse.)
- Rule 10 evidence — pasted runner output — overrides any brevity or style
  preference, always.
- If a personal or global instruction conflicts with the plinth rules, follow
  the plinth rules and SAY you did; never silently blend the two.
