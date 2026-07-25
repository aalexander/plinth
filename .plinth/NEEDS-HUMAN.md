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

- [ ] **Turn ON the v4.7 receipt gate (per repo) — TWO steps, IN THIS ORDER.** v4.7 ships
  the server-verifiable APPROVED-at-HEAD receipt check, but SHIPPING IT IS NOT ENABLING
  IT. I deliberately did NOT do this for plinth itself: enabling changes what can merge
  in every future PR, so it is yours to switch on after you have seen a receipt mint for
  real. Prerequisite: the repo's reviewed branches must run a v4.7+ instrument (an older
  one mints nothing, so the check fails closed — correct, but it would block every PR).
  plinth itself is at 4.7.2 as of this branch (VERSION and .plinth-version agree).
  The v4.7.0 SHA in step 1 below is deliberate and unchanged: that is the commit whose
  reusable workflow you pin, not the instrument version you run.

  **Step 1 — wire the job, and MERGE that to the base branch first.** `ci.yml` is
  per-project and never rewritten by `plinth update`, so add the `receipt:` job by hand
  (copy from `templates/.github/workflows/ci.yml`) and pin its `uses:` ref to the release
  SHA — for v4.7.0 that is `ed8d75b2b90685eddbebb24bd11c2770ed489341`. **Pin the release you are RUNNING, not v4.7.0.** That SHA delivers v4.7.0's
  verifier, which predates this release's live base-SHA check, notes-probe error
  classification, strict-enablement diagnostic and repo-mismatch redaction — so a
  v4.7.2 rollout that keeps it silently ships the older verifier. After tagging,
  take the SHA with `git rev-parse v<version>` and pin that. Merge that PR
  before doing step 2.

  Why the order is not optional: the check reads the receipt job's pin from the BASE
  branch and refuses any PR-supplied pin that differs. That is what stops a PR from
  repointing the verifier at a fork that always passes. A base branch with no receipt job
  has no operator-owned pin to anchor against, so the check fails closed and says so. If
  you require the context BEFORE the wiring is on the base, every PR blocks.

  Expect ONE red `receipt / verify` on the wiring PR itself — its base has no receipt job
  yet, so it correctly fails closed. That is the bootstrap, not a defect; the context is
  not required at that point, so it does not block the merge.

  **Step 2 — require the context with strict up-to-date**, once step 1 is on the
  base. Include `receipt / verify` among the required contexts AND set
  `"strict":true` ("Require branches to be up to date before merging"). The
  receipt job verifies the subject **as of job execution**; after it exits green
  the base can still advance while the PR head and the successful status stay
  unchanged — only `strict:true` forces re-evaluation before merge. A job cannot
  invalidate its own status after it exits.
  `gh api -X PATCH repos/aalexander/<repo>/branches/main/protection/required_status_checks --input -`
  with body like
  `{"strict":true,"contexts":["floor / secrets","floor / sast","floor / dependencies / osv-scan","floor / harness","checks / checks","receipt / verify"]}`
  (keep whatever contexts you already require; always include `receipt / verify`
  and `strict:true`) — or via the branch-protection UI with both the context and
  "Require branches to be up to date" ticked.

  **Then, every branch:** push the notes ref alongside it, or the check fails closed with
  nothing to verify: `git push origin HEAD refs/notes/plinth-receipts`. Never force-push
  that ref. On a non-fast-forward rejection, recover with these four commands, in order —
  `git notes merge` needs the side ref NAMED (bare `git notes --ref=X merge` exits
  "must specify a notes ref to merge"), which the earlier wording here got wrong. Pass
  the SAME base you reviewed against: the re-run re-mints for free only when the stored
  verdict's base matches, and bare `./.plinth/review.sh` means `main`:
  ```
  git fetch origin +refs/notes/plinth-receipts:refs/notes/remote-receipts
  git notes --ref=plinth-receipts merge -s theirs refs/notes/remote-receipts
  ./.plinth/review.sh <base>   # SAME base you reviewed against (defaults to main);
                            # re-mints YOUR receipt at HEAD, no paid round
  git push origin refs/notes/plinth-receipts
  ```
  NOT `-s cat_sort_uniq`: it CONCATENATES two differing receipts for the same commit, so
  the note holds two JSON objects and every field read in receipt-verify.sh returns two
  lines — failing a legitimately approved commit.

<!-- Resolved 2026-07-24 (operator-delegated close-out): driver-shell migrations done in
     plinth/wren/certeus/anvil (shells byte-identical); seat lines applied — wren by the
     operator, certeus (2cb4577) and anvil (83614f4) delegated (Sonnet 5 reviewer, codex
     audit, opus/fable advisor); plinth main branch protection set via API with required
     contexts floor / secrets, floor / sast, floor / dependencies / osv-scan,
     floor / harness, checks / checks, scaffold; certeus cloud reviews confirmed flowing
     (merged PR #29 addresses a cloud P2 from #28; no open PRs pending); ci.yml gates
     repinned to v4.5.0 in the v4.5.1 release. Earlier resolved: this repo's migration
     (173fd80), charter ratification, seat change on main. -->
