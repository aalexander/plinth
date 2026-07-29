# Checkpoint — `feat/effort-seat-wiring` @ 96b8834

Updated: 2026-07-29T18:50:23Z · Phase: **harden** · Snapshot: **enter-harden** (milestone) · Verdict: none

context_advice: optional_fresh_session — NOT required; do not wait. Keep working unless human-blocked.

## Goal
Forced adversarial review after every committing session causes thrash (many rounds mid-feature) without improving ship safety. Ship already requires APPROVED@HEAD; Stop should not re-tax build.
## Done
Product residual closeout on fix/residual-closeout-5.0.5 (verify fail-closed,
sticky/thrash, phase, plan seats, scaffold, quota, agy -p, docs). Canary ALL PASS.
## Next (ordered)
1. Run ./.plinth/review.sh until APPROVED@HEAD, then open PR (or plinth build to leave harden).
1. PR with residual-bound ship (receipt may be red — intentional residual land)
2. Optional follow-up: deeper product-path canaries
## Restart prompt
> Read CHECKPOINT.md (or HANDOFF.md) and continue from ## Next.
> Phase is **harden**. Do not open a PR until `plinth harden` and `./.plinth/review.sh` reach APPROVED@HEAD (unless already APPROVED at this HEAD).
> Advisor: `plinth advise` anytime.
> **Automation:** never block on compaction. At milestones, fresh session is optional; default is keep cooking until ## Next is empty or NEEDS-HUMAN has [BLOCKING] items.

## Evidence
- Live: phase=harden reason=enter-harden verdict=none HEAD=`96b8834` branch=`feat/effort-seat-wiring`

## Risks / Noticed
- (edit)

## Residual
Bound at HEAD — see .plinth/RESIDUAL.json (canary e2e depth follow-up).

## Routing

<!-- plinth.checkpoint/v1 — machine-readable; ETAs reserved-null in v1 -->
```json
{
  "schema": "plinth.checkpoint/v1",
  "plan_ref": "PLAN.md",
  "slice_id": "effort-seat",
  "slice_title": "effort/seat live wiring",
  "slice_index": 1,
  "slice_total": 1,
  "status": "implementing",
  "effort": "high",
  "effort_rationale": "judgment+wiring interleaved",
  "implement": "driver",
  "updated_at": "2026-07-29T18:50:23Z",
  "elapsed_secs_slice": null,
  "eta_secs_slice": null,
  "eta_secs_plan": null
}
```
