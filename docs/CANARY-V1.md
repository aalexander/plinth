# Canary v1 — charter

**Status: DRAFT — under assigned-role panel review; not ratified.**
Successor to Plinth, built clean-sheet under the trusted-driver threat model,
harvesting Plinth modules verbatim. Plinth goes maintenance-frozen; downstream
repos migrate when Canary earns it.

Provenance: every design choice below cites measured evidence from the Plinth
v5.0→v6 sessions (2026-07-29/31), not taste. Key measurements: a 30-round review
loop that diverged (14→15 open blocking on unchanged code); ~5.07M input tokens
per round with the diff responsible for less than half (62-line diff = 2.73M,
6,000-line = 5.14M); a review gate silently broken for hours (vendor CLI schema
tightening, empty stderr) while canaries and adjudication carried quality; four
releases shipped mostly through escape hatches (residual binds, admin merges,
`cmp` proofs). When the fire escape carries more traffic than the stairs, the
building is the wrong shape.

---

## Mission

Speed of development without sacrificing security or shipping known-buggy
software. Speed comes from deleting process, not from skipping verification:
route every claim to the **cheapest verifier that can settle it**.

| Verifier | Cost | Use for |
|---|---|---|
| Computation (`cmp`, schema, types) | ~free, unarguable | identity, structure, invariants |
| Execution (tests, canaries, probes) | cheap, reproducible | behavior |
| Model judgment | expensive; unstable in absolute mode, decent in relative mode, excellent at hypothesis generation | finding bugs, comparing candidates, critique |
| Human judgment | scarcest, authoritative | irreversibles, value tradeoffs, security dismissals |

## Principles

1. **Probes gate; opinions advise.** A blocking finding must carry a
   reproducible failing probe; the probe joins the suite. A claim with no probe
   is advice, labeled as such. (Replaces demotion lexicons, severity floors,
   and ~200 lines of reviewer contract with one rule.)
2. **Gates are deterministic.** No model verdict is ever load-bearing. CI gates
   on the deterministic residue of model work: findings are data; "every
   finding has a disposition" is `jq`, not judgment.
3. **One primitive: disposition on the record.** Findings, requirement
   deletions, plan deviations, and dissents all resolve the same way —
   `fixed | dismissed | deferred` with a written reason, carried on the
   evidence ledger. You may dismiss anything; you may ignore nothing.
4. **Trusted driver, propagated.** No pinned installed copies (Canary runs
   from source — deletes the one-release instrument latency measured three
   times in one day), no tooling-edit-is-tampering class, receipts are an
   evidence ledger, not a forgery-resistance scheme. The residual hard key:
   **security findings can only be waved off by the human.**
5. **Fail loud (jidoka).** Silent skips, swallowed output, and error messages
   that guess are defects wherever they live. An error message that guesses is
   worse than one that says "unknown" — it spends the reader's time defending
   its guess (measured: the `prompt_bytes` capacity guess hid a schema
   rejection for hours).

---

## The plan loop

### Spec loop (product — what must be true)

1. **Requirements critique first** (Elon step 1, institutionalized). Every
   requirement carries an owner and a rationale; a requirement nobody owns is
   deleted by default. Before build, an assigned-role panel challenges the set:
   - **10th-man seat** (cross-family from the author): argues each
     architectural/irreversible/security requirement should be *deleted or
     inverted*; steelmans the world where it's wrong. Refutation framing, not
     critique framing.
   - **Pre-mortem seat** (context-blind): "this failed six months out — write
     the post-mortem," security failure modes explicitly in scope.
   - **Oracle seat** (strongest available model, non-binding): architecture
     and coherence.
   Panel seats are never averaged; **disagreement between seats marks the
   underspecified sections** — consensus is only absence of information.
   All dissent is adjudicated on the record. Track the rate of
   *dismissed-dissent-later-proven-right*: it measures whether the 10th man is
   heard or performed.
2. **Compile, don't prose.** Testable requirements compile into acceptance
   probes that join the suite (requirement → probe → result is the
   traceability matrix, derived free from the ledger). Untestable requirements
   are labeled guidance and can never gate.
3. **The spec is alive.** Dismissed findings, broken assumptions, and plan
   deviations feed a spec-change queue; the human ratifies spec changes. The
   human owns two artifacts: the spec and the gates. (Reuses the prior
   cross-vendor spec-evolution design: obligation-direction classification,
   control-plane split, core invariants.)

### Build loop (plan — how we get there)

- **Plans are data, not prose.** Slices:
  `{objective, files, checks_to_pass, budget, assumptions[]}`. Never parse
  with NLP what you can structure — the plan-prose classifiers produced an
  entire deferred-defect family.
- **Slices sized to ship**: ≤1 session, ≤~500-line diff. Train size is a
  planning output, not a hoped-for discipline (measured: diff growth
  manufactures findings and re-read cost).
- **Estimates cite the reference class.** `metrics.jsonl` records
  tokens/wall-clock/defects per slice; plans estimate from history, not
  optimism (Flyvbjerg outside view).
- **Course correction is a plan diff with a recorded reason** — the
  disposition primitive applied to the plan. No silent drift.
- **Gauntlet (opt-in) for wide solution spaces**: decompose → N parallel
  candidate builds on cheap fast models → blind tournament judged against
  compiled probes and real-world references → winner, grafting from
  runners-up. Relative judgment is stable where absolute judgment measurably
  is not. Skipped for narrow well-specified edits; prototyping runs this loop
  and the deterministic checks only.

### Stop table (mechanical, not vibes)

| Trigger | Action |
|---|---|
| Same check fails after 2 distinct fix attempts | Stop; replan or escalate — never grind |
| Slice budget exceeded | Checkpoint + replan; escalate if the plan is wrong |
| A listed assumption breaks | Replan; escalate if it invalidates a ratified decision |
| Auth, crypto, migrations, data deletion, public API, new deps | Human, always |
| Gate-semantics or trust-boundary change | Fresh context required (measured: five defects shipped writing gate code at hour N) |
| Probe-backed findings spike on fresh work | Next train starts with fresh context |
| Any agent or human files `[BLOCKING]` | That path stops (andon); other paths continue |

---

## The review pipeline (off the critical path)

Reviews are advisory hypothesis-generators; CI gates on their deterministic
residue.

| Lane | What runs | Trigger | Blocking? |
|---|---|---|---|
| Deterministic checks | tests, canaries, scanners, `cmp`/schema proofs, **adjudication-completeness** | every push | **Yes** |
| Advisory review | reviewer CLI headless, lean payload (spec by reference, vendored-identity exclusions, delta), emits `findings.json` + PR comment | once per PR (open/ready) + on-demand; concurrency-cancel; **never per push** | No |
| Async sweep | reviewer against merged `main`; findings → queue | cron / post-merge | No |

- The blocking check is **adjudication completeness**: every probe-backed
  finding (PR pass or async queue) has a disposition on the ledger. The merge
  never waits on an opinion; it waits on the driver having *answered*.
- Review CI jobs **fail loud on CLI errors** (exit-0 traps, empty stderr, and
  schema rejections are all measured vendor behaviors).
- Risk tier decides whether a model pass runs at all: Tier-0/1 diffs pay
  cents (scanners only).

## Security floor (phase-independent)

| Layer | What | When | Gate |
|---|---|---|---|
| Scanners (secrets, SAST, OSV) | deterministic | every PR, every tier | blocking |
| Security-specialist pass (different family than the builder) | one focused call, security severities only | diff touches triggered surface: auth, crypto, secrets/tokens, session, parsers of untrusted input, dep manifests, ship path (list in-repo) | blocking by adjudication |
| Deep sweep + fuzz/property probes on trust boundaries | whole-repo | weekly + every release tag | findings → queue |

- **Prototyping never skips the trigger list** — a prototype touching auth
  gets the pass. "Fast because it's early" is how prototype auth ships.
- **Unreadable classifier → run the pass** (fail toward security).
- **Asymmetric dismissal**: dismissing a security finding auto-opens
  `[BLOCKING]` NEEDS-HUMAN. The human is the only key for security claims.

## Self-tuning (adopted mechanisms)

| Mechanism | Wiring |
|---|---|
| **Mutation testing** (anti-hollow-probe) | Periodic job mutates diff-touched lines; the probe suite must fail. Probes that survive mutation are theater and get flagged. (The single most recurrent defect class in the Plinth sessions, industrialized away.) |
| **Self-pruning checks** (Tricorder) | Per-check dismissal rates computed from ledger; >~50% dismissed over trailing window → auto-proposal to delete the check. Elon step 2, automated. |
| **Error budget** (SRE) | Escaped-defect budget (probe-backed findings against merged main + human bug reports). Within budget → advisory mode everywhere; blown → review flips to blocking-by-adjudication until recovered. Replaces declared build/harden phases with a measured dial. |

---

## Driver contract (one page — this is the whole thing)

1. **Challenge requirements first.** Every requirement has an owner and a
   reason. Requirements compile to probes; what cannot compile is guidance and
   cannot gate. Argue with dumb requirements before building — deletion is a
   disposition, not a failure.
2. **Delete before you fix.** Before debugging anything, ask whether the code
   survives the next architecture. A defect in deleted code is a free pass.
3. **Probes gate; opinions advise.** Deterministic checks and failing probes
   block. Model judgment — including yours — is advice. Every blocking claim
   carries a reproducible probe, and the probe joins the suite.
4. **Judge on the record.** Every finding, deviation, dissent, and deleted
   requirement gets `fixed | dismissed | deferred` with a written reason. You
   may dismiss anything except a security finding (that opens `[BLOCKING]`
   for the human). You may ignore nothing.
5. **Stop when the table says stop.** Two failed fixes → replan. Budget blown
   → checkpoint + replan. Assumption broken → replan; escalate if it breaks a
   ratified decision. Irreversibles and gate-semantics changes → human, fresh
   context.
6. **Ship small and often.** Slices ≤1 session, ≤~500 lines. Main stays
   shippable. Evidence over narrative: runner output, diffs, exit codes —
   never "should pass."
7. **Fail loud.** No silent skips, no swallowed output, no error messages
   that guess. A tool that hides its failure is a defect wherever it lives.

## Harvest list (from Plinth, verbatim with their canaries)

`.claude/` guard hooks (accident prevention: destructive commands, protected
paths) · canary suites + the drive-production-code philosophy ·
`plinth adjudicate` (mint-path redesigned) · receipt/notes plumbing
(as evidence ledger; bound to the reviewed finding set — the one forgery
boundary kept) · risk classifier (narrowed: evidence-requirements routing +
security triggers) · `lane-guard` · `advise` · lean-payload machinery
(spec-by-reference, vendored-identity exclusion) · NEEDS-HUMAN queue ·
checkpoint/handoff.

## v1 slices

```json
{"slices":[
 {"id":"c1","objective":"repo scaffold + one-page contract + metrics.jsonl + stop table wired into driver docs","files":["contract.md","bin/canary"],"checks":["contract fits one page","metrics ledger appends"],"budget":"1 session","assumptions":["trusted-driver model ratified"]},
 {"id":"c2","objective":"plan compiler: requirements -> probes; slices as data; plan-diff dispositions","files":["bin/canary","plan.schema.json"],"checks":["untestable req cannot gate","plan diff requires reason"],"budget":"1 session","assumptions":["spec-evolution design holds"]},
 {"id":"c3","objective":"evidence ledger + adjudication-completeness CI gate (deterministic)","files":["bin/canary",".github/"],"checks":["ledger bound to finding set","completeness check is pure jq"],"budget":"1 session","assumptions":["receipt notes plumbing harvests cleanly"]},
 {"id":"c4","objective":"advisory review lane (once-per-PR, lean payload, fail-loud) + async sweep skeleton","files":[".github/","bin/canary"],"checks":["CLI error fails the job loudly","never triggers per push"],"budget":"1 session","assumptions":["headless vendor CLIs stable"]},
 {"id":"c5","objective":"security floor: scanners + trigger list + specialist pass + asymmetric dismissal","files":[".github/","triggers.json"],"checks":["prototype touching auth gets the pass","security dismissal opens BLOCKING"],"budget":"1 session","assumptions":["cross-family seat available"]},
 {"id":"c6","objective":"panel machinery: 10th-man/pre-mortem/oracle roles + disagreement locator","files":["bin/canary"],"checks":["dissent adjudicated on record","disagreements marked on plan"],"budget":"1 session","assumptions":[]},
 {"id":"c7","objective":"self-tuning: mutation-testing job, dismissal-rate pruning, error budget","files":[".github/","bin/canary"],"checks":["surviving mutant flags probe","pruning proposal generated from ledger"],"budget":"2 sessions","assumptions":["enough ledger history to compute rates"]}
]}
```

## Non-goals (v1)

Multi-repo orchestration · dashboards · malicious-driver hardening ·
per-vendor hook porting · gauntlet as default (opt-in only) · migrating
downstream repos before Canary has shipped itself with its own loop.

## Panel record

*To be filled by adjudication of the assigned-role panel review (10th-man:
codex; pre-mortem: context-blind subagent; oracle: `advise --impactful`).
Every finding will be dispositioned here with a reason. Ratification by the
human follows adjudication.*
