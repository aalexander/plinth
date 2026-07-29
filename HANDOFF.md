# Handoff — `fix/dashboard-review-and-blocking` @ 7cb31de

Updated: 2026-07-29T04:15:22Z · Phase: **harden** · Snapshot: **review-changes-needed** (checkpoint) · Verdict: CHANGES_NEEDED @ 7cb31dea847d

context_advice: keep_cooking — checkpoint only; do not compact/clear mid-loop.

## Goal
Forced adversarial review after every committing session causes thrash (many
## Done
- shared/.claude/hooks/review-gate.sh v2 (build_defer / harden)
- bin/plinth: harden, build, phase, handoff
- shared/plinth-rules.md + MANUAL + CHANGELOG **5.0.0** + VERSION
- canary-lifecycle-build-harden.sh ALL PASS
- PLAN.md product plan
## Next (ordered)
1. Fix [blocker] shared/.plinth/review.sh:2061 — Verify payload caps remain fail-open. The capped ledger is re-carried only from a schema-usable prio; commit; re-run ./.plinth/review.sh
1. Fix [blocker] shared/.plinth/review.sh:1806 — Verify mode fails open at both new payload caps: findings after PLINTH_VERIFY_MAX_FINDINGS are omitt; commit; re-run ./.plinth/review.sh
1. Commit on feat/lifecycle-build-harden
2. `plinth harden` then `./.plinth/review.sh` to APPROVED when ready to ship
3. PR — note consumers need `plinth update` to get new Stop hook
## Restart prompt
> Read HANDOFF.md and continue from ## Next.
> Phase is **harden**. Do not open a PR until `plinth harden` and `./.plinth/review.sh` reach APPROVED@HEAD (unless already APPROVED at this HEAD).
> Advisor: `plinth advise` anytime.
> **Automation:** never block on compaction. At milestones, fresh session is optional; default is keep cooking until ## Next is empty or NEEDS-HUMAN has [BLOCKING] items.

## Evidence
- Live: phase=harden reason=review-changes-needed verdict=CHANGES_NEEDED @ 7cb31dea847d HEAD=`7cb31de` branch=`fix/dashboard-review-and-blocking`

## Risks / Noticed
- (edit)
