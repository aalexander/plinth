# Checkpoint — `feat/effort-seat-wiring` @ 06a03f6

Updated: 2026-07-30T03:00:00Z · Phase: **build** · Snapshot: **S0–S6 complete, entering S7** · Verdict: CHANGES_NEEDED @ 81909bc (pre-5.1, superseded)

context_advice: keep_cooking — implementation complete; one paid review round is the remaining step.

## Goal
Ship **v5.1.0 ship-bias architecture**: dual OFF default, risk-triggered L3 security, thrash class demotion with receipt audit + never-demote security floor, APPROVED after one primary+verify with Noticed-only, L1 min canaries + L4 floor/receipt non-negotiable. Land prior product residual **without dual-e2e thrash**.

## Done — S0 through S6 (implementation complete)
- Product residual 5.0.x train on this branch through `81909bc`.
- **S0** — free canaries 8/8 baseline; asymptotic classes already in MANUAL `## Noticed`; residual unbound.
- **S1** `88a1c61` — dual OFF by default in EVERY phase (HARDEN no longer forces it); slice knob renamed `effort:medium|high|xhigh` → `rigor:standard|deep` (operator-ratified scope extension; old key/env read one release, writer emits `rigor` only, two alias impls canary-locked to agree); requested-dual-with-no-seat fails closed (exit 2) BEFORE the paid round with `PLINTH_ACK_NO_DUAL=1` recorded on request/verdict/receipt; VERSION 5.1.0 + CHANGELOG opened.
- **S2** `80c8fef` — demotion bounded by in-repo `demotable_classes` (7 IDs); NO `class` field is read from findings JSON, so "driver must not assign classes" holds by construction; vocabulary edit is Tier 2 by construction (canary-asserted vs risk-classify); every demotion records its class. Two real holes closed: the never-demote floor did not apply to every arm (ephemera demoted on PATH ALONE ahead of any precedence check), and the belt missed passive-voice data loss ("the stored state **is lost**").
- **S3** `3864c3e` — demotion ledger on the receipt (`{round,id,file,class,from,to,phase,mode}`); severities snapshotted pre-policy; `thrash_ledger_rows` extractable so the canary drives the real mapping; unparseable ledger refuses to mint; `receipt-verify` bounds the shape when present, never requires it.
- **S4** `f0a1152` — L3 risk-triggered security pass (trigger from risk-classify reasons + `PLINTH_SECURITY_PASS`); unreadable reasons fail TOWARD running it; never false-concurs (UNAVAILABLE recorded; same-vendor seat is not independent); `security_pass_required` read from BASE config so a PR cannot delete it.
- **S5** `f0a1152` — reviewer contract: asymptotic never major in EITHER phase, security never minor/Noticed, no `class:` emission by reviewers, only-minors-is-APPROVED stated outright.
- **S6** `5a3f8c2` — MANUAL ship-bias doctrine (L1–L4), PLAN AC #9 alignment, four honest residuals in `## Noticed`.
- **S7 pre-flight** `06a03f6` — free adversarial self-review found three real defects: a SECOND demotion site (audit payload) whose demotions reached no ledger (making "every demotion is disclosed" wider than the code), a Tier-0 receipt claiming `security_pass: UNKNOWN` instead of NOT_TRIGGERED, and a dropped trigger path in the security-pass reason (ERE binds `a|b[^;]*` as `a` OR `b[^;]*`). Also caught a top-level `local` that `bash -n` cannot detect and that would have failed at runtime on the audit path.

## Next
1. **S7:** run `./.plinth/review.sh` (base `main`) → fix findings in ONE commit per round → **APPROVED@HEAD**.
2. On APPROVED: `git push origin HEAD refs/notes/plinth-receipts` → open PR with the audit summary derived from `.plinth/session/review/` → heal CI by classification → merge → tag `v5.1.0`.
3. **Do not:** re-open dual e2e / canary depth / fake-CLI argv as majors (they are `## Noticed` by design); HARDEN-default dual; dual in branch protection; driver-assigned demotion classes; delete receipt/unbind/dirty-tree fail-closed.

## Phase decision (operator-ratified 2026-07-30)
Review runs in **BUILD**, not harden. The two mechanisms that stop an asymptotic spiral are both BUILD-only: the harness demotion of coverage-shaped classes (deliberately not widened into harden — that would push a fail-open into the phase where coverage depth is in charter) and the base contract's asymptotic-coverage-is-minor rule. S5's fix (asymptotic never major in either phase) is inlined from the RATIFIED BASE, so it cannot govern the branch that introduces it. Harden here would reproduce the r28 spiral the plan forbids feeding. Dual is off in both phases now, so harden's main cost is already gone.

## Evidence
- Plan: `docs/SHIP-BIAS-5.1.md` (S1 scope extension recorded in-line)
- Free canaries: **10/10 PASS** (added `canary-thrash-classes.sh`, `canary-security-pass.sh`)
- `receipt-verify.sh` end-to-end demotion fixtures: **8/8 PASS** (pre-v5.1 receipt without the field still verifies)
- VERSION `5.1.0` == CHANGELOG top H2 (Tier-0 floor requirement)
- Residual: unbound (`.plinth/RESIDUAL.json`)

## Risks / Noticed
- **Demotion laundering** remains the #1 risk; all three bounds are in place (in-repo vocabulary the loop cannot supply, Tier-2 edit surface, receipt disclosure).
- `PLINTH_ACK_NO_DUAL` is disclosed on request/verdict/receipt but is NOT in `receipt-verify.sh`'s 5-name `override_ledger` allowlist, so it is auditable but not machine-enforced into the PR body. Recorded in MANUAL `## Noticed`.
- `thrash_class` is still triplicated in the sticky blocks; vocabularies are canary-locked rather than unified (deliberate — a refactor of three duplicated jq blocks in the same train as the demotion bounds is where a silent classification bug would hide).
- S5's contract binds from the NEXT branch, not this one (base-read).
- L3 fires on every diff in THIS repo (Plinth's product surface IS the tooling ship path); the risk-triggered saving shows up downstream.

## Routing

<!-- plinth.checkpoint/v1 — machine-readable; ETAs reserved-null in v1 -->
```json
{
  "schema": "plinth.checkpoint/v1",
  "plan_ref": "PLAN.md",
  "slice_id": "s7-review-to-approved",
  "slice_title": "S7 one paid review to APPROVED@HEAD, then ship 5.1.0",
  "slice_index": 8,
  "slice_total": 8,
  "status": "reviewing",
  "rigor": "standard",
  "rigor_rationale": "Ship-bias 5.1: one primary + verify is the gate; L3 covers the security-shaped surface. Driver reasoning effort is a HARNESS knob, deliberately not encoded here.",
  "implement": "driver",
  "updated_at": "2026-07-30T03:00:00Z",
  "elapsed_secs_slice": null,
  "eta_secs_slice": null,
  "eta_secs_plan": null
}
```
