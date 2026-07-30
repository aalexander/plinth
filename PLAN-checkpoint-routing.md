# Plan: Checkpoint + plan progress + slice rigor (dual-pass routing)

Status: APPROVED_WITH_CHANGES (claude fable + codex) — implementing v1 · Product cut after residual closeout (#58)

## Goal
Make plan position, resume state, and per-slice routing (rigor + implement seat)
first-class, machine-readable, and visible on the dashboard — as extensions of
**generalized model routing policy** (MODELS.md), not a separate ops product.

## Non-goals (v1)
- ML time prediction or fabricated ETAs
- Effort as a ship gate or review-tier override
- Forced always-worker topology
- Full rewrite of PLAN.md format

## Design (proposed)

### 1. Checkpoint rename (compat)
- Canonical file: root `CHECKPOINT.md`
- `HANDOFF.md`: if present without CHECKPOINT, still honored; `plinth checkpoint`
  writes CHECKPOINT and may refresh HANDOFF as a one-line pointer for one major
- CLI: `plinth checkpoint` primary; `plinth handoff` alias
- Auto-snapshots (harden/build/plan--deep/review) write CHECKPOINT

### 2. Machine-readable block
Fenced JSON at end of CHECKPOINT (or `.plinth/session/checkpoint.json` mirror):

```json
{
  "schema": "plinth.checkpoint/v1",
  "plan_ref": "PLAN.md",
  "slice_id": "R3",
  "slice_title": "optional short title",
  "slice_index": 3,
  "slice_total": 12,
  "status": "implementing|reviewing|blocked|done",
  "rigor": "standard|deep",
  "rigor_rationale": "one line",
  "implement": "driver|worker|either",
  "updated_at": "ISO-8601",
  "elapsed_secs_slice": 0,
  "eta_secs_slice": null,
  "eta_secs_plan": null
}
```

Markdown body keeps Goal/Done/Next/Restart for humans. Missing JSON → dashboard
shows presence only (today’s behavior); never block the loop.

> **v5.1 rename (2026-07-29):** the knob shipped in this train as
> `effort: medium|high|xhigh`. That vocabulary is owned by the model layer
> (reasoning effort), so v5.1 renamed it to `rigor: standard|deep` and reserved
> `effort` for model reasoning effort only. The fence above shows the CURRENT
> shape; the old key is read as a deprecated alias for one release. See
> `shared/MODELS.md` → "Slice routing (rigor + implement)".

### 3. Dashboard
Per-repo card: plan position (`i/n` + title), rigor badge, slice ETA, plan ETA
(null → “ETA unknown”). Snapshot adds `lifecycle.checkpoint` object from parse.

### 4. Rigor as routing (non-blocking)
- standard | deep recommended for *upcoming* slice (v5.0.x: medium|high|xhigh)
- Driver cannot change rigor → do not block; default **standard**, announce
- Biases the optional dual pass via MODELS guidance
- Independent of risk tier (review depth still classifier-owned)

### 5. Implement seat (driver vs worker)
- Default: judgment-shaped → driver; volume-shaped + well-specified → worker
- Not “always controllable worker” (coordination tax / context loss)
- Checkpoint records `implement` recommendation; driver may override without gate

### 6. Docs home
- MODELS.md: new “Slice routing (rigor + implement)” under routing policy
- plinth-rules / DRIVER: checkpoint resume; rigor non-blocking
- MANUAL: checkpoint command + dashboard fields

## Acceptance criteria
1. `plinth checkpoint` writes CHECKPOINT.md with valid `plinth.checkpoint/v1` when
   env/args supply slice fields; always preserves human sections
2. `plinth handoff` remains working alias
3. Dashboard smoke shows checkpoint progress fields when JSON present; unknown ETA
   when null
4. Missing rigor never fails `plinth next` / review / stop
5. MODELS documents rigor vs risk tier independence and worker routing rule
6. Canary or unit tests for JSON parse + HANDOFF fallback

## Advisor sign-off (2026-07-29)
- **Claude (fable, impactful):** APPROVE_WITH_CHANGES
- **Codex:** APPROVE_WITH_CHANGES
### Locked decisions
1. Pointer-only HANDOFF (mtime touch); CHECKPOINT is sole body authority.
2. Committed CHECKPOINT.md fence is source of truth; no session JSON as authority.
3. `plinth next` prints non-blocking `route:` line when valid.
4. ETAs reserved-null in v1; invalid JSON fail-soft; `implement: driver` = MODELS exception.
