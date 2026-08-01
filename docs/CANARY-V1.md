# Canary v1 — charter

**Posture: ship.** Canary exists to make shipping fast, and to keep two things from
shipping with it — known bugs and security holes. Everything else is negotiable,
and most of it should be negotiated away.

Successor to Plinth, clean-sheet, under a **trusted, fallible driver** threat model.
Plinth goes maintenance-frozen; downstream repos migrate when Canary earns it, never
by fiat.

---

## The one rule that governs the rest

**Default is ship.** Blocking is the exception and must justify itself. Every
mechanism here states what it costs in latency and what it has caught; one that
cannot answer both gets deleted at the next review.

This is written first because drafting this charter demonstrated the failure mode it
exists to prevent. Four adversarial panel rounds took the plan from 7 slices to ~20 —
each finding individually correct, collectively a quarter of work before anything ran.
**Adversarial reviewers are rewarded for finding problems, every fix adds mechanism,
and nobody on a panel is accountable for shipping.** That is Plinth's 30-round loop
reproduced at design time.

Worse: the largest addition — a nine-slice cryptographic trust root — defended against
a driver that games its own gate, which is **explicitly a non-goal of this document**.
Correct findings, wrong threat model, adopted anyway. Hence the checking rule in Panel
doctrine below.

---

## Evidence, cheapest first

| Verifier | Cost | Use for |
|---|---|---|
| Computation (`cmp`, schema, types) | ~free, unarguable | identity, structure, invariants |
| Execution (tests, canaries, probes) | cheap, reproducible | behaviour |
| Model judgment | expensive; good at generating hypotheses, unreliable as a verdict | finding bugs, comparing candidates |
| Human judgment | scarcest | irreversibles, security waivers, value tradeoffs |

Measured in Plinth: byte-identity beat a model review; canaries caught what 30 review
rounds did not; a review gate was silently broken for hours while quality held, because
deterministic checks and recorded judgment carried it.

## Principles

1. **Ship by default.** Deterministic checks and declared hazards block. Everything
   else is advice: recorded, counted, never blocking.
2. **Gates are deterministic.** No model verdict is load-bearing. "Every hazard finding
   has a disposition" is `jq`, not judgment.
3. **Judge on the record.** Findings, deviations and deleted requirements resolve as
   `fixed | dismissed | deferred` with a written reason. You may dismiss anything except
   a security finding; you may ignore nothing. This makes a wrong finding cost one
   sentence instead of a review round.
4. **Trusted driver.** No malicious-driver hardening. Runs from source; gate integrity
   is `CODEOWNERS` on `.github/` plus branch protection — accident-level protection,
   which is the level this threat model asks for.
5. **Fail loud.** Silent skips, swallowed output and error messages that guess are
   defects. An error that guesses is worse than one saying "unknown" — measured: a
   `prompt_bytes` capacity guess hid a schema rejection for hours.
6. **Delete before you fix.** Ask whether code survives the next architecture before
   debugging it. A defect in deleted code is a free pass.
7. **Check prior art before finalizing, never before generating.** Researching first
   anchors you; never researching reinvents badly. Adopting the standard is the default
   — measured: an invented hazard vocabulary lost outright to CWE/ASVS.

---

## Security floor — the one thing that never bends

Phase-independent. Prototyping skips generalist review, never this.

| Layer | When | Gate |
|---|---|---|
| Scanners (secrets, SAST, OSV) | every PR | blocking |
| **Dedicated security pass** — specialist tool/model, cross-family from the builder | PR touches a triggered surface | blocking by adjudication |
| Deep sweep | weekly + release tags | findings → queue |

**Triggered surfaces** (list in-repo): auth, crypto, secrets/tokens, session, parsers of
untrusted input, dependency manifests, agent tool-call boundaries. Unreadable classifier
⇒ **run the pass**.

**A finding is security-class iff it carries a public anchor** — CWE (Base or Variant;
Pillar/Class such as CWE-20 are rejected, since they admit anything), OWASP ASVS
requirement, STRIDE + named asset, CVE/GHSA/OSV, or OWASP LLM Top 10 / MITRE ATLAS for
agent surfaces. The **reviewer** emits the anchor; the driver may **widen, never
narrow**. That asymmetry stops "reclassify it as non-security" and costs nothing.

**Dismissing a security finding opens `[BLOCKING]` for the human.** One hard key, kept
cheap by being rare.

**Impact ladder, not CVSS**, for first-party findings: credential exposure ·
cross-tenant access · authn bypass · authz bypass · injection/RCE · other. CVSS is
self-scored by the party who benefits from a low number; keep it to the dependency lane
where it is third-party assigned.

**Dedupe on location first, CWE second** — never CWE alone, which false-merges two
distinct sinks sharing an id and marks a real vulnerability handled.

---

## How work flows

**Plan.** Requirements carry an owner and a reason; one with no owner is deleted.
Testable ones compile to probes; untestable ones are guidance and cannot gate. Plans are
**data** — `{objective, files?, checks, budget, assumptions[]}` — because NLP-parsing
prose plans produced an entire defect family in Plinth. Slices ship in ≤1 session, with
an **atomicity override** for changes that are worse when split (schema + writer + reader
+ backfill is one change, whatever its size).

**Build.** Course correction is a plan diff with a recorded reason. Optional **gauntlet**
for wide solution spaces: N candidates from cheap models, blind A/B against compiled
probes and references — **with the state of the art entered as a candidate**, so if
bespoke cannot beat the standard, the standard wins and nobody argues.

**Review.** Advisory, off the critical path: once per PR (never per push), lean payload,
fail loud on CLI error. Async sweep against main feeds a queue. The blocking check is
that every **hazard-class** finding has a disposition — coverage of judgment, not of
paperwork.

**Stop.** Two failed fix attempts → replan. Budget blown → replan. Assumption broken →
replan. Irreversibles (auth, crypto, migrations, deletion, public API, deps) → human.
Gate-semantics change → human, fresh context. `[BLOCKING]` stops one path, never the
others.

---

## v1 slices — six, then we use it

Built under Plinth's existing loop, which works and is measured. Canary gates itself
from c4 onward.

| id | objective | proven by | budget |
|---|---|---|---|
| **c1** | Repo, one-page contract, `metrics.jsonl` (tokens · wall-clock · **time-to-merge** · escaped defects), stop table | contract fits one page; ledger appends | 1 |
| **c2** | Plan-as-data + `canary adjudicate`: dispositions with reasons, expiry on `deferred`, every open hazard accounted for | reasonless dismissal rejected; unaccounted finding rejected; expired deferral turns the ledger red | 1 |
| **c3** | Deterministic CI gate: tests · canaries · scanners · hazard-disposition completeness (pure `jq`); `CODEOWNERS` on `.github/` + branch protection | a PR with an undispositioned hazard finding goes red; a workflow edit requires code-owner review | 1 |
| **c4** | Security floor: trigger list, anchor validation (Base/Variant CWE only), widen-never-narrow, impact ladder, `[BLOCKING]` on security dismissal | a new auth/parser site fires the pass; a Pillar CWE is rejected; a driver cannot narrow a label | 1–2 |
| **c5** | Advisory review lane + async sweep: once per PR, lean payload, fail-loud, rotating seeded fixture | a known-buggy fixture yields ≥1 finding or the lane is declared dead; a CLI error fails loudly | 1 |
| **c6** | Harvest from Plinth: guard hooks, canary suites, lane-guard, NEEDS-HUMAN, checkpoint, lean-payload machinery | harvested suites pass in the new repo | 1 |

**~6 sessions to a working system**, which then ships its own improvements. Anything not
in these six is v1.1 or later and must earn entry by pointing at a defect that escaped.

**Deferred with intent:** mutation testing (advisory, once real probes exist) ·
self-tuning / pruning / error budget (needs ledger history, and it is the only mechanism
whose failure mode is *removing* controls) · gauntlet tournaments (opt-in, never
infrastructure) · panel machinery beyond an ad-hoc call.

---

## Deliberately out of scope — with the receipt

Four panel rounds produced correct findings against a threat model we do not hold. Kept
so the trade is explicit rather than forgotten, and so a future reader can reverse it
deliberately:

- **A PR can edit its own workflow to fake the required check** (round 3, F1). Real.
  Mitigated to accident level by `CODEOWNERS` + branch protection; fully closing it needs
  a protected supervisor in a second repository — malicious-driver defence, not ours.
- **Payload/inventory binding, object-DB derivation, content digests, in-toto + Sigstore
  attestation, shadow evaluation, freeze ceremony, break-glass SOP** (rounds 3–4). All
  correct, all defending against a driver gaming its own gate: ~9 slices for a threat we
  do not model.
- **A supervisor can prove bytes were submitted, never that a model considered them**
  (round 4). True regardless of design — so we never claim model coverage, only that a
  lane ran and returned schema-valid output.
- **Seeded controls detect gross blindness, not selective blindness** (round 3). A bound
  on what the lane canary proves.

**Reversal trigger:** if the threat model changes — untrusted contributors, a compliance
regime, or a real incident of gate tampering — this section is the build plan, already
reviewed.

---

## The objective function — what reviews are actually scored against

Shipping, security, correctness and completeness **genuinely compete**. A review that
optimizes one of them is not rigorous, it is miscalibrated — and it will be
counterproductive in exact proportion to how good it is at its proxy.

Adversarial review is scored on *defects found*. That is a proxy for product quality,
which is a proxy for value. Each hop drops the tradeoff, which is how four correct
panel rounds turned a 7-slice plan into 20. **The fix is not to avoid pointing seats at
cuts; it is to give them the right objective and let them argue within it.**

### Every panel run declares its stage and weights

| Stage | Ship | Security | Correctness | Completeness | What blocks |
|---|---|---|---|---|---|
| **Prototype** | ●●●● | ●●○○ | ●○○○ | ○○○○ | security floor only |
| **Build-out** | ●●●○ | ●●●○ | ●●○○ | ●○○○ | + hazard-class findings |
| **Harden** | ●●○○ | ●●●● | ●●●● | ●●○○ | + reproduced correctness defects |
| **Mature / regulated** | ●○○○ | ●●●● | ●●●● | ●●●● | + coverage and compliance obligations |

The **security floor never moves** — it is the one weight that does not vary, because a
prototype that leaks credentials is not a cheap prototype, it is an incident. Everything
else does.

Stage is a **declared property of the product**, recorded in the ledger, and it is what
a seat argues within. A finding that would be right at *Mature* and wrong at *Prototype*
is not a good finding — it is a finding at the wrong stage, and the seat should say so.

### Seats have a symmetric mandate

**"This control costs more than it saves — delete it" is a first-class finding**,
carrying the same calibration as "this is missing": confidence, severity, and a concrete
sequence. A seat that has never proposed a deletion is not calibrated to the objective;
it is calibrated to its proxy.

This subsumes the "shipping seat" as a bias-corrector. A shipping perspective is still
worth staffing on large panels, but as **one legitimate view among several** rather than
a counterweight bolted on to cancel a bias we chose not to fix.

### Seats are measured on net contribution, not output

Two rates, both from the ledger, both required — either drifting to zero means the panel
has become theatre in one direction or the other:

| Metric | Detects |
|---|---|
| **dismissed-later-proven-right** | the panel was right and we ignored it |
| **adopted-later-deleted** | the panel over-produced and we complied — mechanism adopted from a finding, then removed as not worth its cost |

The second is the one this charter was missing, and it is the one that would have caught
round 4 automatically. *Baseline recorded: of the mechanisms adopted across panel rounds
1–4, roughly nine slices' worth were deleted within a day as wrong-threat-model or
not-worth-cost. That is the number to beat.*

### Consequence for when panels run

A panel is worth its cost when the decision is **architectural, irreversible, or
security-class** *and* the stage weights make the tradeoff non-obvious. At Prototype
stage most design questions do not qualify: the cheapest way to evaluate a reversible
decision is to build it and read the ledger.

---

## Panel doctrine — for architectural, irreversible and security decisions only

Cost is real and the bias is systematic. Use sparingly.

- **Assigned roles**, not "critique this": dissent (argue delete/invert), pre-mortem
  ("it failed in six months — write the post-mortem"), oracle (architecture),
  practitioner (domain).
- **Every run declares stage and weights** (see The objective function). Seats argue
  within the declared objective; a finding correct at another stage is labelled as such,
  not adopted.
- **Mandate is symmetric**: proposing a deletion is a first-class finding. Staff a
  shipping perspective on large panels as one legitimate view — not as a counterweight
  bolted on to cancel a bias we could have fixed at the source.
- **Every finding is checked against the ratified threat model and Non-goals before
  adoption.** A correct finding about an actor we do not defend against is *recorded, not
  adopted*. This rule exists because its absence cost ~9 slices.
- **A seat may find nothing.** "No dissent found — strongest attack was X, it fails
  because Y" is a complete, successful result. Manufactured dissent is a defect.
- **Calibration:** confidence · severity · concrete failure sequence. An uncalibrated
  objection is advice.
- **Independence is checked, not assumed.** Family independence from the author is a
  recorded property of a run. Measured failure: rounds 1–2 ran three of four seats in the
  author's own family, including the security seat, and an operator question surfaced it.
- **The author defends or updates, explicitly.** Reflexive folding is as much a failure as
  reflexive defence. Measured: author-defended 1-of-15 in round 2 and 0-of-12 in round 4 —
  a clear capitulation signal, caught by the operator rather than by the metric.
- **Convergence ⇒ redesign. Divergence ⇒ specify.** Independent seats reaching the same
  defect by different routes means the design is wrong; disagreement means it is
  underspecified.

---

## Panel records

Full findings and adjudications for rounds 1–4 are in this file's git history on
`canary/charter` (`804bc10` · `890a473` · `2e83820` · `a7f5e3f`). Kept because the
receipts are useful — what was found, adopted, dismissed and why — and because round 4's
over-adoption is the strongest available argument for the shipping seat.

**Ratification: operator.** Marginal return fell to operational detail after round 3;
round 4's value was almost entirely in showing the panel had run past its usefulness.
