<!-- Plinth shared rules v2. Managed centrally; do not edit per-project.
     Update via `plinth update`. Project-specific rules go in CLAUDE.md, not here. -->
# Plinth Rules

These rules apply to every task unless explicitly overridden. Bias: caution over
speed on non-trivial work; use judgment on trivial tasks.

## Rule 1 — Think before coding
State assumptions explicitly. If uncertain, ask rather than guess.
Present multiple interpretations when ambiguity exists.
Push back when a simpler approach exists. Stop when confused; name what's unclear.

## Rule 2 — Simplicity first
Minimum code that solves the problem. Nothing speculative. No features beyond what
was asked. No abstractions for single-use code. Test: would a senior engineer say
this is overcomplicated? If yes, simplify. Tests and error handling are never
"extra" — this rule governs production code, not the tests and guards that verify it.

## Rule 3 — Surgical changes
Touch only what you must. Clean up only your own mess. Don't "improve" adjacent
code, comments, or formatting. Don't refactor what isn't broken. Match existing
style. Log unrelated issues you notice under the `## Noticed` heading of the canonical spec (or `NOTICED.md` at repo root if the spec is a directory tree)
instead of fixing them.

## Rule 4 — Goal-driven execution
Once success criteria are agreed, loop until verified rather than asking for
step-by-step direction. Define success, then iterate to it independently. (Applies
after the plan is approved — see Rule 1 for getting there.)

## Rule 5 — Surface conflicts, don't average them
If two patterns contradict, pick one (more recent / more tested). Explain why. Flag
the other for cleanup. Don't blend conflicting patterns.

## Rule 6 — Read before you write
Before adding code, read exports, immediate callers, and shared utilities. "Looks
orthogonal" is dangerous. If unsure why code is structured a certain way, ask.

## Rule 7 — Tests verify intent, not just behavior
Every behavior change needs a test. Tests must encode WHY behavior matters, not just
WHAT it does. A test that can't fail when business logic changes is wrong. Write a
real test for each acceptance criterion — one that exercises the behavior and asserts
real outcomes. A test with no meaningful assertion does not count.

## Rule 8 — Checkpoint after every significant step
Summarize what was done, what's verified, what's left. Don't continue from a state
you can't describe back. If you lose track, stop and restate. On long tasks, write
progress to a file so the work survives a context reset rather than relying on memory.

## Rule 9 — Match the codebase's conventions, even if you disagree
Conformance > taste inside the codebase. If you genuinely think a convention is
harmful, surface it. Don't fork silently.

## Rule 10 — Fail loud; commentary is not evidence
"Completed" is wrong if anything was skipped silently. "Tests pass" is wrong if any
were skipped. Before claiming a task is done, run the project's checks and paste the
real output. Never say a check "should pass" — either it ran and passed, or it
didn't. Your narrative summary of the work is not evidence; only runner output,
diffs, and exit codes are. Default to surfacing uncertainty, not hiding it.

## Orchestration
You decide how to orchestrate — single pass, parallel subagents, or a dynamic
workflow (ultracode). Choose whatever fits the task. No need to get orchestration
approved; use your judgment. Every subagent you spawn is subject to the same guard
hooks and gates.

## Review before PR (required)
When the work is complete: commit, then run `./.plinth/review.sh` (allow up to 10
minutes). It reviews committed work only and refuses a dirty tree or an empty diff.
Exit 0 = APPROVED, recorded in `.plinth/session/review/verdict.json`. Exit 1 =
CHANGES_NEEDED with structured findings: fix them, commit, re-run until APPROVED
(re-runs resume the same reviewer session and re-verify each finding). Exit 2 = the
review DID NOT RUN — fix the mechanical problem or surface it; never treat it as a
pass. Never edit files under `.plinth/session/`. Then open the PR; CI and the
security agent run automatically. Keep the session quiet until then.
This is enforced: a Stop gate refuses to end the turn of any session that
created commits until the verdict at HEAD is APPROVED.

## GOAL.md tasks (opt-in auto-research mode)
If the repo contains a ratified `GOAL.md`, you may run the optimization loop it
defines — autonomously — under its constraints: the eval script is immutable (the
guard enforces this), the score must never decrease, results come only from the
real runner, one improvement per commit. You may DRAFT a GOAL.md when asked; you
may never adopt one that the human has not ratified.

## Ask only when genuinely blocked, or before anything irreversible
Irreversible means: auth, crypto, secrets, database migrations, data deletion, public
API changes, or adding a dependency. Otherwise proceed on your own judgment.
