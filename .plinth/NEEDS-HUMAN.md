# Blocked on you

- [ ] **Auto mode residual (2026-07-26):** Product **v4.8.0**, tags **v4.7.2**/**v4.8.0**
  pushed, GitHub releases published. Close-out trails floor/checks pins to **v4.7.2**.
  Installed instrument is still **4.6.0**. **Order (do not skip):**
  1. Land instrument-refresh PR → `.plinth-version` **≥ 4.7** (preferably 4.8.0).
  2. Wire the `receipt` job in `ci.yml` (pin `plinth-receipt.yml` to the release you run).
  3. Require `receipt / verify` **and** `"strict":true` in branch protection.
  Do not require the context before step 1 (pre-v4.7 mints nothing; fails closed).
  Caller-control bound: a PR can replace the receipt caller with a green spoof of the
  same context name (ci.yml HONEST BOUND / MANUAL).
  ```
  gh api -X PATCH repos/aalexander/plinth/branches/main/protection/required_status_checks --input -
  ```
  body like
  `{"strict":true,"contexts":["floor / secrets","floor / sast","floor / dependencies / osv-scan","floor / harness","checks / checks","receipt / verify"]}`
  Notes: `git push origin HEAD refs/notes/plinth-receipts` (never force-push that ref).

- [ ] **Instrument refresh to v4.8.0** (separate release-labeled PR): materialize tagged
  shared payload; `.plinth-version` → 4.8.0; then wire receipt job (step 2 above).

- [ ] **#43** — Write-tool implementer prompts regressed after #41 overwrote #37.
  Restore non-shell Write-tool flow; keep #41 delegation-receipt wiring; add
  mutation-sensitive canary for `lane-guard.sh delegation`.

- [ ] **Tier-2 confirmation process window (product):** non-fresh Tier-2 may write
  `APPROVED` before clean-slate confirmation finishes; ship gates that only read the
  verdict field can accept that intermediate state. Fix: persist UNBOUND/pending until
  confirmation succeeds; canary the failed-confirmation state.

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
  - **anvil:**
    `cd ~/Dev/anvil && sed -i '' -e 's/^reviewer_vendor = claude/reviewer_vendor = codex/' -e 's/^reviewer_model_tier1 = sonnet/reviewer_model_tier1 = gpt-5.6-sol/' -e 's/^reviewer_model_tier2 = sonnet/reviewer_model_tier2 = gpt-5.6-sol/' -e 's/^audit_vendor = codex/audit_vendor = claude/' -e 's/^advisor_model = opus/advisor_model = fable/' .plinth/config && printf 'audit_model = opus\n' >> .plinth/config`
  - **certeus (currently ALL-DEFAULT seats — note the cross-vendor audit is silently
    OFF there today because reviewer and audit both default to codex):**
    `cd ~/Dev/certeus && printf 'reviewer_vendor = codex\nreviewer_model_tier1 = gpt-5.6-sol\nreviewer_model_tier2 = gpt-5.6-sol\naudit_vendor = claude\naudit_model = opus\nadvisor_model = fable\nadvisor_model_max = fable\n' >> .plinth/config`
  - Rationale: audit_vendor = claude everywhere (differs from BOTH the codex reviewer
    and the grok worker); advisor = fable per your direction.

- [ ] **wren has no git remote** — its `chore/instrument-v4.6.0` branch is staged and
  APPROVED at HEAD but cannot become a PR until the repo exists on GitHub.
  `cd ~/Dev/wren && gh repo create wren --private --source=. --remote=origin && git push -u origin --all`

<!-- Resolved 2026-07-24 (operator-delegated close-out): driver-shell migrations done in
     plinth/wren/certeus/anvil; seat lines applied; plinth main branch protection set with
     floor/checks contexts; earlier migration and charter ratification. -->
