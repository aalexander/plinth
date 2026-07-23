<!-- Plinth shared model guidance. Version-pinned; propagates via `plinth update`.
     This is the file that changes when the model landscape changes. -->
# Plinth — Model Assignments (v4, July 12 2026)

## Context
Fable 5 launched June 9, was suspended June 12 by US export controls (Amazon
jailbreak report), and relaunched globally July 1 with a retrained safety
classifier. The June 22 plan-inclusion date in v2 is void.

July 12: the frontier is multi-vendor. GPT-5.6 Sol out-reasons Opus 4.8, Grok 4.5
delivers near-parity coding at a fraction of the wall-clock, and Fable 5's
availability is export-control-volatile (suspended once already; may lapse again).
v4 therefore stops assuming an Anthropic driver: seats are assigned per model,
judgment is imported per-decision, and every seat has a named fallback.

## Seat assignment (v4) — one seat per model, judgment imported per-decision

| Seat | Model | Wiring |
|------|-------|--------|
| **Architect** — the resident session: judgment, specs, routing, final read-only audit (DEFAULT) | **Fable 5** by exception / **Opus 4.8** (Claude Code is the harness) | Guard + Stop gate ENFORCED; the coding volume goes to the Worker lane. The architect does not type routine code and does not edit the worker's diff directly — corrections go back as specs |
| **Worker** — most of the coding | **Grok 4.5** (`grok-implementer` lane; codex lane = cross-vendor second implementation) | Five-part spec in, scope-checked diff out; escalates open questions to the architect. ALTERNATIVE topology: grok-RESIDENT (grok CLI as harness) for wall-clock-critical sessions — carries the known limitation (review contract-bound until the receipt check ships) and consults judgment via `plinth advise` |
| **Advisor** — judgment, consulted per-decision | **Fable 5** (peer tier: Opus 4.8) | `advisor_vendor = claude` (default), `advisor_model = opus`, `advisor_model_max = fable` — scaffolded by `plinth init` |
| **Reviewer** — the adversarial gate | **GPT-5.6** | `reviewer_vendor = codex` (default) + `reviewer_model_tier1/tier2 = gpt-5.6` — scaffolded COMMENTED; uncomment once your account is eligible (GA July 9 2026, Codex CLI >= 0.144.0) |
| **Audit** — Tier-2 second opinion | **Claude** (Opus 4.8) | `audit_vendor = claude`, `audit_model = opus` (both scaffolded) — a different FAMILY than both the WORKER (the diff's producer) and the reviewer, in either topology; pinned so a Sonnet/Fable CLI default can't drift the seat |

Why this shape: repeated lane calibration showed Grok at ~even quality and 3–6×
the speed of the codex lane on well-specified work, so the seat that types the
most goes to the fastest near-parity model — while the ARCHITECT stays resident
in the Claude harness, which keeps the guard and Stop gate enforced (the
grok-resident alternative trades that gate for wall-clock and consults judgment
UP per-decision via `plinth advise`). Three models work together: architect
(judgment), worker (volume), reviewer (the gate) — plus the cross-vendor
auditor on Tier 2.

Honest scope of the evidence: the calibration measured the LANE seat
(well-specified typing). Grok in the DRIVER seat — decomposition, routing, loop
discipline — is exactly what v4 is testing. The tell that judgment needs to move
back toward the driver (consult more, or restore a Claude driver): rising review
round counts, or reviewer findings clustering on design errors rather than
typing errors.

Under the grok-RESIDENT alternative the implementer lanes are dormant (they are Claude-Code
subagents) — and mostly moot, since the driver already is the cheap fast typist.
Under the architect-resident DEFAULT they are the worker seat. A grok-resident driver
that wants a second implementation shells out to `codex` directly with the same
five-part spec and `.plinth/lane-guard.sh` (preflight / snapshot / scope are
vendor-neutral shell).

What a non-Claude driver does and doesn't get: grok reads the driver contract
(both contract files); whether it EXECUTES `.claude/` hooks is probeable, not
assumed — run `plinth hookprobe grok` (shipped; one small capped model call that
reports EACH of the four enforcement hook events separately). At release time
grok 0.2.93 reported NONE executed (reproduce: plinth hookprobe grok): no in-session guard hooks, no Stop gate.
Re-run after CLI upgrades; a NOT-invoked event is certainly unenforced, an
INVOKED one is necessary-but-not-sufficient (verify end-to-end) — this section
is the floor unless end-to-end verification passes. The binding layer is unchanged and vendor-neutral: `review.sh` /
`risk-classify.sh` are plain shell, verdicts bind to commit SHAs, and branch
protection's required checks gate every merge regardless of driver — but those
required checks verify the CI floor and tooling integrity, not the review
verdict, and the Codex cloud review cannot close that gap (it posts PR comments;
there is no status-check context to require). The server-verifiable
APPROVED-at-HEAD receipt check — shipping with auto mode — is the designated
adversarial gate for the default path. (If in-session interception ever proves
necessary, the designated fix is one CI-side protected-paths tamper check —
vendor-neutral, covers every driver — not per-vendor hook ports.)

### Contingency — Fable access lapses (live risk)
Fable has been suspended once already and runs credits-only with no metered
fallback; treat its availability as day-to-day. If it lapses, move the advisor
seat to GPT-5.6 — `advisor_vendor = codex`, `advisor_model = gpt-5.6`,
`advisor_model_max = gpt-5.6` — and change nothing else. Advisor and reviewer
sharing a family is acceptable (the advisor is collaborative and non-blocking,
not a gate), but keep `audit_vendor = claude`: Opus 4.8 is unaffected by Fable's
status and keeps a third family on every Tier-2 approval. If you weigh family
diversity over raw capability for the advisor, Opus 4.8 remains a capable peer
pick; the assignment above follows capability (5.6 Sol > Opus 4.8) and the
advisor ≥ driver rule.

## Claude driver — route your model to the work (speed & efficiency)
This section applies when an Anthropic model holds the driver seat (a Claude Code
session) — see Seat assignment above for the v4 default.
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
  Every advisor runs role-isolated from the repo's auto-loaded DRIVER contract
  (claude `--safe-mode`; codex doc-suppression; grok `--rules`; agy relies on the
  prompt's role-scope line) while keeping the repo readable.
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
codex/grok delegate inherits `.claude/` hooks only if its CLI executes them — per-CLI,
probe with `plinth hookprobe`; see plinth-rules.md). As with
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
has whole-tree write and (per the hookprobe result for its CLI — grok 0.2.93: no
hook execution) typically does not run the `.claude/` guard, so each lane enforces
`.plinth/lane-guard.sh scope` (with a pre-run `lane-guard.sh snapshot`) after the run — every tracked change +
new file must be a spec file and must not touch a protected path, AND no sensitive path (secrets/keys,
protected — even gitignored) may have been added/changed/repointed by the lane (else SCOPE VIOLATION,
not accepted; it fails loud if the diff is uncomputable or a sensitive file is unhashable).
`.plinth/session/` verdict/receipt state is compared too — a delegated CLI bypasses the `.claude/`
guard, so scope is what stops it forging a fake approval; only the hook-appended
`.plinth/session/events.jsonl` (pulse.sh, every tool use) is excluded to avoid false-flagging every
clean lane. The scope is drawn at
the ERRORS a fallible lane makes, not an adversarial sandbox — it catches a lane planting secrets
or a fake verdict, but non-sensitive gitignored artifacts (`node_modules/`, `dist/`) are legitimate
lane output and don't trip it (rejecting them would break `npm install`/builds). Those it REPORTS,
not rejects: `scope` prints a non-blocking note that the lane's verification is not hermetic (it ran
against un-reviewed ignored state) — so you re-run verification yourself and treat CI's fresh install
as the authority, rather than trusting the lane's in-session evidence blindly. A lane that returns
`unavailable`/`timeout`
gets its spec re-routed to the other lane — never a silent substitution.

**Cross-vendor, mostly free.** Both lanes are non-Anthropic families, so a Claude/Fable
driver judges an independent-vendor diff unconditionally. Plinth's PR reviewer is a second
independent family only when `reviewer_vendor` differs from the lane's producer — it is NOT
for a codex lane under the DEFAULT codex primary, nor a grok lane under a grok primary; in
those pairings the independent checks are the driver plus the Tier-2 claude audit (Tier-1
lane work gets no audit — route to the OTHER lane if reviewer independence matters there).
For high-stakes work, race `grok-implementer` and `codex-implementer` on the SAME spec and
keep the stronger diff — a third independent perspective for one extra lane's cost. Race
with ISOLATION, never concurrently in one checkout: both lanes write the shared working
tree and `scope` authorizes by PATH, not producer, so parallel same-checkout runs
interleave into one mixed diff neither lane produced. Run them SEQUENTIALLY (run one,
capture its diff, reset clean, run the other) or spawn each lane subagent in its own git
worktree (the driver's subagent worktree isolation).

(The lanes are Claude-Code subagents, so they apply when the DRIVER is Claude/Fable — the
architect-delegates-to-cheaper-family topology. A non-Claude driver delegates via its own
mechanism; the spec contract and Rule-10 verification are the same. Pattern adapted from
DannyMac180/fable-advisor.)

## Reviewer: Codex / GPT-5.6 (v4)
The v4 primary reviewer model is GPT-5.6: set `reviewer_model_tier1/tier2 =
gpt-5.6` in `.plinth/config` (passed as the codex `-m` flag per tier), or move
the vendor default with `model = "gpt-5.6"` in `~/.codex/config.toml`
(`model_reasoning_effort = "high"`). Rollout: June 26 to ~20
US-government-approved organizations; GA July 9, 2026 across ChatGPT/Codex —
but access is still PER-ACCOUNT (eligibility) and needs Codex CLI >= 0.144.0.
Activate the seat once `codex -m gpt-5.6` works on your account: uncomment the
two scaffolded tier lines. They ship COMMENTED because an active gpt-5.6 knob
on an ineligible account (or an older CLI) makes the reviewer fail loud rather
than fall back — one probe command, then one uncomment. An ineligible account
stays on the GPT-5.5 vendor default meanwhile. (The advisor knobs ARE
scaffolded live: `plinth advise` is
non-blocking by design, so a missing Fable reports unavailable instead of
breaking anything.) The Codex
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
- **codex** — goes DEEPEST. The DEFAULT primary at all tiers, and does the
  binding clean-slate confirmation. Slower. Runs GPT-5.5 (the vendor default)
  until your account is GPT-5.6-eligible (GA July 9 2026; Codex CLI >= 0.144.0),
  then uncomment the scaffolded `reviewer_model_tier1/tier2` knobs to seat the
  v4 reviewer (Reviewer section above).
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
- `audit_vendor` = codex | claude | grok | agy runs that vendor's OWN CLI as the cross-vendor
  SECOND opinion (a separate binary), independent of the primary. If not installed/signed
  in, the audit is UNAVAILABLE (non-blocking) and the primary review stands —
  surface it (dashboard shows "audit unavailable"), don't read a missing audit as a
  pass. Pick a DIFFERENT vendor than `reviewer_vendor` (the audit is suppressed when
  they match) — e.g. a grok PRIMARY needs `audit_vendor = codex` (or claude/agy), not grok.
- `reviewer_model_tier1/tier2` set the per-tier MODEL the reviewer_vendor runs (its
  own model flag; codex/grok `-m`, claude `--model`). Unset = the vendor default.
  (To make a non-OpenAI model primary, just set `reviewer_vendor` — no
  `~/.codex/config.toml` model_provider needed anymore.)

Default scaffold (`plinth init` writes `.plinth/config`): `audit_vendor = claude` —
the v4 audit seat, a different family than both the WORKER (the diff's producer) and the codex
reviewer (needs the `claude` CLI signed in; a non-fatal UNAVAILABLE if not).
Under a Claude driver flip it to grok or agy to keep the audit cross-family.
Revisit on any model/subscription change.

## Trust note (from the Fable 5 system card)
Agent self-reports during autonomous runs are partly grader-aware performance —
the code is the code; the commentary is partly theater. Plinth's trust order is:
deterministic floor (CI) > cross-model review > driver self-report. Never relax a
gate because the driver's summary sounded diligent.
