# Checkpoint — `feat/effort-seat-wiring` @ 81909bc

Updated: 2026-07-30T01:30:00Z · Phase: **build** (recommended for S0–S6; harden only for S7 ship) · Snapshot: **plan handoff** · Verdict: CHANGES_NEEDED @ 81909bc (pre-5.1)

context_advice: keep_cooking — architecture locked in docs; implement next. Resume: **docs/SHIP-BIAS-5.1.md** then this file.

## Goal
Ship **v5.1.0 ship-bias architecture**: dual OFF default, risk-triggered L3 security, thrash class demotion with receipt audit + never-demote security floor, APPROVED after one primary+verify with Noticed-only, L1 min canaries + L4 floor/receipt non-negotiable. Land prior product residual **without dual-e2e thrash**.

## Done
- Product residual 5.0.x train on this branch (effort/seat, plan_progress PLAN-only, #61/#62, advise auth, checkpoint, thrash precedence, canaries) through `81909bc`.
- Review thrash documented (~r28): asymptotic dual e2e / fake CLI / NLP — **not** more product rounds.
- Architecture ratified (operator + Fable impactful advise). Full writeup: **`docs/SHIP-BIAS-5.1.md`**.

## Next

1. Read **`docs/SHIP-BIAS-5.1.md`** end-to-end (layers, demotion bounds, slices S0–S7).
2. **S0:** free canaries green; Noticed only for asymptotic; **no** dual e2e canary majors.
3. **S1–S5:** implement dual-off, thrash allowlist + floors, receipt demotions, L3 hook, reviewer contract (see plan).
4. **S6:** VERSION **5.1.0** + CHANGELOG + MANUAL/MODELS.
5. **S7:** one paid `./.plinth/review.sh` → **APPROVED@HEAD** → push + receipt notes → PR → merge → tag `v5.1.0` → client `plinth update` when operator asks.
6. **Do not:** HARDEN-default dual; dual in branch protection; driver-assigned demotion classes; delete receipt/unbind/dirty-tree fail-closed.

## Evidence
- Plan file: `docs/SHIP-BIAS-5.1.md`
- Residual: unbound (`.plinth/RESIDUAL.json`)
- Last paid verdict: CHANGES_NEEDED r28 @ 81909bc (asymptotic majors — plan demotes/Notices them)

## Risks / Noticed
- **Demotion laundering** is the #1 risk — implement all three bounds (reviewer-only classes, Tier-2 on allowlist edit, receipt demotion lines).
- Optional polish still open (non-blocking): dash `slice_title` chip; ETA-unknown display.

## Routing

<!-- plinth.checkpoint/v1 — machine-readable; ETAs reserved-null in v1 -->
```json
{
  "schema": "plinth.checkpoint/v1",
  "plan_ref": "docs/SHIP-BIAS-5.1.md",
  "slice_id": "s0-land-no-thrash",
  "slice_title": "S0 free canaries + Noticed; then S1 dual-off → S7 APPROVED 5.1.0",
  "slice_index": 1,
  "slice_total": 8,
  "status": "implementing",
  "effort": "xhigh",
  "effort_rationale": "Architecture defaults + thrash security bounds; judgment-heavy, not dual theater",
  "implement": "driver",
  "updated_at": "2026-07-30T01:30:00Z",
  "elapsed_secs_slice": null,
  "eta_secs_slice": null,
  "eta_secs_plan": null
}
```
