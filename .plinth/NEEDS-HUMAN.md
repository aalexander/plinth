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
    loud on your account, so wren's review loop is BRICKED until repinned.
    IMPORTANT: the seat lines live ONLY on the `build/async-boot-v2` branch — `main`
    has no seat lines at all (it falls back to the codex default `gpt-5.6-sol`, which
    works). So the repin must be run WITH THAT BRANCH CHECKED OUT, or it silently does
    nothing. Re-verified 2026-07-25: wren is currently on `build/async-boot-v2` and
    still pinned `gpt-5.6`; it also still has NO git remote (`gh repo create` is a
    separate open item below):**
    `cd ~/Dev/wren && git checkout build/async-boot-v2 && sed -i '' -e 's/^reviewer_model_tier1 = gpt-5.6$/reviewer_model_tier1 = gpt-5.6-sol/' -e 's/^reviewer_model_tier2 = gpt-5.6$/reviewer_model_tier2 = gpt-5.6-sol/' -e 's/^advisor_model = opus$/advisor_model = fable/' .plinth/config && grep -E '^(reviewer_model|advisor_model)' .plinth/config`
  - ~~**plinth**~~ — **DONE (2026-07-25, applied by the operator).** `.plinth/config` now
    reads reviewer_vendor = codex, reviewer_model_tier1/tier2 = gpt-5.6-sol,
    audit_vendor = claude, audit_model = opus, advisor_model/advisor_model_max = fable.
    It rides in the v4.7.0 PR. NOTE: seats are read from the BASE branch, so this takes
    effect for branches cut AFTER that merge — the v4.7 branch's own review ran under
    main's previous claude/sonnet seat.
  - **anvil:**
    `cd ~/Dev/anvil && sed -i '' -e 's/^reviewer_vendor = claude/reviewer_vendor = codex/' -e 's/^reviewer_model_tier1 = sonnet/reviewer_model_tier1 = gpt-5.6-sol/' -e 's/^reviewer_model_tier2 = sonnet/reviewer_model_tier2 = gpt-5.6-sol/' -e 's/^audit_vendor = codex/audit_vendor = claude/' -e 's/^advisor_model = opus/advisor_model = fable/' .plinth/config && printf 'audit_model = opus\n' >> .plinth/config`
  - **certeus (currently ALL-DEFAULT seats — note the cross-vendor audit is silently
    OFF there today because reviewer and audit both default to codex):**
    `cd ~/Dev/certeus && printf 'reviewer_vendor = codex\nreviewer_model_tier1 = gpt-5.6-sol\nreviewer_model_tier2 = gpt-5.6-sol\naudit_vendor = claude\naudit_model = opus\nadvisor_model = fable\nadvisor_model_max = fable\n' >> .plinth/config`
  - Rationale: audit_vendor = claude everywhere (differs from BOTH the codex reviewer
    and the grok worker); advisor = fable per your direction (advise is rare,
    driver-initiated, non-blocking — low Fable spend).

- [ ] **wren has no git remote** — its `chore/instrument-v4.6.0` branch is staged and
  APPROVED at HEAD but cannot become a PR (and so cannot be merged through the gates)
  until the repo exists on GitHub. Re-verified 2026-07-25: `git remote -v` in
  `~/Dev/wren` is still empty.
  `cd ~/Dev/wren && gh repo create wren --private --source=. --remote=origin && git push -u origin --all`

- [ ] **Turn ON the v4.7 receipt gate (per repo).** v4.7 ships the server-verifiable
  APPROVED-at-HEAD receipt check, but SHIPPING IT IS NOT ENABLING IT: it gates only
  where the `receipt` job is wired into that repo's `ci.yml` AND the `receipt / verify`
  context is added to branch protection's required checks. `ci.yml` is per-project and
  is NEVER rewritten by `plinth update` — for an EXISTING project you add the job by
  hand (copy it from `templates/.github/workflows/ci.yml`, and pin its `uses:` ref to
  this release's commit SHA; only a freshly `plinth init`-ed ci.yml is pinned for you).
  Until then the review verdict still has no server-side verifier and a non-Claude or
  delegated driver stays contract-bound. Do this only for repos whose reviewed
  branches run a v4.7+ instrument (older instruments mint no receipt, so the check
  fails closed — correct, but it would block every PR):
  `gh api -X PATCH repos/aalexander/<repo>/branches/main/protection/required_status_checks --input -` with the
  existing contexts plus `receipt / verify` — or add it in the branch-protection UI.
  Also push the notes ref with the branch: `git push origin HEAD refs/notes/plinth-receipts`.

<!-- Resolved 2026-07-24 (operator-delegated close-out): driver-shell migrations done in
     plinth/wren/certeus/anvil (shells byte-identical); seat lines applied — wren by the
     operator, certeus (2cb4577) and anvil (83614f4) delegated (Sonnet 5 reviewer, codex
     audit, opus/fable advisor); plinth main branch protection set via API with required
     contexts floor / secrets, floor / sast, floor / dependencies / osv-scan,
     floor / harness, checks / checks, scaffold; certeus cloud reviews confirmed flowing
     (merged PR #29 addresses a cloud P2 from #28; no open PRs pending); ci.yml gates
     repinned to v4.5.0 in the v4.5.1 release. Earlier resolved: this repo's migration
     (173fd80), charter ratification, seat change on main. -->
