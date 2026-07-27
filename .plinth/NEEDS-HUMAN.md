# Blocked on you

- ~~**Auto mode residual (2026-07-27)**~~ — **DONE.** Instrument **4.8.1** + receipt job
  wired (floor/checks/receipt@**v4.8.0** trail pin). Tags **v4.7.2**/**v4.8.0**/**v4.8.1**.
  Branch protection on `main` requires
  `floor / secrets`, `floor / sast`, `floor / dependencies / osv-scan`, `floor / harness`,
  `checks / checks`, `scaffold`, `receipt / verify` with `"strict":true`.
  Caller-control bound still applies (ci.yml HONEST BOUND / MANUAL).
  Notes: `git push origin HEAD refs/notes/plinth-receipts` (never force-push).

- ~~**Instrument refresh to v4.8.1**~~ — **DONE** (#46).

- ~~**#43 / Tier-2 confirmation window**~~ — **DONE in v4.8.1 product** (#45): Write-tool
  recombine + UNBOUND-before-confirmation + delegation canary.

- ~~**Seat topology (2026-07-24 direction: Opus driver / grok worker / gpt-5.6-sol
  reviewer / Fable advisor / Claude Opus audit)**~~ — **plinth DONE.** Sibling status:
  - **wren** — seats already on `main` (`gpt-5.6-sol` / fable / claude opus audit).
  - **certeus** — seats on feature branches only; land seats+instrument on `main` via PR.
  - **anvil** — seats on `chore/seat-topology-swap` (#3, polluted base / red CI); land
    clean seats+instrument from `main` via PR.
  - **geneus** — local seats present; advisor peer still `opus` (target `fable`); no remote.

- ~~**wren has no git remote**~~ — **DONE** (remote `origin` = `aalexander/wren`).

<!-- Resolved 2026-07-24 (operator-delegated close-out): driver-shell migrations done in
     plinth/wren/certeus/anvil; seat lines applied; plinth main branch protection set with
     floor/checks contexts; earlier migration and charter ratification. -->
