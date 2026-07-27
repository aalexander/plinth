# Product plan — lifecycle: default build, ship-time harden

product_rev: 1

## Problem
Forced adversarial review after every committing session causes thrash (many
rounds mid-feature) without improving ship safety. Ship already requires
APPROVED@HEAD; Stop should not re-tax build.

## Users / context
Drivers (Claude/codex/grok) and operators using Plinth on feature branches.

## Non-goals
- Full Delphi 3-seat plan product
- Dual first-pass beyond existing Tier-2 audit
- Cryptographic human gates / accept digests
- Changing ship gate (still APPROVED@HEAD + CI/receipt where wired)

## Acceptance criteria
1. Feature branch default: Stop allows end-of-turn without APPROVED; logs `build_defer`.
2. After `plinth harden`, Stop again requires APPROVED@HEAD (same messages as today).
3. `plinth build` returns to default build (clears harden).
4. Ship / `gh pr create|merge` still blocked without APPROVED@HEAD (unchanged guard).
5. `plinth handoff` writes/updates root `HANDOFF.md` with goal/next/restart prompt.
6. Driver rules document: plan → build → harden → ship; read HANDOFF to restart; advisor anytime.
7. Canary script proves 1–4 without network.

## Risks / trust boundaries
Ship path must not weaken. Phase file is session-local under `.plinth/session/`
(agent-unwritable via protected paths). Missing phase = build (default).

## Open tradeoffs
- **Harden sticky until build/clear:** yes — explicit `plinth build` to leave.
- **Plan tooling:** docs + PLAN.md convention only in this slice; no multi-agent panel CLI yet.

## Ratification
- by: operator (this branch implements the thin core agreed in design)
- product_rev: 1
