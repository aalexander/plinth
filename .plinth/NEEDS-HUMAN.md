# Blocked on you

- [ ] Same one-time driver-shell migration in **certeus** and **anvil** as the one you ran
  here (their v4.5.0 updates printed the same NOTE; each still has a custom CLAUDE.md).
  Their next driver session can move the '## Project-specific notes' into
  `.plinth/DRIVER-project.md` first — only the final step needs you, with **plinth in the
  commit subject** (the tamper label rule):
  `cd <repo> && rm CLAUDE.md && plinth update . && git add -A && git commit -m "chore: regenerate plinth driver shell (one-time v4.4 migration via plinth update)"`
- [ ] Add the seat lines to `.plinth/config` (guard-protected, so set-once by you) in
  **all four repos** — plinth, wren, certeus, anvil (update preserves existing configs;
  only fresh init writes them). Per your 2026-07-24 decision the REVIEWER is Sonnet 5:
  ```
  reviewer_vendor = claude
  reviewer_model_tier1 = sonnet
  reviewer_model_tier2 = sonnet
  advisor_model = opus
  advisor_model_max = fable
  ```
  Add `audit_vendor = grok`: with codex OUT OF CREDITS (2026-07-24), the unset default
  (codex) would fail non-fatally and Tier-2 approvals would get no working second
  opinion; grok is signed in, subscription-billed, and differs from the claude reviewer.
  (Do NOT use `audit_vendor = claude` — with a claude reviewer that turns the audit OFF.)
  One-liner per repo, run from each repo root:
  `printf 'reviewer_vendor = claude\nreviewer_model_tier1 = sonnet\nreviewer_model_tier2 = sonnet\naudit_vendor = grok\nadvisor_model = opus\nadvisor_model_max = fable\n' >> .plinth/config`
- [ ] Set branch protection to require the exact job-name contexts (GitHub does NOT prefix
  with the workflow name): `floor / secrets`, `floor / sast`,
  `floor / dependencies / osv-scan`, `floor / harness`, and `checks / checks` (or
  `checks` if you use a direct checks job). The preflight matches these; confirm against
  the first PR's checks list and adjust only if your ci.yml renamed the `floor`/`checks`
  caller jobs.
- [ ] THIS repo only (plinth-canary.yml): also require the `scaffold` context in branch
  protection. The regression suite that gates Plinth's own behavior (lane-guard,
  hookprobe, edit_file, stale-ref, preflight) lives in that job; without it required,
  those tests are advisory and a regression could merge. (Downstream projects don't have
  plinth-canary.yml — this item is specific to the Plinth repo.)
- [ ] Certeus: confirm the Codex cloud CI reviews are now being pulled and their findings
  addressed (they were previously not fetched). Re-run the review loop there if any were
  missed.

<!-- Resolved 2026-07-24 and removed: this repo's driver-shell migration (48e7222,
     reworded 173fd80); review-convergence charter ratified into AGENTS-project.md
     (660b902); ci.yml required gates repinned v4.4.0 -> v4.5.0 (697c1e2). -->
