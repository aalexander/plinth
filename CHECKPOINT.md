# Checkpoint — `feat/effort-seat-wiring` @ 88a1c61

Updated: 2026-07-30T03:10:00Z · Phase: **build** (harden only for S7 ship) · Snapshot: **S1 landed** · Verdict: CHANGES_NEEDED @ 81909bc (pre-5.1, superseded)

context_advice: keep_cooking — S0+S1 done and committed; S2 is the security-critical slice. Resume: **docs/SHIP-BIAS-5.1.md** then this file.

## Goal
Ship **v5.1.0 ship-bias architecture**: dual OFF default, risk-triggered L3 security, thrash class demotion with receipt audit + never-demote security floor, APPROVED after one primary+verify with Noticed-only, L1 min canaries + L4 floor/receipt non-negotiable. Land prior product residual **without dual-e2e thrash**.

## Done
- Product residual 5.0.x train on this branch through `81909bc`.
- **S0** @ 81909bc→88a1c61: free canaries 8/8 PASS baseline; asymptotic classes confirmed already in MANUAL `## Noticed`; residual unbound (`bound:false`).
- **S1** @ `88a1c61`: dual OFF by default in EVERY phase (HARDEN no longer forces it); slice knob renamed `effort:medium|high|xhigh` → `rigor:standard|deep` (operator-ratified scope extension — the old vocabulary is the model layer's); deprecated key/env read for one release, writer emits `rigor` only; requested-dual-with-no-seat now fails closed (exit 2) BEFORE the paid round, with `PLINTH_ACK_NO_DUAL=1` recorded on request/verdict/receipt; VERSION 5.1.0 + CHANGELOG opened. Free canaries 8/8 PASS.

## Next

1. **S2 (xhigh — highest risk):** thrash class allowlist + never-demote floors. See survey below.
2. **S3:** receipt demotion ledger (`mint_receipt` payload + session artifact; receipt-verify tolerates old receipts — its schema check is a positive conjunction, so additive fields are already compatible).
3. **S4:** L3 risk-triggered security pass (trigger + one security-focused `run_auditor` + `security_pass` field + unit trigger matrix).
4. **S5:** reviewer contract — Noticed-only APPROVED, asymptotic never major, security never Noticed, class-emission rules.
5. **S6:** finalize MANUAL doctrine + MODELS (CHANGELOG/VERSION already opened in S1).
6. **S7:** one paid `./.plinth/review.sh` → **APPROVED@HEAD** → push + notes → PR → merge → tag `v5.1.0`.
7. **Do not:** re-open dual e2e as majors; HARDEN-default dual; dual in branch protection; driver-assigned demotion classes; delete receipt/unbind/dirty-tree fail-closed.

## S2 survey (done — implement from here)

Current machinery is **entirely text-classifier driven**; there are no reviewer-emitted class IDs yet.

- `thrash_policy_process_findings` — `shared/.plinth/review.sh:1592`. Demotion arms in the `.findings |= map(...)` chain at 1674–1702: ephemera, queue-nit, coverage-asymp (BUILD only), docs-prose, out-of-scope.
- Existing never-demote belts: `is_external_security` (1615), `is_real_test_gap` (1628), `is_precedence_must_block` (1635) — the last is checked FIRST so mixed wording can't be swallowed.
- `is_security_surface` (1611) already covers review/risk-classify/receipt/lane-guard/guard.sh/`.claude/hooks/`/`bin/plinth` + auth/crypto/secret/oauth/jwt/session source files.
- Sticky has its own **duplicate** `thrash_class` definition at three sites (1396, 1487, 1547) with `is_real_test_gap_desc` twins — the plan's "one source if possible" applies here.
- `risk-classify.sh` — Tier-2 path signals near line 61; `tier2_extra` from `.plinth/config` can only ADD Tier 2 and already fails closed on an invalid regex.

**Design tension to resolve at xhigh (do not skip):** the plan says *"reviewer-emitted class IDs only — driver must not assign demotion classes"* AND *"sticky/thrash may map description → class only via in-repo allowlist"*. Reconciliation: the class **vocabulary** is fixed in-repo (allowlist file, Tier-2 protected); the finding→class **mapping** may come from the reviewer's explicit `class:` emission or from the in-repo text classifier, but never from a field the DRIVER could author. Concretely: never trust a `class` key that survives from a prior round's driver-touched state, and keep `is_precedence_must_block` as the belt over any class-based demotion.

## Evidence
- Plan file: `docs/SHIP-BIAS-5.1.md` (S1 scope extension recorded in-line)
- Residual: unbound (`.plinth/RESIDUAL.json`)
- Free canary runner used locally: mirrors the `scaffold` job's network-free steps
- S1 commit: `88a1c61`

## Risks / Noticed
- **Demotion laundering** is the #1 risk — all three bounds required (reviewer-only classes, Tier-2 on allowlist edit, receipt demotion lines).
- `PLINTH_ACK_NO_DUAL` is disclosed via dedicated request/verdict/receipt fields, deliberately NOT added to `receipt-verify.sh`'s 5-name `override_ledger` allowlist (that path enforces exact tuple equality against the PR body). Flag in the PR body if ever used.
- Optional polish still open (non-blocking): dash `slice_title` chip; ETA-unknown display.

## Routing

<!-- plinth.checkpoint/v1 — machine-readable; ETAs reserved-null in v1 -->
```json
{
  "schema": "plinth.checkpoint/v1",
  "plan_ref": "docs/SHIP-BIAS-5.1.md",
  "slice_id": "s2-thrash-allowlist",
  "slice_title": "S2 thrash class allowlist + never-demote floors",
  "slice_index": 3,
  "slice_total": 8,
  "status": "implementing",
  "rigor": "standard",
  "rigor_rationale": "Ship-bias 5.1: one primary + verify is the gate; L3 covers the security-shaped surface. Driver reasoning effort is a HARNESS knob, deliberately not encoded here.",
  "implement": "driver",
  "updated_at": "2026-07-30T03:10:00Z",
  "elapsed_secs_slice": null,
  "eta_secs_slice": null,
  "eta_secs_plan": null
}
```
