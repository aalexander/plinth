<!-- Plinth shared model guidance. Version-pinned; propagates via `plinth update`.
     This is the file that changes when the model landscape changes. -->
# Plinth — Model Assignments (v3, July 7 2026)

## Context: what happened in June
Fable 5 launched June 9, was suspended June 12 by US export controls (Amazon
jailbreak report), and relaunched globally July 1 with a retrained safety
classifier. The June 22 plan-inclusion date in v2 is void; the new terms are below.

## Driver — route your model to the work (speed & efficiency)
Default driver: **Opus 4.8** — pure subscription, no metering. From there, route
DOWN for cheap work and UP only when the task earns it. The reviewer is already
routed by a deterministic risk tier (`risk-classify.sh`, which you cannot edit or
de-escalate); point your OWN model at the SAME tier the change will land in, so a
cheap change stays cheap end to end:

| The work | Tier it lands in | Drive with |
|----------|-----------------|------------|
| Docs, comments, CHANGELOG, mechanical refactor | 0–1 | **Sonnet 5** — fast, burns plan limits far slower |
| Ordinary feature or bugfix in project code | 1 | **Opus 4.8** (default) |
| Architecture, whole-repo / 1M-context reasoning, security · tooling · spec · migrations | 2 | **Opus 4.8 at high effort**; **Fable 5 by exception** (credits — below) |

Sonnet 5 is ~63.2% on agentic coding vs Opus 4.8's 69.2 — genuinely weaker, so keep
it to mechanical/doc work where the diff is its own proof; don't reach for it on
logic you'd want Opus to reason through. Note: model tier ≠ review tier. A
dependency bump or a test edit is mechanical enough to DRIVE with Sonnet, but the
classifier still routes it to Tier 2 review (deps/tests/tooling are high-
consequence to *verify*, whoever wrote them) — the two axes are independent.

Your one lever over review COST is tier hygiene: a single Tier-2 signal anywhere in
a diff pulls the WHOLE change onto the deep clean-slate + cross-vendor path. Land
low-risk work in its own commit/PR instead of bundling a doc tweak or refactor into
a security/tooling change. That tier hygiene is the ONLY "direction over the
reviewer" you have — you never pick the reviewer, the diff does.

This routing is GUIDANCE, not a gate. Your model choice is a self-interested
speed/cost call with no adversarial stakes: the CI floor and cross-model review
catch bad work regardless of which model wrote it, so nothing enforces your choice
and nothing should. That asymmetry is deliberate — the reviewer's tier is the
immutable adversarial gate; your own model is your business, so it stays doc
guidance, not a new knob or script.

### Fable 5 by exception (usage credits)
Fable 5 left plan inclusion; it runs ONLY on prepaid usage credits at API rates
($10/$50 per MTok) with NO automatic metered fallback — if credits aren't enabled
or run out, access stops mid-task. Reserve it for the Tier-2 long-horizon work where
its 1M-context edge is worth ~2x Opus API rates, and enable a small credit balance
WITH a monthly cap first. (Fable's retrained safety classifier still flags more real
code and can bounce a coding session to Opus mid-run — if a session feels different,
that's why.) Anthropic intends to restore Fable 5 to standard subscription "when
capacity allows" — check before buying credits in bulk.

## Orchestration
`/effort` -> `ultracode` for substantive tasks (model-managed dynamic workflows);
default effort for routine ones. The model chooses decomposition; the gates make
that safe.

## Advisor — consult a model as good or BETTER than the driver
`plinth advise [--impactful] "<question>"` is a COLLABORATIVE, non-blocking,
driver-initiated consult — distinct from the adversarial reviewer (the gate) and the
auditor (a second opinion on an approval). Vendor-agnostic and cross-family: any driver
can consult any advisor CLI, so a Grok driver can ask Fable.
- `advisor_vendor` (claude|codex|grok|agy) picks the advisor CLI (default claude).
- `advisor_model` is the PEER tier; `advisor_model_max` the ESCALATED tier. `plinth
  advise` uses the peer model; `plinth advise --impactful` uses the max model. Both
  should be >= the driver model.
- Reserve `--impactful` for IMPACTFUL, ARCHITECTURAL, or hard-to-reverse decisions (a
  schema, a public interface, a security boundary, a migration strategy) — not merely
  "hard" problems. Recommended: peer = your driver's own frontier (e.g. Opus 4.8); max =
  Fable 5 — its 1M-context, cross-family perspective earns the credit cost on exactly
  these calls (see Fable-by-exception).
- Claude driver, OPTIONAL enhancement: Claude Code's native advisor (`advisorModel:
  fable` / `--advisor` / `/advisor`) consults a stronger model over the FULL conversation
  and enforces advisor >= main automatically. Use it when the advisor should see the
  whole session; `plinth advise` is the vendor-neutral floor that works for every driver.
- Router seam: the knob shape (advisor_vendor / advisor_model / advisor_model_max) is
  structured so an external "route to the best model for this task" service could drop in
  later without changing the surface. Not built now — native selection suffices.

## Subagent routing
Fan out independent work to subagents for speed; route EACH to the best model for its
part. Cheap/fast (Sonnet, or a lighter model) for mechanical or heavily-parallel fan-out
where the diff is its own proof; a strong model (Opus at high effort, Fable by exception)
for the hard or high-consequence pieces. Prefer in-family for parallel fan-out; a
cross-family CLI shell-out routes a single subtask to another family's strength (such a
codex/grok delegate does not inherit the `.claude/` hooks — see plinth-rules.md). As with
the driver, model tier != review tier: the classifier routes the RESULT by risk
regardless of which model wrote it.

## Implementer lanes — the architect pattern (cost lever)

Implementation mechanics — boilerplate, wiring, CRUD, mechanical edits, test bodies — are
most of a session's tokens, and a cheaper cross-family model types them at near-parity.
So the frontier driver should behave like an ARCHITECT: emit judgment (decomposition,
interfaces, specs, routing, verdicts on diffs), and DELEGATE the typing to a cheaper lane.
Two shipped subagents do exactly this — they drive an external CLI and VERIFY the result:

| Lane | Producer | Agent | Route here when |
|---|---|---|---|
| Routine | Grok (xAI) | `grok-implementer` | The spec fully determines the outcome. **Default lane.** Needs the `grok` CLI. |
| Cross-vendor | codex (OpenAI) | `codex-implementer` | Correctness is critical enough to want a second implementation, or grok is unavailable. Needs the `codex` CLI. |

**Cost discipline (the point of the pattern).** The driver's context is re-read at driver
prices every turn. So: emit judgment, not volume — a code block longer than an interface
signature is a spec that hasn't been delegated yet. Keep the context lean — delegate broad
searches/log-grepping to a cheap read-only subagent and keep only conclusions. Reason once,
then hand off — capture the hard thinking in the spec and let the lane carry it. Fixing a
lane's bug by hand is the same failure in disguise: send a corrected spec back.

**The five-part spec** every lane receives (they share none of your context): objective ·
files · interfaces · constraints · verification command. A spec you can't finish writing
means the decision isn't made yet — that's architect work, not a reason to hand a cheaper
model the ambiguity.

**Verification + scope (Rule 10).** A lane's report is a claim; the diff and your own re-run of
the verification command are the evidence. "The lane said it works" is forbidden. A delegated CLI
has whole-tree write and does not run the `.claude/` guard, so each lane enforces `.plinth/lane-
guard.sh scope` (with a pre-run `lane-guard.sh snapshot`) after the run — every tracked change +
new file must be a spec file and must not touch a protected path, AND no sensitive path (secrets,
`.plinth/session/`, protected — even gitignored) may have been added/changed by the lane (else
SCOPE VIOLATION, not accepted; it fails loud if the diff is uncomputable). That catches a lane
planting secrets or a fake verdict; non-sensitive artifacts like `node_modules/` don't trip it. A lane that returns `unavailable`/`timeout`
gets its spec re-routed to the other lane — never a silent substitution.

**Cross-vendor for free.** Both lanes are non-Anthropic families, so a Claude/Fable driver
(and Plinth's reviewer at PR) judges an independent-vendor diff. For high-stakes work, race
`grok-implementer` and `codex-implementer` on the SAME spec and keep the stronger diff — a
third independent perspective for one extra lane's cost.

(The lanes are Claude-Code subagents, so they apply when the DRIVER is Claude/Fable — the
architect-delegates-to-cheaper-family topology. A non-Claude driver delegates via its own
mechanism; the spec contract and Rule-10 verification are the same. Pattern adapted from
DannyMac180/fable-advisor.)

## Reviewer: Codex / GPT-5.5 (unchanged)
Set in `~/.codex/config.toml` (`model = "gpt-5.5"`, `model_reasoning_effort =
"high"`). GPT-5.6 launched June 26 to ~20 US-government-approved organizations
only (API + Codex), gated by a June 2 executive order requiring federal
benchmarking; general availability expected mid-July at earliest. When it reaches
ChatGPT Pro/Codex GA: evaluate as reviewer, then change the one line. The Codex
cloud review (GitHub App) posts on every PR — a generalist review that arrives
security-briefed because AGENTS.md (the driver shell it auto-loads) directs any
reviewer to read the reviewer contract `.plinth/reviewer.md`; no separate "Codex
Security" product exists or is assumed.
Reviewer-swap checklist: review.sh's resume-skip threshold now scales per
`reviewer_vendor` (~65% of that vendor's context window) automatically;
PLINTH_RESUME_MAX (env) still overrides. Staying well under the window matters
because a near-full thread silently auto-compacts away the original diff context.

## Reviewer assignment across vendors (all subscription-authenticated, no per-use cost)
Any of codex / claude / grok can be the PRIMARY reviewer via `reviewer_vendor`
(default codex); assign by their observed strengths:
- **codex / GPT-5.5** — goes DEEPEST. The DEFAULT primary at all tiers, and does the
  binding clean-slate confirmation. Slower.
- **claude / Anthropic** — native, ~1M window, resumes warm threads. A capable
  primary; runs with `--safe-mode` — isolates it from the repo's CLAUDE.md (and other
  project customizations) while keeping OAuth auth (unlike `--bare`, which needs an
  API key).
- **grok / Grok Build (xAI)** — good and noticeably FASTER, and a DIFFERENT vendor
  from a Claude/Codex driver. Strong either as the FAST primary (`reviewer_vendor =
  grok`) or as the Tier-2 CROSS-VENDOR second opinion (`audit_vendor = grok`) — a
  different vendor breaks reviewer-collusion risk. Reports no headless token usage,
  so it runs fresh/verify each round (no warm resume).
- **agy / Antigravity (Gemini, Google)** — CAUTION: REFUSES adversarial
  "find-the-bypass" framing. Fine for the review-loop audit (framed as "audit your
  own code") but not as the primary adversary — audit_vendor only.

Three SEPARATE integration paths — don't conflate them (a driver did):
- `reviewer_vendor` = codex | claude | grok picks the PRIMARY reviewer's OWN CLI —
  who runs the primary adversarial review. Default codex (no setup). claude/grok
  need only their own CLI installed + signed in; NOTHING goes in codex's config.
  review.sh sets the resume threshold per vendor automatically.
- `audit_vendor` = codex | grok | agy runs that vendor's OWN CLI as the cross-vendor
  SECOND opinion (a separate binary), independent of the primary. If not installed/signed
  in, the audit is UNAVAILABLE (non-blocking) and the primary review stands —
  surface it (dashboard shows "audit unavailable"), don't read a missing audit as a
  pass. Pick a DIFFERENT vendor than `reviewer_vendor` (the audit is suppressed when
  they match) — e.g. a grok PRIMARY needs `audit_vendor = codex` (or agy), not grok.
- `reviewer_model_tier1/tier2` set the per-tier MODEL the reviewer_vendor runs (its
  own model flag; codex/grok `-m`, claude `--model`). Unset = the vendor default.
  (To make a non-OpenAI model primary, just set `reviewer_vendor` — no
  `~/.codex/config.toml` model_provider needed anymore.)

Default config (templates/.plinth/config): `audit_vendor = grok` — the separate
`grok` CLI (needs it signed in; a non-fatal UNAVAILABLE if not). Revisit on any
model/subscription change.

## Trust note (from the Fable 5 system card)
Agent self-reports during autonomous runs are partly grader-aware performance —
the code is the code; the commentary is partly theater. Plinth's trust order is:
deterministic floor (CI) > cross-model review > driver self-report. Never relax a
gate because the driver's summary sounded diligent.
