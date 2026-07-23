<!-- Plinth shared rules v2. Managed centrally; do not edit per-project.
     Update via `plinth update`. Project-specific driver notes go in
     .plinth/DRIVER-project.md (not here, and not in the pinned CLAUDE.md shell). -->
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
approved; use your judgment. Every CLAUDE subagent you spawn inherits the same
`.claude/` guard hooks and gates; whether a cross-family codex/grok delegate inherits
them is PER-CLI — probe with `plinth hookprobe <vendor>` and treat hooks as absent
ONLY when the probe says so (grok 0.2.93 reported no execution; a probe reporting
execution means the guard and gates are LIVE for that delegate). For a non-executing
delegate, the binding layer is your own discipline
(run the review loop) plus branch protection's required checks (floor + checks — CI
and tooling integrity; they do NOT verify the review verdict). The Codex cloud
review is ADVISORY: it posts PR comments and exposes no status-check context that
branch protection could require. The server-verifiable APPROVED-at-HEAD receipt
check (auto mode, next release) is the designated adversarial gate for delegated
and non-Claude work.

## Subagents and the advisor (speed, and a stronger opinion)
Fan out independent work to SUBAGENTS for speed and parallelism — the moment a task
splits into parts that do not depend on each other (survey N files, write M
independent tests, apply one refactor across many sites), run them concurrently
instead of in sequence. Route each subagent to the BEST model for THAT part: cheap and
fast for mechanical or heavily-parallel fan-out, a strong model for the hard or
high-consequence pieces. Use your harness's native model selection (Claude: the Agent
`model` param / opusplan; other drivers: their equivalent). Prefer IN-FAMILY subagents
for parallel fan-out; when one subtask genuinely wants another family's strength, a
cross-family CLI shell-out is fine — with the enforcement caveat that follows. CLAUDE
subagents inherit the `.claude/` guard
hooks and gates automatically; whether a cross-family codex/grok shell-out does is
PER-CLI (probe with `plinth hookprobe` — grok 0.2.93 reported no execution; only
probe-EXECUTED events are enforced), so keep any ship or destructive authority for such
delegations narrow — what actually binds them is your discipline plus branch
protection's required checks (floor + checks; the cloud review is advisory PR
comments, not a requirable context, and no server-side review gate exists yet).

Act like an ARCHITECT on implementation volume: emit judgment (decomposition, interfaces,
specs, verdicts) and keep the expensive model for the judgment a spec can't capture. Under a
CLAUDE driver, delegate the TYPING to a cheaper cross-family lane rather than typing it
yourself — two shipped Claude-Code subagents do this, `grok-implementer` (default) and
`codex-implementer` (cross-vendor), each driving an external CLI from a five-part spec
(objective · files · interfaces · constraints · verification) and VERIFYING the result
independently (Rule 10: the lane's report is a claim; your re-run of the verification command
is the evidence). A NON-Claude driver cannot run those subagents — and doesn't need them when
it IS the cheap fast model (the v4 grok driver): type your own volume, consult judgment UP
via `plinth advise` (`--impactful` for architectural calls), and for a second implementation
shell out to the other family's CLI with the same five-part spec plus
`.plinth/lane-guard.sh` (preflight / snapshot / scope — vendor-neutral shell).
Details + cost discipline: `.plinth/MODELS.md`. When a
delegated spec turns out to be architecturally wrong, that is YOUR call — do not let the lane
guess; decide it, or consult the advisor.

Before an IMPACTFUL or architectural decision — one expensive to reverse or that
shapes the design (a schema, a public interface, a security boundary, a migration
strategy) — consult the ADVISOR: `plinth advise --impactful "<question>"` calls a model
as good or better than you (config: `advisor_vendor` / `advisor_model` /
`advisor_model_max`; cross-family is fine — a Grok driver can consult Fable). Drop
`--impactful` for an ordinary second opinion. The advisor is COLLABORATIVE and
NON-BLOCKING — it informs your call; it is neither the adversarial reviewer (the gate)
nor the auditor (a second opinion on an approval). Use it on the calls that matter, not
reflexively.

## Review before PR (required)
Work on a feature branch — never commit directly to the base branch. The Stop
gate deliberately does not guard base branches (it logs and releases), and the
PR needs a branch to exist. Branch first, then build.
When the work is complete: commit, then run `./.plinth/review.sh`. Rounds on
large diffs can exceed 10 minutes — if your shell tool caps there, run it in
the background and read the result; an interrupted round is safe to re-run
(resume/fallback recovers). It reviews committed work only and refuses a dirty tree or an empty diff.
Exit 0 = APPROVED, recorded in `.plinth/session/review/<slug>/verdict.json` (branch-keyed;
`<slug>` is the branch name with `/` and spaces turned to `-`). Exit 1 =
CHANGES_NEEDED with structured findings: fix them, commit, re-run until APPROVED
(re-runs resume the same reviewer thread when it fits the vendor's window; an
oversized or dead thread instead runs a VERIFY round — a fresh session seeded with
the prior findings plus the FULL diff — re-checking each finding and re-reviewing the
whole diff). Exit 2 = the
review DID NOT RUN — fix the mechanical problem or surface it; never treat it as a
pass. Never edit files under `.plinth/session/` or version-pinned Plinth tooling
(under a Claude driver the guard blocks both at the tool level; for EVERY driver the
review and CI reject such edits as tampering — so do not rely on the local hook, just
don't do it). Verdict policy: blockers/majors in project code block;
minor findings don't block but MUST be appended to the spec's `## Noticed` before
the PR; findings in Plinth tooling are UPSTREAM — surface them to the human,
never fix the instrument in-session. Then open the PR; CI and the Codex cloud review
run automatically. The PR body is the audit summary of the loop, derived from
.plinth/session/review/ — not narrated: rounds and modes, final verdict + SHA,
real check output, open minors with their `## Noticed` entries, tooling-update
commits labeled as such, and any UPSTREAM handoffs. Keep the session quiet
until then.
Under a CLAUDE driver this is enforced by a `.claude/` Stop gate: it refuses to end
the turn of a session that created commits until the verdict at HEAD is APPROVED. The
gate has two pressure valves — a recent mechanical review failure, and a per-session
block cap (PLINTH_GATE_MAX_BLOCKS, default 10) — and every release without approval is
logged to the session event feed, where `plinth watch` shows it in red. A codex/grok
driver whose CLI does not execute `.claude/` hooks (probe with `plinth hookprobe
<vendor>` — grok 0.2.93 reported no execution; re-run after upgrades) has no Stop
gate — nothing LOCAL forces it to review. It is bound instead by these rules (you are trusted to run
the loop) and branch protection's required checks (floor + checks). Neither verifies
the review verdict, and the Codex cloud review is advisory (PR comments — no
requirable status context), so for a non-Claude driver the adversarial review loop is
CONTRACT-bound until the APPROVED-at-HEAD receipt check ships (auto mode, next
release). Either way: run the loop to APPROVED before you open the PR — that is the
contract, whether or not a server gate enforces it yet.

## Upstream channel — two-way, with the Plinth maintainer
Tooling findings and improvement proposals are never fixed in-project (that is
tampering). File them upstream as a GitHub issue:
  gh issue create -R aalexander/plinth --title "UPSTREAM: <symptom>" \
    --body "<symptom / root-cause hypothesis / proposed fix / session+round refs>"
This is a conversation, not a drop-box: at session start, check your open
upstream issues for maintainer replies (gh issue list -R aalexander/plinth
--search "UPSTREAM in:title") and answer what was asked. Proposals are
evaluated — including for security — before anything ships; never assume one
landed until `plinth update` delivers it.

## GOAL.md tasks (opt-in auto-research mode)
If the repo contains a ratified `GOAL.md`, you may run the optimization loop it
defines — autonomously — under its constraints: the eval script is immutable (a
Claude driver's guard blocks edits to it; for every driver the reviewer flags an eval
edit as metric gaming — a blocking review finding — so treat it as immutable regardless),
the score must never decrease, results come only from the
real runner, one improvement per commit. You may DRAFT a GOAL.md when asked; you
may never adopt one that the human has not ratified.

## Ask only when genuinely blocked, or before anything irreversible
Irreversible means: auth, crypto, secrets, database migrations, data deletion, public
API changes, or adding a dependency. Otherwise proceed on your own judgment.
When blocked on something only the human can supply (credentials, artifact
hashes, hardware runs, spend approvals), add a checkbox line to
`.plinth/NEEDS-HUMAN.md` (the canonical location — always write it there; the
dashboard and review tooling tolerate a legacy root copy but new items go in
`.plinth/`) — what, why, and the exact format needed — and keep working on
whatever isn't blocked. Prioritize the queue by blocking impact:
prefix any item that stalls work RIGHT NOW with `[BLOCKING]` and keep those at
the top; everything else (needed eventually, nice-to-have) goes below. The
dashboard surfaces the file and the blocking count; check items off the moment
they're supplied. RUNTIME review findings are burned down the same way: ask
the human for a `plinth smoke` run (execution receipts feed the next review
round), not more review rounds.
