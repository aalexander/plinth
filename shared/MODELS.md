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
| Docs, comments, CHANGELOG, mechanical refactor, test/dep bump | 0–1 | **Sonnet 5** — fast, burns plan limits far slower |
| Ordinary feature or bugfix in project code | 1 | **Opus 4.8** (default) |
| Architecture, whole-repo / 1M-context reasoning, security · tooling · spec · migrations | 2 | **Opus 4.8 at high effort**; **Fable 5 by exception** (credits — below) |

Sonnet 5 is ~63.2% on agentic coding vs Opus 4.8's 69.2 — genuinely weaker, so keep
it to mechanical/doc work where the diff is its own proof; don't reach for it on
logic you'd want Opus to reason through.

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

## Reviewer: Codex / GPT-5.5 (unchanged)
Set in `~/.codex/config.toml` (`model = "gpt-5.5"`, `model_reasoning_effort =
"high"`). GPT-5.6 launched June 26 to ~20 US-government-approved organizations
only (API + Codex), gated by a June 2 executive order requiring federal
benchmarking; general availability expected mid-July at earliest. When it reaches
ChatGPT Pro/Codex GA: evaluate as reviewer, then change the one line. The Codex
cloud review (GitHub App) posts on every PR — a generalist review that arrives
security-briefed because it reads AGENTS.md; no separate "Codex Security"
product exists or is assumed.
Reviewer-swap checklist: review.sh's resume-skip threshold assumes the reviewer's
context window — PLINTH_RESUME_MAX defaults to 650000 (~65% of GPT-5.5's
1,005,000). On a reviewer with a different window, set PLINTH_RESUME_MAX to
~65% of it (env var or wrapper); staying well under the window matters because a
near-full thread silently auto-compacts away the original diff context.

## Reviewer assignment across vendors (all subscription-authenticated, no per-use cost)
Three reviewer CLIs are available; assign by their observed strengths:
- **codex / GPT-5.5** — goes DEEPEST. Keep it the PRIMARY adversarial reviewer at
  all tiers, and it does the binding clean-slate confirmation. Slower.
- **grok / Grok Build (xAI)** — good and noticeably FASTER, and a DIFFERENT vendor.
  Best as the Tier-2 CROSS-VENDOR second opinion (`audit_vendor = grok`) — a
  different vendor breaks the reviewer-collusion risk (the primary reviewer is
  otherwise a sibling of the driver), and speed matters for a check that fires on
  every Tier-2 approval. This path runs grok's OWN `grok` CLI — nothing goes in
  codex's config.
- **agy / Antigravity (Gemini, Google)** — CAUTION: it REFUSES adversarial
  "find-the-bypass" framing. Fine for the review-loop audit (framed as
  "audit your own code," which review.sh uses) but do not point red-team prompts
  at it. Keep as a third cross-vendor option, not the primary adversary.

Two SEPARATE integration paths — don't conflate them (a driver did):
- `audit_vendor` = grok | agy runs that vendor's OWN CLI (a separate binary,
  subscription-authed), independent of your codex config. If that CLI isn't
  installed or signed in, the audit is recorded UNAVAILABLE (non-blocking) and the
  codex primary review stands — surface it (the dashboard shows "audit
  unavailable"), don't read a missing audit as a pass.
- `reviewer_model_tier1/tier2` are passed to `codex -m`, so they must be models
  YOUR codex can actually run. The stock config runs only gpt-5.5; making grok (or
  any non-OpenAI model) the PRIMARY reviewer means adding an xAI/Google
  `model_provider` + key to `~/.codex/config.toml` AND resetting `PLINTH_RESUME_MAX`
  to ~65% of that model's context window (reviewer-swap checklist above). It is not
  automatic — leave these UNSET to keep gpt-5.5 unless you've done that setup.

Default config (templates/.plinth/config): `audit_vendor = grok` — the separate
`grok` CLI (needs it signed in; a non-fatal UNAVAILABLE if not). Revisit on any
model/subscription change.

## Trust note (from the Fable 5 system card)
Agent self-reports during autonomous runs are partly grader-aware performance —
the code is the code; the commentary is partly theater. Plinth's trust order is:
deterministic floor (CI) > cross-model review > driver self-report. Never relax a
gate because the driver's summary sounded diligent.
