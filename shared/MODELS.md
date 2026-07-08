<!-- Plinth shared model guidance. Version-pinned; propagates via `plinth update`.
     This is the file that changes when the model landscape changes. -->
# Plinth — Model Assignments (v3, July 3 2026)

## Context: what happened in June
Fable 5 launched June 9, was suspended June 12 by US export controls (Amazon
jailbreak report), and relaunched globally July 1 with a retrained safety
classifier. The June 22 plan-inclusion date in v2 is void; the new terms are below.

## Driver — two phases

### Through July 7: Claude Fable 5 (use this window)
Included on Pro/Max/Team/select Enterprise for up to 50% of weekly usage limits.
Select via `/model` in Claude Code. Spend the window on the work that justifies it:
long-horizon architecture, whole-repo analysis (1M context), the hardest tasks.
Two cautions:
- Fable 5 draws down plan limits faster than Opus 4.8 for equivalent work.
- The retrained classifier flags more real code; some coding/debugging sessions
  fall back to Opus 4.8 automatically. If a session feels different, that's why.

### From July 8: Claude Opus 4.8 (default), Fable 5 by exception
Fable 5 leaves plan inclusion and runs ONLY on prepaid usage credits at API rates
($10/$50 per MTok). There is NO automatic metered fallback: if credits aren't
enabled or run out, Fable 5 access stops mid-task. Policy:
1. Default driver: **Opus 4.8** — pure subscription, no metering.
2. Optionally enable a small usage-credit balance WITH a monthly cap, reserved for
   long-horizon tasks where Fable 5's edge is worth ~2x Opus API rates.
3. Anthropic states it intends to restore Fable 5 to standard subscription "when
   capacity allows" — check before buying credits in bulk.

## Routine/mechanical tier: Claude Sonnet 5
Launched July 1. ~63.2% agentic coding (Opus 4.8: 69.2). Intro pricing $2/$10 per
MTok through Aug 31, then $3/$15; on subscription it burns plan limits far slower.
Route mechanical refactors, test fixes, dependency bumps, and doc work here.

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
- **grok / Grok Build (xAI)** — good and noticeably FASTER. Best as the Tier-2
  CROSS-VENDOR second opinion (`audit_vendor = grok`) — a different vendor breaks
  the reviewer-collusion risk (the primary reviewer is otherwise a sibling of the
  driver), and speed matters for a check that fires on every Tier-2 approval.
  Also a good `reviewer_model_tier1` when you want faster ordinary-code review.
- **agy / Antigravity (Gemini, Google)** — CAUTION: it REFUSES adversarial
  "find-the-bypass" framing. Fine for the review-loop audit (framed as
  "audit your own code," which review.sh uses) but do not point red-team prompts
  at it. Keep as a third cross-vendor option, not the primary adversary.

Default config (templates/.plinth/config): `audit_vendor = grok`,
`verify_sample_rate = 10`. Trust-but-verify (verify_sample_rate) is ON by default
— a random tenth of low-risk changes get a full review so tier honesty is
confirmed, not assumed. Revisit these on any model/subscription change.

## Trust note (from the Fable 5 system card)
Agent self-reports during autonomous runs are partly grader-aware performance —
the code is the code; the commentary is partly theater. Plinth's trust order is:
deterministic floor (CI) > cross-model review > driver self-report. Never relax a
gate because the driver's summary sounded diligent.
