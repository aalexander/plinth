# Ship-bias architecture — v5.1 (locked for implement)

**Status:** ratified by operator + `plinth advise --impactful` (Fable).  
**Branch target:** land on `feat/effort-seat-wiring` (or successor) as **VERSION 5.1.0**.  
**Not a product PLAN.md rewrite** — this is the instrument architecture delta for 5.1.

---

## One-sentence

Dual OFF by default; risk-triggered L3 security; thrash demotes only allowlisted classes with receipt audit; APPROVED after one primary + one verify when only Noticed/minors remain; L1 fail-open canaries + L2 primary + L4 floor/receipt stay non-negotiable.

---

## Layers (non-negotiable floor)

| Layer | What | Ship gate? |
|-------|------|------------|
| **L1** | Free fail-open canaries (minimum set below) | CI signal only |
| **L2** | One primary adversarial review (tier from `risk-classify`) + batch → one verify | **Yes** — APPROVED@HEAD |
| **L3** | Optional codex-security (or peer) — **risk-triggered only**, one pass, security severities | Not a merge check; can remint APPROVED |
| **L4** | floor + checks + receipt/strict | **Yes** — branch protection |

**Dual is optional rigor, not foundation.** Never a required check. Never HARDEN-default.

---

## Lifecycle defaults (behavior change)

### BUILD
- Free fail-open canaries anytime.
- **No paid review required to keep coding** (already true under default-build Stop).
- Feature-complete → **ONE primary** (risk tier) → batch fixes → **ONE verify**.
- Minors → Noticed; asymptotic → Noticed / thrash-demote (**demotable classes only**).
- `security.*` / reproduced-correctness → **never demote**.
- **APPROVED possible here** for non-security-heavy work when open majors/blockers = 0.

### HARDEN / PR intent
- **Dual: OFF default.** ON only `effort=xhigh` **or** `PLINTH_DUAL_PASS=1` / `--dual` equivalent.
- **Do not** dual merely because phase=hardening.
- Dual **requested** (xhigh or override) + auditor missing → **BLOCK** or explicit `--ack-no-dual` (not silent log-only). Default dual-skip (wanted=false) stays log-only.
- **L3 security:** if risk-classify security-sensitive **or** operator flag → one security-focused pass; fix security majors only; remint APPROVED@HEAD if needed.
- L3 path/trigger list **in-repo**; edits fail closed to Tier-2 (same pattern as `risk-classify.sh`).

### MERGE
- L4 only. Dual never required.

---

## What is removed from the critical path

- Dual as habit / HARDEN-default dual  
- Dual e2e canaries as **majors**  
- Second full generalist review for polish  
- Classifier perfection (NLP plan edges) as ship blockers  

## What is preserved

- Fail-open CI canaries (min set)  
- One real adversarial primary review  
- Optional deep security tool (L3)  
- Merge gates (APPROVED@HEAD + floor/checks/receipt)  
- Dirty-tree / unbind / residual honesty  

---

## Demotion fail-open bound (non-negotiable — advisor)

Class demotion is a **new fail-open**. Without all three bounds, ship bias **does** sacrifice security.

1. **Reviewer-emitted class IDs only** — driver must not assign demotion classes. Sticky/thrash may map description → class **only** via in-repo allowlist; never trust driver-supplied class for demotion.
2. **Allowlist (+ L3 triggers) in-repo** — e.g. `shared/.plinth/thrash-allowlist.json` (or embedded table in `review.sh` with canary extract). Diff touching allowlist / thrash demotion policy / L3 triggers → **Tier-2** (extend `risk-classify` or protect like classifier).
3. **Every demotion on the receipt** — `mint_receipt` includes demotion ledger (`id`, `class`, `from→to`, round). Laundering is auditable, not silent.

### Severity floor by class

| Class pattern | Demotable? |
|---------------|------------|
| `class:coverage-gap`, `class:canary-depth`, `class:fake-cli-argv`, `class:handoff-ws`, `class:sticky-ledger`, `class:docs-prose`, `class:queue-nit` | Yes → minor / Noticed |
| `security.*`, external security path/text, ship_integrity, data_loss, reproduced correctness / real test-gap / AC | **Never** |

Thrash text classifiers that already exist must be **tightened** to these class IDs; asymptotic dual-e2e / fake CLI wording maps to demotable classes **only** when not mixed with precedence-must-block wording (existing `is_precedence_must_block` belt).

---

## Dual matrix (5.1 — replace HARDEN-always)

`slice_dual_from_effort effort rphase override`:

| Condition | dual_wanted |
|-----------|-------------|
| `PLINTH_DUAL_PASS=1` / `--dual` | 1 |
| `PLINTH_DUAL_PASS=0` | 0 |
| `effort=xhigh` | 1 |
| else (including HARDEN + medium/high) | **0** |

Eligibility unchanged: fresh · r1 · Tier-2 · cross-vendor audit seat for actual run.  
`dual_wanted` remains **policy desire** (stamp note).  
**Requested dual + no auditor:** fail closed unless `PLINTH_ACK_NO_DUAL=1` (or flag) recorded on request/verdict/receipt.

Update canaries: drop “HARDEN always dual”; assert OFF default + xhigh/override on.

---

## L3 security pass (new)

- **Trigger:** risk-classify reasons match security-sensitive surface (auth/crypto/secrets/tooling ship path — list in-repo) **or** `PLINTH_SECURITY_PASS=1`.
- **Seat:** audit vendor preferred as security specialist (codex when primary ≠ codex; else peer). One pass.
- **Scope:** security severities / external security findings only — not a second full product review.
- **Unavailable:** record `security_pass: UNAVAILABLE` (like dual_degraded); **do not** false-concur. Whether unavailable blocks ship: **only if trigger fired and operator did not ack** — default = record + continue primary APPROVED for non-blocking best-effort **unless** config `security_pass_required=true` (optional later; v5.1 default = best-effort with loud note).
- **Honest v5.1 minimum:** wire trigger + one security-focused auditor prompt + receipt field; full “block on miss” can be config later.

---

## Minimum free canary set (do not cut further)

1. Verdict bind / unbind (stale APPROVED unreadable)  
2. Dirty-tree / git-status fail-closed  
3. Phase-scoped BLOCKING  
4. Auth/advise diagnostics  
5. Receipt ↔ HEAD comparison  

**Cuttable as majors:** dual e2e merge, fake CLI argv matrix, dash shape polish, plan NLP edges → Noticed / demotable thrash only.

---

## Doc / version surface

| Artifact | Change |
|----------|--------|
| `VERSION` | `5.1.0` |
| `CHANGELOG.md` | v5.1.0 section: dual OFF default; thrash class bounds + receipt demotions; L3 hook; canary doctrine; land of 5.0.8 product residual if same train |
| `shared/MODELS.md` + installed `.plinth/MODELS.md` | Live wiring table: dual only xhigh/override; HARDEN does **not** force dual; L3 risk-triggered |
| `MANUAL.md` | Ship-bias lifecycle; dual/L3; thrash allowlist; min canary set; Noticed asymptotic honesty |
| `shared/.plinth/reviewer.md` | APPROVED with Noticed-only OK; asymptotic not major; security never Noticed; class emission rules |
| `PLAN.md` AC #9 | Align anti-thrash text with dual-off + class demotion (if still claimed) |

---

## Implementation slices (Opus / driver execute in order)

### S0 — Close prior product without thrash (same train or first commit)
- Do **not** expand dual e2e canaries or fake-CLI argv theater.
- Leave asymptotic items under MANUAL `## Noticed` (already partly there).
- Free canaries green on existing suite (min set + current unit canaries).
- Residual stays **unbound** unless binding a real deferred major class with human note.

### S1 — Dual OFF default
- Change `slice_dual_from_effort`: remove HARDEN always-on.
- Messages, MODELS, canary-checkpoint-routing matrix.
- Requested dual + missing auditor → block or ack path + canary.

**S1 SCOPE EXTENSION — ratified by operator 2026-07-29 (knob rename).**
The slice knob shipped as `effort: medium|high|xhigh`, which collides with the
MODEL layer's reasoning-effort vocabulary (`/effort`, codex
`model_reasoning_effort`) while controlling only "run the dual pass?".
`shared/MODELS.md` used the same word in three senses in one file, and the
collision actively misled a driver session into reading the Plinth knob as a
thinking-effort request. Renamed to **`rigor: standard|deep`**:
- `slice_dual_from_effort` → `slice_dual_from_rigor`; `SLICE_EFFORT` →
  `SLICE_RIGOR`; `PLINTH_CHECKPOINT_EFFORT` → `PLINTH_CHECKPOINT_RIGOR`.
- The old fence key and env name are **read** for one release
  (`medium|high` → `standard`, `xhigh` → `deep`) with a one-time stderr note;
  the writer emits `rigor` only, so one `plinth checkpoint` migrates a
  downstream fence. Two independent alias implementations exist (shell in
  `review.sh`, python in `bin/plinth`) — the canary drives both per token and
  fails on divergence.
- `MODELS.md` now RESERVES `effort` / `medium|high|xhigh` for model reasoning
  effort, so the collision cannot return by the same route.
This is a `plinth.checkpoint/v1` fence-schema change (additive + aliased, so v1
stays readable). Deliberate deviation from the locked plan, recorded here
because this file is the spec for the work.

### S2 — Thrash class allowlist + floors
- Introduce versioned allowlist of demotable class IDs (file or single source in review.sh extracted by canary).
- Map known asymptotic phrases → demotable classes; keep `is_external_security` / `is_real_test_gap` / `is_precedence_must_block` as never-demote.
- Sticky thrash_class fingerprints align with allowlist (one source if possible).
- risk-classify: thrash-allowlist / demotion policy path → Tier-2.
- Canary: security-worded finding never demoted; coverage-asymp demoted in BUILD; allowlist edit → tier 2.

### S3 — Receipt demotion ledger
- After thrash_policy, record demotions into session artifact + `mint_receipt` payload.
- receipt-verify: tolerate/require demotions field if present (fail-open on old receipts; new receipts include array).
- Canary: demoted finding appears in mint payload.

### S4 — L3 security hook (minimum)
- Trigger from risk-classify reasons + env flag.
- One security-focused `run_auditor` (or dedicated prompt) on HARDEN/PR path or on APPROVED path when triggered.
- Verdict/receipt field `security_pass`.
- Canary: unit trigger matrix (no live seat required).

### S5 — Reviewer contract + BUILD approve path
- reviewer.md: Noticed-only APPROVED; forbid asymptotic majors; security floor.
- Confirm primary+verify can APPROVE with only minors (already true if thrash works).

### S6 — VERSION 5.1.0 + CHANGELOG + MANUAL doctrine
- Ship notes; dual e2e honesty stays Noticed not major.

### S7 — One paid review to APPROVED@HEAD
- Free canaries first.
- **Do not** feed the loop with dual-e2e majors as product work.
- On APPROVED: push + notes + PR + merge + tag `v5.1.0` + `plinth update` clients when operator wants pins.

---

## Explicit non-goals (v5.1)

- Dual in branch protection  
- Driver-chosen demotion class IDs  
- Deleting receipt / unbind / dirty-tree fail-closed  
- Perfect plan NLP / dash chips as ship blockers (optional follow-up: slice_title, ETA-unknown chips)  
- Full live dual_merge e2e in free CI  

---

## Success criteria

1. `slice_dual_from_effort high hardening` → **0**; `xhigh build` → **1**; override 0/1 respected.  
2. Free canary min set ALL PASS; dual matrix canary updated.  
3. Fabricated security major text is **not** thrash-demoted.  
4. Coverage-asymp / dual-canary-depth majors **are** demoted in BUILD (and HARDEN thrash class path as designed).  
5. Receipt for APPROVED includes demotion entries when any demotion occurred.  
6. VERSION=5.1.0; CHANGELOG top H2 matches.  
7. `./.plinth/review.sh` → **APPROVED@HEAD** without another dual-e2e thrash spiral.  
8. Residual unbound (or honestly bound only for real deferred product).  

---

## Correctness / security trade (locked)

| Concern | Mitigation |
|---------|------------|
| Miss product bugs | Mandatory primary + Rule 10 |
| Miss security bugs | Risk L3 + never-demote security floor — not dual theater |
| Ship fail-open | Fail-open canaries + residual hard; demotion bounds |
| Process forgery | Receipt/caller-control bounds unchanged |
| Dual catch rate | Slightly lower; L3 preferred for security-shaped issues |

Net: ship bias cuts sequential optional opinions and coverage majors — **not** L1+L2+L3+L4.

---

## Handoff note for Opus (Claude)

You are the DRIVER. Spec for this work is **this file** + existing product residual on the branch.  
Do **not** re-open dual e2e canaries as majors. Follow S0→S7.  
Commit on the feature branch; run free canaries; one paid review loop; land only with APPROVED@HEAD.  
Advisor non-binding; demotion bounds **are** non-negotiable.
