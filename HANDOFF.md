# Handoff — `fix/dashboard-review-and-blocking` @ 32723c6

Updated: 2026-07-29T03:36:01Z · Phase: **harden** · Snapshot: **enter-harden** (milestone) · Verdict: none

context_advice: optional_fresh_session — NOT required; do not wait. Keep working unless human-blocked.

## Goal
Forced adversarial review after every committing session causes thrash (many
## Done
- shared/.claude/hooks/review-gate.sh v2 (build_defer / harden)
- bin/plinth: harden, build, phase, handoff
- shared/plinth-rules.md + MANUAL + CHANGELOG **5.0.0** + VERSION
- canary-lifecycle-build-harden.sh ALL PASS
- PLAN.md product plan
## Next (ordered)
1. Run ./.plinth/review.sh until APPROVED@HEAD, then open PR (or plinth build to leave harden).
1. Commit on feat/lifecycle-build-harden
2. `plinth harden` then `./.plinth/review.sh` to APPROVED when ready to ship
3. PR — note consumers need `plinth update` to get new Stop hook
## Restart prompt
> Read HANDOFF.md and continue from ## Next.
> Phase is **harden**. Do not open a PR until `plinth harden` and `./.plinth/review.sh` reach APPROVED@HEAD (unless already APPROVED at this HEAD).
> Advisor: `plinth advise` anytime.
> **Automation:** never block on compaction. At milestones, fresh session is optional; default is keep cooking until ## Next is empty or NEEDS-HUMAN has [BLOCKING] items.

## Evidence
- Live: phase=harden reason=enter-harden verdict=none HEAD=`32723c6` branch=`fix/dashboard-review-and-blocking`

## Risks / Noticed
- (edit)
