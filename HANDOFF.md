# Handoff — `feat/lifecycle-build-harden`

Updated: 2026-07-27 · Phase: **build** (implementing the lifecycle itself)

## Goal
Thin lifecycle: default build (Stop defers review), `plinth harden` restores
Stop pressure, handoff for restart, ship still APPROVED@HEAD.

## Done
- shared/.claude/hooks/review-gate.sh v2 (build_defer / harden)
- bin/plinth: harden, build, phase, handoff
- shared/plinth-rules.md + MANUAL + CHANGELOG 4.9.0 + VERSION
- canary-lifecycle-build-harden.sh ALL PASS
- PLAN.md product plan

## Next (ordered)
1. Commit on feat/lifecycle-build-harden
2. `plinth harden` then `./.plinth/review.sh` to APPROVED when ready to ship
3. PR — note consumers need `plinth update` to get new Stop hook

## Restart prompt
> Read HANDOFF.md and continue from ## Next.
> Product sources are shared/ + bin/; do not edit installed .plinth/.claude judges.

## Evidence
- Canary: canary-lifecycle-build-harden: ALL PASS

## Risks / Noticed
- Local .claude/hooks/review-gate.sh is still the installed judge until plinth update
- Full Delphi plan panel / dual harden first-pass deferred (thin core only)
