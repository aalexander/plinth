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
9. Review anti-thrash (instrument): cooperative-driver threat model; HANDOFF
   excluded + HANDOFF-only **base…HEAD** floor; BUILD asymptotic coverage →
   minor; out-of-pathspec demotion only for thrash classes; never demote
   external security; sticky AUTO thrash-classes only; dual-pass in HARDEN
   Tier-2 only; same-open soft cap; VERSION exact top-H2 match; NEEDS-HUMAN
   project-owned.
10. Phase slug encode (no feat/a-b vs feat/a/b collision); findings round sort
    by basename N; handoff preserves Goal/Evidence/Risks + pre-archive;
    `plinth next` exit 3 when idle.

## Risks / trust boundaries
Ship path must not weaken. Phase file is session-local under `.plinth/session/`
(agent-unwritable via protected paths). Missing phase = build (default).
Corrupt/unknown phase = harden (fail closed, matches Stop). Driver is not an
internal adversary; instrument gaming is canary/CI/receipt, not review thrash.
Thrash demotions fail-closed on external security / ship integrity.

## Open tradeoffs
- **Harden sticky until build/clear:** yes — explicit `plinth build` to leave.
- **Plan tooling:** light scaffold always; `--deep` reuses configured seats (ratified for v5).
- **Thrash demotion vs rigor:** deterministic demotion of known thrash classes;
  real blocking classes always keep major/blocker.

## Ratification
- by: operator (this branch implements lifecycle v5 + dashboard ops + review
  anti-thrash agreed in design / land loop)
- product_rev: 1
