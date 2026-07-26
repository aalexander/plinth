# Blocked on you

- [ ] **Auto mode residual (2026-07-26):** Product **v4.8.0**, tags **v4.7.2**/**v4.8.0**
  pushed, GitHub releases published. `ci.yml` wires floor/checks@**v4.7.2** and
  **`receipt`**@**v4.7.2**. Installed instrument is still **4.6.0** (trail) until a
  labeled instrument-refresh PR — do not require `receipt / verify` until that lands
  (pre-v4.7 instruments mint no receipt; the check fails closed).
  **After instrument ≥ 4.7 is on the base:** require status check `receipt / verify`
  among required contexts **and** set `"strict":true`. Without strict, a green receipt
  can describe a base that has since advanced. Caller-control bound: a PR can replace
  the receipt caller with a green spoof of the same context name (ci.yml HONEST BOUND).
  ```
  gh api -X PATCH repos/aalexander/plinth/branches/main/protection/required_status_checks --input -
  ```
  body like
  `{"strict":true,"contexts":["floor / secrets","floor / sast","floor / dependencies / osv-scan","floor / harness","checks / checks","receipt / verify"]}`
  (keep whatever contexts you already require; always include `receipt / verify` and
  `strict:true`) — or via the branch-protection UI.
  Notes push: `git push origin HEAD refs/notes/plinth-receipts` (never force-push that ref).

- [ ] **Instrument refresh to v4.8.0** (separate PR, release-labeled):
  `plinth update` / copy tagged shared payload; `.plinth-version` → 4.8.0. Prerequisite
  for receipt minting and for requiring the receipt context.

- [ ] **#43** — Write-tool implementer prompts regressed after #41 overwrote #37.
  Both implementers again use shell `SPEC_EOF` heredocs; restore the non-shell Write-tool
  flow from #37 while keeping the #41 delegation-receipt wiring. Also add a mutation-
  sensitive canary for `lane-guard.sh delegation`.

- [ ] **Tier-2 confirmation process window (product):** non-fresh Tier-2 approval may
  leave `verdict.json` as APPROVED before the clean-slate confirmation finishes; ship
  gates that only check the field can accept that intermediate state. Fix: persist
  pending/UNBOUND until confirmation succeeds; canary the failed-confirmation state.
  MANUAL documents the bound.

- [ ] **UPSTREAM residuals:** `_ship_bare` / `GH_REPO` redirect on argument-less
  `gh pr merge`; guard comment prose for strict+caller-control (if not already in tag).

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

<!-- Resolved 2026-07-24 (operator-delegated close-out): driver-shell migrations done in
     plinth/wren/certeus/anvil (shells byte-identical); seat lines applied — wren by the
     operator, certeus (2cb4577) and anvil (83614f4) delegated (Sonnet 5 reviewer, codex
     audit, opus/fable advisor); plinth main branch protection set via API with required
     contexts floor / secrets, floor / sast, floor / dependencies / osv-scan,
     floor / harness, checks / checks, scaffold; certeus cloud reviews confirmed flowing
     (merged PR #29 addresses a cloud P2 from #28; no open PRs pending); ci.yml gates
     repinned to v4.5.0 in the v4.5.1 release. Earlier resolved: this repo's migration
     (173fd80), charter ratification, seat change on main. -->
