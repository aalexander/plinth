# Blocked on you

- [ ] **Ratify review-loop convergence rules** (paste into `.plinth/AGENTS-project.md` — your
  file; the driver must not edit reviewer instructions mid-loop). This is the structural fix
  for the 10-round escalation treadmill on `chore/instrument-v4.5.0` (rounds 1–4 found real
  bugs; 7–10 demanded adversarial-local-attacker hardening on a trusted-env CLI). Draft:
  ```
  ## Review-loop convergence (ratified 2026-07-__)
  - Trust boundary: driver, reviewer, and operator are TRUSTED; local-machine
    adversaries are OUT OF SCOPE. Flag realistic failure (fail-open logic, wrong
    behavior, data loss) — not local-attacker hardening (symlink races on repo
    temps, NUL-injected local policy files, per-stage mutation shims) unless the
    code crosses a real trust boundary (network input, PR-supplied content).
  - Round 1 is EXHAUSTIVE: report every finding AND every finding-class you can
    see, enumerating all siblings of a class in one finding, so fixes batch.
  - Later rounds verify fixes: review (a) whether prior findings are resolved and
    (b) defects INTRODUCED by the fix diffs. Do not raise a new finding class
    against lines unchanged since the round that first reviewed them.
  ```
- [ ] **[BLOCKING] Complete this repo's one-time driver-shell migration** (v4.4 design; the
  guard rightly blocks the driver from `rm CLAUDE.md`, so this last step is yours). The
  project notes are already migrated into `.plinth/DRIVER-project.md`; run exactly:
  `cd ~/Dev/plinth && rm CLAUDE.md && plinth update ~/Dev/plinth && git add -A && git commit -m "chore: regenerate driver shell (one-time v4.4 migration)"`
  Until then CLAUDE.md ≠ the driver shell, the v4.5.0-pinned CI floor fails on it, and the
  `chore/instrument-v4.5.0` branch review keeps a major open on exactly this.
- [ ] Same one-time driver-shell migration in **certeus** and **anvil** (their v4.5.0
  updates printed the same NOTE; each still has a custom CLAUDE.md). Their next driver
  session can populate `.plinth/DRIVER-project.md` from the CLAUDE.md notes first —
  only the `rm CLAUDE.md && plinth update <repo> && commit` step needs you.
- [ ] Add the v4 seat lines to `.plinth/config` (guard-protected, so set-once by you) in
  **all four repos** — plinth, wren, certeus, anvil all lack them (update preserves
  existing configs; only fresh init writes them):
  `audit_vendor = claude`, `audit_model = opus`, `advisor_model = opus`,
  `advisor_model_max = fable`; optionally `reviewer_model_tier1/2 = gpt-5.6` once
  `codex -m gpt-5.6` works on your account (Codex CLI >= 0.144.0 — an active line on an
  ineligible account makes the reviewer fail loud by design). Without `audit_vendor`,
  Tier-2 approvals get NO cross-vendor second opinion in any of the four.
- [x] After tagging **v4.5.0**, bump this repo's own required gates in `.github/workflows/ci.yml`
  (`floor` + `checks`, now pinned `@5a39ab…` / v4.4.0) to the v4.5.0 SHA — the required gate
  intentionally trails the latest tag by one release for immutability, so v4.5.0's own floor
  changes only become the *required* gate once repinned post-tag. The `floor-current`/`checks-current`
  twins already exercise them on every PR. (The pin was moved v4.1.9 -> v4.4.0 in-branch so the
  required gate carries the v4.2–v4.4 floor/review hardening now, not only after v4.5.0 tags.)
  *(DONE 2026-07-24 on `chore/instrument-v4.5.0`: repinned to `3431797` / v4.5.0 as part of the
  instrument refresh — the update's stale-ref check emitted the exact sed.)*
- [ ] Set branch protection to require the exact job-name contexts (GitHub does NOT prefix with
  the workflow name): `floor / secrets`, `floor / sast`, `floor / dependencies / osv-scan`,
  `floor / harness`, and `checks / checks` (or `checks` if you use a direct checks job). The
  preflight matches these; confirm against the first PR's checks list and adjust only if your
  ci.yml renamed the `floor`/`checks` caller jobs.
- [ ] THIS repo only (plinth-canary.yml): also require the `scaffold` context in branch protection.
  The regression suite that gates Plinth's own behavior (lane-guard, hookprobe, edit_file, stale-ref,
  preflight) lives in that job; without it required, those tests are advisory and a regression could
  merge. (Downstream projects don't have plinth-canary.yml — this item is specific to the Plinth repo.)
- [ ] Certeus: confirm the Codex cloud CI reviews are now being pulled and their findings addressed
  (they were previously not fetched). Re-run the review loop there if any were missed.
