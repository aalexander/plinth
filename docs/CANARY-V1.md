# Canary v1 — charter

**Status: DRAFT, panel-amended (round 1) — sections A–D redesigned; requires a second
panel pass on those sections before ratification.**
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

---

## Defining "security" — anchored to public taxonomy, not to our vocabulary

Panel round 1 exposed the real hole: *who decides a finding is security-class?*
If the driver decides, asymmetric dismissal is bypassed by classifying-as-
non-security. If we invent our own word list, it drifts and we maintain it.
This problem is already solved outside; Canary should not re-solve it.

**A finding is security-class iff it carries at least one of:**

| Anchor | What it is | Mechanically checkable? |
|---|---|---|
| **CWE-###** | MITRE Common Weakness Enumeration — the standard catalogue of weakness *types* | Yes: the ID exists in the catalogue, and its category is in our in-scope set |
| **OWASP ASVS Vx.y** | Application Security Verification Standard — *verifiable requirements* by chapter (V2 auth, V3 session, V4 access control, V5 validation, V6 crypto, V7 logging, V8 data protection, V9 comms, V12 files, V13 API, V14 config) | Yes: chapter/section exists |
| **STRIDE category + named asset** | Spoofing · Tampering · Repudiation · Information disclosure · DoS · Elevation of privilege — for design-level hazards with no code site yet | Partially: category is enumerated; the asset must be named |

Consequences, all deterministic:

- **The reviewer emits the anchor; the harness validates it.** A security claim
  without a valid anchor is malformed and is returned for re-labelling — it is
  not silently downgraded to advice.
- **The driver may WIDEN, never NARROW.** Adding an anchor is free; removing
  one is a **human waiver**. This is what closes the laundering surface Plinth
  spent three bounds on: the label is no longer the driver's to withdraw.
- **CVSS scores the severity**, so "how bad" is also not our invention; the
  human waiver threshold is a CVSS band, not an adjective.
- **The deterministic lane speaks the same language.** Semgrep/CodeQL/OSV
  already emit CWE and CVE identifiers, so scanner output and model findings
  land in one namespace and dedupe against each other — a model finding that
  duplicates a scanner CWE is not a second obligation.
- **Coverage is expressible as a checklist.** ASVS chapters give the deny-skip
  manifest a public referent: "this surface has no ASVS V4 coverage" is a
  statement about a published standard, not about our taste.
- **Supply chain** rides on the same rails: SLSA levels for provenance,
  OSV/CVE for known-vulnerable dependencies.

**Why not simply "whatever codex-security finds"?** Because it makes the
definition vendor-coupled and unstable: the class changes silently when a
vendor upgrades (measured: a CLI upgrade broke our loop mid-session), it cannot
be checked mechanically, it dedupes against nothing, and it collapses to a
single family — the exact independence loss the pre-mortem found. Vendor tools
are *producers* of anchored findings, never the definition of the class.

**Hazard classes** (which gate without a probe, per Principle 1) are therefore:
security (CWE/ASVS/STRIDE-anchored, as above) · data-loss · concurrency/race ·
authz · compliance-retention. The first is externally defined; the rest are
short, enumerated, and each requires a named asset and a failure sequence.

---

## Panel discipline (amended after round 1)

Round 1's seat prompt said "your only success criterion is dissent" and "do not
soften." That is a **hallucination incentive**, and it produced at least two
dutiful objections alongside the real ones. Amended rules:

1. **A seat may find nothing.** "No dissent found on X — the strongest attack I
   could construct is Y, and it fails because Z" is a **complete, successful**
   result. Manufactured dissent is a defect, and a seat that never reports a
   survival is not calibrated.
2. **Every dissent is calibrated**: confidence (high/medium/low), severity if
   right, and a concrete failure sequence (actor → action → consequence). An
   uncalibrated objection is advice, not dissent.
3. **Dissent is always advice.** It never gates. It is *specified* advice —
   the driver must disposition it on the record, which is not the same as
   obeying it.
4. **The author defends or updates, explicitly.** For each dissent the author
   states: *upheld* (and updates the design) or *defended* (and says why the
   scenario does not obtain). Reflexive folding is as much a failure as
   reflexive defence — the author is a participant, not a defendant.
5. **Both directions are measured.** Track `dismissed-dissent-later-proven-
   right` (was the 10th man heard?) **and** `author-defended-and-upheld`
   (did the author cave to pressure?). Either rate drifting toward zero means
   the panel has become theatre.

## Driver contract (one page — this is the whole thing)

1. **Challenge requirements first.** Every requirement has an owner and a
   reason. Requirements compile to probes; what cannot compile is guidance and
   cannot gate. Argue with dumb requirements before building — deletion is a
   disposition, not a failure.
2. **Delete before you fix.** Before debugging anything, ask whether the code
   survives the next architecture. A defect in deleted code is a free pass.
3. **Probes gate; hazards gate; everything else advises.** Deterministic checks
   and failing probes block. A claim in a declared **hazard class** (security —
   CWE/ASVS/STRIDE-anchored — data-loss, concurrency, authz,
   compliance-retention) blocks **without** a probe, resolvable only by a fix, a
   disproof, or a human waiver. Everything else is advice: recorded, counted,
   never dropped, never blocking.
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

## Panel record — adjudicated 2026-07-31

Seats (all context-blind to the drafting session, assigned adversarial roles):
**10th man** = codex, cross-family, instructed to argue the strong-form opposite
of every principle with no praise permitted · **pre-mortem** = fresh Opus,
"it failed six months out, write the post-mortem" · **oracle** =
`advise --impactful`, architecture only.

**Method note that changed the outcome:** the charter says disagreement marks
underspecified sections. The panel produced something stronger —
**independent convergence**. Three seats reached the same core defect by three
different routes, which marks a section that is simply *wrong*. That
distinction is now doctrine: convergence ⇒ redesign, divergence ⇒ specify.

### CONVERGENT — redesigned (all three seats, independently)

**A. The probe rule silenced credible unprobeable hazards. FIXED by redesign.**
Oracle: contradiction between Principle 1 and the security floor — no probe
exists for weak crypto or a logged token. Pre-mortem: a missing rate limit, an
authz check that passed only because the fixture ran as admin, and a deploy
hazard were all labeled advice and **left no ledger trace at all**; reviewers
then drifted toward trivially-probeable nits. 10th man (hard dissent 3):
"credible security, safety and concurrency concerns must block even before
reproducibility exists."
→ **Principle 1 replaced.** Two blocking classes: *probe-backed* (a failing
probe, which joins the suite) and **`judgment-blocking`** — a claim in a
declared hazard class (security · data-loss · concurrency · authz ·
compliance/legal-retention) blocks **without** a probe and can only be resolved
by a fix, a disproof, or a **human** waiver. Everything outside those classes
with no probe is advice — and advice is now *recorded and counted*, never
dropped, so the drift is measurable (metric: advice-to-probe ratio by severity).
Reproducibility is no longer a licence to ignore a hazard.

**B. Adjudication-completeness gated paperwork, not outcomes. FIXED.**
10th man (hard dissent 2): "a recorded dismissal is not evidence of
correctness, and reviewer output must not control repository availability" —
plus a reviewer-driven DoS: hundreds of probe-backed variants of one weak claim
force bulk dismissal. Pre-mortem: reason strings decayed to ~8 words in three
weeks and `deferred: "tracked in queue"` became 60% of dispositions; also a
mid-review push **cancelled** the lane, leaving no `findings.json` — zero
findings, all dispositioned, **vacuously green**. Oracle: no positive lane
canary.
→ **The merge gate is now COVERAGE, not completeness**, and is deterministic:
`findings.json` must exist, `reviewed_sha == merge_sha`, the security
classifier's decision must be recorded *for that diff*, and the lane must be
proven live by a **seeded-defect canary** (a known-buggy fixture must yield ≥1
finding or the lane is declared broken). Stale, cancelled, or never-fired ⇒
**red**, never green. Dispositions carry **expiry and provenance**: `deferred`
turns the ledger red at its date; a "delete before you fix" dismissal requires
the deletion to land within one train; findings must **earn standing** (deduped
by class, capped per class per round) so a noisy reviewer cannot conscript
availability.

**C. Security coverage — the hole ships THROUGH the trigger list. FIXED.**
Oracle: *who* classifies a finding as security? If the driver does, asymmetric
dismissal is bypassed by classifying-as-non-security — Plinth's exact
laundering surface, reopened. Pre-mortem: a new webhook file fell outside the
allow-fire globs, so the specialist pass never ran and **no finding existed** —
"the human key guards the exit door of a room nobody entered" — after which the
driver narrowed the globs inside a feature commit, legal because trusted-driver
deleted the tooling-edit class.
→ **Trigger list inverted from allow-fire to DENY-SKIP**: any new file, new
dependency, or new parse/auth/network call site outside a human-ratified
known-safe manifest fires the specialist pass. **`triggers.json` and the
known-safe manifest cannot change in the same PR as product code** (a
deterministic check, not a policy). Hazard-class labels are emitted by the
*reviewer* and may be widened by the driver, never narrowed — narrowing is a
human waiver. Coverage, not just dismissal, is gated.

**D. Trusted-driver deleted gate self-protection. PARTIALLY REVERSED.**
10th man (hard dissent 1), and nobody else caught it: with no pinned copies, a
PR can modify Canary's gate implementation, CI executes the modified source,
"the altered driver suppresses scanners and emits valid-looking receipts — the
same PR approves itself." I deleted pinning because its one-release latency bit
us three times in one day; that threw out the property that makes a gate a gate.
→ **Split the difference: pin the VERIFIER, not the instrument.** The
deterministic gate (coverage check, ledger verifier, scanners, trigger
evaluation) runs from an immutable pinned ref; everything else — planning,
review lanes, canaries, driver tooling — runs from source. So instrument
improvements land with zero latency, and no change can execute the gate that
judges it. This is a *narrow* pin over a small verifier, not a vendored copy of
the world.

### ACCEPTED — amendments (single-seat, upheld)

**E. Runtime-check the slice assumptions** (pre-mortem, new). A repriced vendor
silently collapsed the cross-family seat to the builder's own family for six
weeks — exit 0, green, independence gone. Slices list assumptions but nothing
watched them. → Assumptions become **executable predicates**; the gate records
distinct model-family count per gated PR and fails when a declared
cross-family seat is not satisfied.

**F. Mutation testing moves forward, and is scoped** (oracle order + 10th-man
objection). Oracle: every slice mints probes that go unverified until c7.
10th man: mutation testing brands meaningful tests hollow via equivalent
mutants and drives implementation-coupled assertions. → Pulled to immediately
after probe compilation, but **advisory only** and reported as a *ratio trend*,
never a gate. Pre-mortem's warning is minuted: mutation measures line
sensitivity, not hazard coverage — it can never certify hazard classes.

**G. Self-pruning gets hard exclusions** (all three, mildest form). Rare-event
defenses (dependency/security scanners) are **never** prunable; a check that
has ever produced a true positive is never prunable; proposals are disqualified
when dismissals come from a single author; and pruning requires **escape
evidence**, not frequency. Pre-mortem's scenario — the driver's own dismissals
deleting parser hardening, nine proposals ratified in one sitting — is why
batch ratification is banned.

**H. Error budget narrowed to a floor, not a dial** (10th man). "Historical
averages relax scrutiny exactly when a singular high-impact change needs it."
→ The budget may **never** relax hazard-class handling or the security floor;
it only modulates *generalist* review depth on non-hazard diffs.

**I. Human-queue latency budget** (oracle). Asymmetric dismissal routes more to
the human; unbudgeted human gates are the fire-escape condition this charter
opens by condemning. → Waivers carry an SLO; a breached SLO is a
**planning-visible** signal (it changes slice sizing), never an auto-approval.

### DISMISSED — with reasons on the record

**J. "Delete `judge on the record` entirely; findings should earn standing"**
(10th man §4). *Partially adopted, then dismissed as stated.* Standing is
adopted (see B: dedupe, caps). Deleting the primitive is dismissed: it is the
only mechanism that makes a wrong finding cost **one written sentence** instead
of a review round, and the measured alternative is a 30-round loop that
diverged. Removing it restores comply-or-grind.

**K. "Async review is unsafe; risk-bearing review belongs before merge"**
(10th man). *Dismissed as stated, with the risk conceded and mitigated.*
Hazard-class diffs are already **synchronous** (deny-skip specialist pass
blocks pre-merge), so the scenario named — a parser-level authz bypass — is now
covered by C, not by async timing. Making *all* review synchronous reinstates
per-merge model latency, the exact cost this design exists to remove. Residual
risk accepted explicitly: a non-hazard defect can live on main until the sweep.

**L. "Ship the smallest atomic change regardless of line count"** (10th man
§6). *Adopted as an exception, dismissed as a rule.* The migration scenario is
real — a split schema/writer/reader/backfill change is worse than one atomic
900-line change. So the cap gains an **atomicity override with a recorded
reason**, and stays the default, because diff growth manufacturing findings is
measured, not hypothetical.

**M. "Fail-loud must permit controlled bypass in emergencies"** (10th man §7).
*Dismissed for gates, adopted for lanes.* An emergency patch may bypass an
**advisory lane** (recorded); it may never bypass a deterministic gate or the
security floor. The named damage — an exploitable bug live while a vendor is
down — is answered by lane bypass alone.

**N. "Plan-as-data forces premature structure; plans should be narratives"**
(10th man). *Dismissed.* Concedes the discovery problem: `files` and `checks`
become **optional-until-implementation**, and a `discovery` slice type carries
objective + budget only. But prose plans produced an entire deferred-defect
family of NLP classifiers here; structured-fiction risk is answered by making
fields optional, not by returning to parsing prose.

**O. "Gauntlet tournaments produce monoculture benchmark-gamers"**
(10th man). *Dismissed — already opt-in and non-default*, and the objection
argues against making it infrastructure, which the charter's Non-goals already
forbid. Minuted: judge against **references and hazard cases**, not only
compiled probes, precisely to avoid selecting the best probe-gamer.

**P. "Permit judgment-based requirements to gate"** (10th man §1). *Adopted
via A*, not as stated: compliance/legal-retention is now a declared hazard
class, so such requirements gate through `judgment-blocking` with a named
owner — rather than every untestable requirement gaining gate authority.

### Net effect

Four of seven driver-contract principles were rewritten by this panel, and one
architectural decision (no pinned copies) was reversed in part. The charter that
went in would have shipped the pre-mortem's authorization bypass; **I wrote it,
and three assigned dissenters caught it in one round for a few dollars.** That
is the strongest available argument for institutionalizing the 10th man — and
for the rule that the author never grades their own work, which is the same
defect that produced hollow canaries in the Plinth sessions.

**Status: amended; requires a second panel pass on the redesigned sections
(A–D) before ratification.** No dissent in the DISMISSED set is security-class,
so none required a human key; the security-class findings in A and C were all
adopted.
