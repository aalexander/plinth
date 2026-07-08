<!-- Plinth: single source of truth for this repo. Update before each task. -->
# <Project> — Spec

## Purpose
<One paragraph: what this is and why it exists.>

## Non-goals
- <Things this explicitly will not do. Be aggressive — agents over-build.>

## Core Invariants
<!-- Near-immutable properties (security, determinism, data integrity, safety).
     These may be loosened ONLY by explicit human escalation, never by the normal
     loop. Keep short and load-bearing; everything here is high-consequence. -->
- INV-1: <e.g., no user data leaves the process unencrypted.>

## Requirements
<!-- Each requirement has a STABLE ID (REQ-<AREA>-<NN> — never renumber; the
     review loop, receipts, and drift detection key off these). EARS phrasing.
     List prerequisites so the build is a dependency DAG (enables small vertical
     slices + safe parallel work). And name HOW it is validated at each level it
     needs — "has a test" is NOT enough: for anything whose correctness depends on
     real libraries, hardware, or external services, name the RUNTIME (smoke)
     check, because CI unit tests will not exercise it. -->
- **REQ-<AREA>-01** — When <condition>, the system shall <response>.
  - prereqs: <none | REQ-…>
  - validate: unit=<test> · integration=<test> · runtime=<smoke cmd | "n/a (pure logic)"> · post-merge=<what to watch | n/a>
  - fails-how / rollback: <how it fails; how to undo>

## Acceptance criteria
<!-- Each references a REQ id and is a testable assertion, not a vibe. -->
- [ ] <REQ-…> — <testable assertion>

## Execution-gated surface
<!-- Paths whose correctness can ONLY be confirmed by RUNNING on real deps/
     hardware (the layer CI can't reach — the classic late-found blindspot).
     Mirror these into .plinth/config: RUNTIME review findings there route to the
     run gate (plinth smoke) instead of blocking, and smoke_cmd exercises them. -->
- exec_gated: <space-separated grep -E patterns, e.g. (^|/)backends/ | "none">
- smoke_cmd: <command that exercises the real-run layer | "none">

## High-consequence surface (tier2_extra)
<!-- Project paths that must ALWAYS get the full (Tier 2) adversarial review +
     cross-vendor second opinion. Auth/crypto/secrets/migrations/public-API/
     tooling are already Tier 2 by default; list anything project-specific here. -->
- tier2_extra: <grep -E pattern | "none">

## Noticed
<!-- The driver logs unrelated issues here instead of fixing them. Triage yourself. -->
