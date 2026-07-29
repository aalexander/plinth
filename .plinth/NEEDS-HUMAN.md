# Blocked on you

- [x] **Auto mode residual (2026-07-27)** — Instrument **4.8.1** + receipt job
  wired (floor/checks/receipt@**v4.8.0** trail pin). Tags **v4.7.2**/**v4.8.0**/**v4.8.1**.
  Branch protection on `main` requires floor + checks + scaffold + `receipt / verify`
  with `"strict":true`. Caller-control bound still applies (ci.yml HONEST BOUND / MANUAL).

- [x] **Instrument refresh to v4.8.1** — #46.

- [x] **#43 / Tier-2 confirmation window** — v4.8.1 product (#45).

- [x] **Seat topology on plinth** — operator seats live.

- [x] **wren git remote** — `origin` = `aalexander/wren`.

- [x] **anvil seats+instrument** — merged #6 (instrument 4.8.1 + seats on scaffold main).

- [x] **certeus seats+instrument** — merged #36; receipt trail-pin merged #37
  (floor + receipt both @ v4.8.0).

- [x] **wren instrument** — merged #19; protection has `receipt / verify` + `strict:true`.

- [x] **geneus remote** — `origin` = `aalexander/geneus` (private); branches pushed.

- [x] **anvil harness** — not a plinth human gate. Scaffold main is instrumented
  (seats + receipt @ v4.8.0 via anvil#6). Full SPEC acceptance is **anvil product work**
  on open [anvil#1](https://github.com/aalexander/anvil/pull/1) (`build/harness-v14`),
  not an operator credential/config action for this repo. Track progress on that PR.

- [x] **plinth#51 / UPSTREAM fail-open class (2026-07-29)** — v5.0.3 paid #11/#12/#13/#15/#5/#31/#29/#14/#17
  (+ #49 in 5.0.2). Remaining optional: #2 SIGPIPE, #20 long verify, #21 shell migration notes,
  #32 lane honesty bound. Residual canary-depth still in RESIDUAL-TRIAGE.
