# Blocked on you

- [x] **Auto mode residual (2026-07-27)** — Instrument **4.8.1** + receipt job
  wired (floor/checks/receipt@**v4.8.0** trail pin). Tags **v4.7.2**/**v4.8.0**/**v4.8.1**.
  Branch protection on `main` requires
  `floor / secrets`, `floor / sast`, `floor / dependencies / osv-scan`, `floor / harness`,
  `checks / checks`, `scaffold`, `receipt / verify` with `"strict":true`.
  Caller-control bound still applies (ci.yml HONEST BOUND / MANUAL).
  Notes: `git push origin HEAD refs/notes/plinth-receipts` (never force-push).

- [x] **Instrument refresh to v4.8.1** — #46.

- [x] **#43 / Tier-2 confirmation window** — v4.8.1 product (#45): Write-tool
  recombine + UNBOUND-before-confirmation + delegation canary.

- [x] **Seat topology on plinth** (2026-07-24 direction: Opus driver / grok worker /
  gpt-5.6-sol reviewer / Fable advisor / Claude Opus audit).

- [x] **wren git remote** — `origin` = `aalexander/wren`.

- [ ] **anvil** — land clean seats+instrument from `main` via PR
  (https://github.com/aalexander/anvil/pull/4). #3 closed as polluted base.

- [ ] **certeus** — land seats+instrument on `main` via PR
  (https://github.com/aalexander/certeus/pull/36). Seats were only on feature branches.

- [ ] **wren** — land instrument refresh 4.7.1→4.8.1 via PR
  (https://github.com/aalexander/wren/pull/19). Seats already correct on `main`.
  Branch protection now requires `receipt / verify` + `strict:true`.

- [ ] **geneus** — local only (no remote). Instrument 4.8.1 + advisor=`fable` applied
  on `feat/phase-0-spec-ratification`. Create GitHub remote when ready.

<!-- Resolved 2026-07-24 (operator-delegated close-out): driver-shell migrations done in
     plinth/wren/certeus/anvil; seat lines applied; plinth main branch protection set with
     floor/checks contexts; earlier migration and charter ratification. -->
