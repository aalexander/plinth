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
  Full SPEC acceptance still waits on harness PR #1.

- [x] **certeus seats+instrument** — merged #36 (instrument 4.8.1 + seats on main).
  Follow-up: repin receipt @ v4.8.0 once convenient (landed with floor@v4.8.0, receipt
  left at main's v4.7.1 pin for base-pin during bootstrap).

- [x] **wren instrument** — merged #19 (instrument 4.8.1 + floor/checks/receipt@v4.8.0).
  Admin merge for receipt base-pin chicken-and-egg; protection restored with
  `receipt / verify` + `strict:true`.

- [ ] **geneus** — local only (no remote). Instrument 4.8.1 + advisor=`fable` applied
  on `feat/phase-0-spec-ratification`. Create GitHub remote when ready.

- [ ] **certeus receipt trail-pin follow-up** — optional small PR to set
  `plinth-receipt.yml@29df9c14… # v4.8.0` now that main has the newer floor pin.
