# Product plan — lifecycle: default build, ship-time harden

product_rev: 1

## Problem
Forced adversarial review after every committing session causes thrash (many
rounds mid-feature) without improving ship safety. Ship already requires
APPROVED@HEAD; Stop should not re-tax build.

## Users / context
Drivers (Claude/codex/grok) and operators using Plinth on feature branches.

## Non-goals
- Full Delphi 3-seat plan product with independent deliberation UX
- Cryptographic human gates / accept digests
- Changing ship gate (still APPROVED@HEAD + CI/receipt where wired)

## Acceptance criteria
1. Feature branch default: Stop allows end-of-turn without APPROVED; logs `build_defer`.
2. After `plinth harden`, Stop again requires APPROVED@HEAD (same messages as today).
3. `plinth build` returns to default build (clears harden).
4. Ship / `gh pr create|merge` still blocked without APPROVED@HEAD (unchanged guard).
5. `plinth handoff` writes/updates root `HANDOFF.md` with goal/next/restart prompt.
6. Driver rules document: plan → build → harden → ship; read HANDOFF to restart; advisor anytime.
7. Canary script proves 1–4 without network (wired in `plinth-canary.yml`).
8. `plinth plan` scaffolds PLAN.md; `plinth plan --deep` runs three existing seats
   (reviewer/audit/advisor config) as a best-effort plan review panel (not a new Delphi product).

## Risks / trust boundaries
Ship path must not weaken. Phase file is session-local under `.plinth/session/`
(agent-unwritable via protected paths). Missing phase = build (default).
Corrupt/unknown phase = harden (fail closed, matches Stop).

## Open tradeoffs
- **Harden sticky until build/clear:** yes — explicit `plinth build` to leave.
- **Plan tooling:** light scaffold always; `--deep` reuses configured seats (ratified for v5).

## Ratification
- by: operator (this branch implements lifecycle v5 + dashboard ops agreed in design)
- product_rev: 1
