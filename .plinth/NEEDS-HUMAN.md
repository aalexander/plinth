# Blocked on you

- [ ] **Seat topology swap (your 2026-07-24 direction: Opus 5 driver / grok worker /
  gpt-5.6-sol reviewer / Fable 5 advisor).** `.plinth/config` is operator-only
  (guard-protected), so these are paste-ready — one command per repo, then commit on
  a branch (a seat change reviews as normal project code). Verified facts: codex-cli
  0.145.0; `codex exec -m gpt-5.6-sol` WORKS on your account; plain `gpt-5.6` is
  REJECTED ("not supported when using Codex with a ChatGPT account"). Driver seat is
  already done (`~/.claude/settings.json` → model opus, effortLevel high; codex
  reasoning effort xhigh → high).
  - **wren — do this one first: its reviewer seat is pinned `gpt-5.6`, which fails
    loud on your account, so wren's review loop is BRICKED until repinned:**
    `cd ~/Dev/wren && sed -i '' -e 's/^reviewer_model_tier1 = gpt-5.6$/reviewer_model_tier1 = gpt-5.6-sol/' -e 's/^reviewer_model_tier2 = gpt-5.6$/reviewer_model_tier2 = gpt-5.6-sol/' -e 's/^advisor_model = opus$/advisor_model = fable/' .plinth/config`
  - **plinth:**
    `cd ~/Dev/plinth && sed -i '' -e 's/^reviewer_vendor = claude/reviewer_vendor = codex/' -e 's/^reviewer_model_tier1 = sonnet/reviewer_model_tier1 = gpt-5.6-sol/' -e 's/^reviewer_model_tier2 = sonnet/reviewer_model_tier2 = gpt-5.6-sol/' -e 's/^audit_vendor = grok/audit_vendor = claude/' -e 's/^advisor_model = opus/advisor_model = fable/' .plinth/config && printf 'audit_model = opus\n' >> .plinth/config`
  - **anvil:**
    `cd ~/Dev/anvil && sed -i '' -e 's/^reviewer_vendor = claude/reviewer_vendor = codex/' -e 's/^reviewer_model_tier1 = sonnet/reviewer_model_tier1 = gpt-5.6-sol/' -e 's/^reviewer_model_tier2 = sonnet/reviewer_model_tier2 = gpt-5.6-sol/' -e 's/^audit_vendor = codex/audit_vendor = claude/' -e 's/^advisor_model = opus/advisor_model = fable/' .plinth/config && printf 'audit_model = opus\n' >> .plinth/config`
  - **certeus (currently ALL-DEFAULT seats — note the cross-vendor audit is silently
    OFF there today because reviewer and audit both default to codex):**
    `cd ~/Dev/certeus && printf 'reviewer_vendor = codex\nreviewer_model_tier1 = gpt-5.6-sol\nreviewer_model_tier2 = gpt-5.6-sol\naudit_vendor = claude\naudit_model = opus\nadvisor_model = fable\nadvisor_model_max = fable\n' >> .plinth/config`
  - Rationale: audit_vendor = claude everywhere (differs from BOTH the codex reviewer
    and the grok worker); advisor = fable per your direction (advise is rare,
    driver-initiated, non-blocking — low Fable spend).

<!-- Resolved 2026-07-24 (operator-delegated close-out): driver-shell migrations done in
     plinth/wren/certeus/anvil (shells byte-identical); seat lines applied — wren by the
     operator, certeus (2cb4577) and anvil (83614f4) delegated (Sonnet 5 reviewer, codex
     audit, opus/fable advisor); plinth main branch protection set via API with required
     contexts floor / secrets, floor / sast, floor / dependencies / osv-scan,
     floor / harness, checks / checks, scaffold; certeus cloud reviews confirmed flowing
     (merged PR #29 addresses a cloud P2 from #28; no open PRs pending); ci.yml gates
     repinned to v4.5.0 in the v4.5.1 release. Earlier resolved: this repo's migration
     (173fd80), charter ratification, seat change on main. -->
