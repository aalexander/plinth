<!-- Plinth auto-research mode. STATUS must be RATIFIED (by the human) before any
     agent runs this loop. Agents may draft and critique this file; they may never
     set STATUS to RATIFIED themselves. -->
# GOAL — <one-line objective>

STATUS: DRAFT   <!-- human changes to RATIFIED after review -->

## Metric (single scalar, higher is better)
Command that produces the score (the ONLY source of truth — never narrate a score):
    <e.g. ./anvil score --json | jq .tokens_per_sec>

## Immutable
The eval/scoring path(s) below are agent-immutable. They MUST also be added to
`.plinth/protected-paths` (the guard enforces it):
- <e.g. (^|/)bench/score\.sh$>   <!-- use (^|/) not ^: agent paths are often absolute -->

## Constraints
- Score must never decrease. Measure before AND after every change; paste real output.
- One improvement per commit (atomic, revertible).
- No new dependencies. No changes outside: <allowed dirs>.
- Results come only from the real runner. Fabricated/derived numbers = task failure.

## Action catalog (what kinds of changes are in bounds)
- <e.g. cache layout, batch sizes, algorithmic changes in src/inference/>

## Stop conditions
- Score reaches <target>, OR <N> consecutive attempts without improvement,
  OR constraint violation (stop and report).

## Exit
On stop: run ./.plinth/review.sh (reviewer checks metric integrity), then open a PR.
Normal Plinth gates apply.
