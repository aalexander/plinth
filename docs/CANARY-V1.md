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


### Panel record — round 2, adjudicated 2026-07-31

Seats: **dissent** (codex, cross-family) on the redesigned sections A–D and both
amendments · **security practitioner** (fresh Opus) on the taxonomy scheme only.
Recalibrated prompts: explicit licence to find nothing, mandatory
confidence/severity/failure-sequence.

**Calibration result, recorded because it is the point:** the practitioner seat
reported **three explicit survivals**; the dissent seat reported **zero**. Same
licence, opposite behaviour. Either A–D were genuinely all broken, or the dissent
role still carries an incentive the licence did not remove. The seat itself
predicted this and supplied the fix — adopted below as **seeded panel controls**.

#### DISAGREEMENT — C (manifest laundering). Both right; section was underspecified.

Dissent: a maintainer ratifies a broad directory in a tooling-only PR, a later
product PR routes attacker input through it, deny-skip sees only manifested
surfaces, specialist never runs. Practitioner: this **fails** — manifest edits
cannot ride in a product PR, so the two-PR sequence *fires the specialist on the
first PR*; "the strongest mechanism in the document."
→ **Both hold, against different assumptions.** The practitioner is right *if*
ratification is real; the dissent is right *if* it is rubber-stamped. Resolution:
**a manifest-widening PR is itself hazard-class** — it moves the security coverage
boundary, so it fires the specialist pass and requires human ratification with a
stated rationale. Plus the dissent's hardening: manifest entries carry **narrow
structural identity, owner, rationale, expiry**, and are **invalidated when
dependencies, imports, callees, generated outputs or trust-boundary metadata
change**. Per doctrine, disagreement ⇒ specify: the section now states which
assumption it relies on.

#### UPHELD — critical

**D2. Pinning the verifier does not protect evidence PRODUCTION.** (dissent,
critical) The unpinned instrument builds the payload, picks suppressions and
classifies findings; a PR can modify the wrapper to omit one file while still
submitting the seed and the correct SHA. "A verifier cannot recover facts never
placed in its inputs."
→ **Not resolved by pinning everything** (that reinstates measured latency).
Third option: **the pinned verifier independently derives the file/diff inventory
from git and compares it against what was actually reviewed**, attests which lanes
ran, and re-runs the trigger evaluation itself. It verifies *inputs*, not
*receipts about inputs*. This enlarges the pinned surface from "checks artifacts"
to "derives ground truth and compares" — and that is the whole security boundary
of the design.

#### UPHELD — high

**B2. `reviewed_sha == merge_sha` breaks merge queues.** Ephemeral merge-group
commits mean the reviewed SHA can never equal the merge SHA without re-running per
queue revision. → Bind to the **reviewed tree/diff content** (content digest of
the payload actually examined), not SHA equality; the pinned verifier attests the
payload. Goal (no stale review) upheld; mechanism was wrong — an update, not a fold.

**B3. The seeded canary proves only a pulse.** A lane could submit the fixture and
omit the PR diff: seed found, liveness green, unreviewed merge ships. → **Rotating
seeds** plus **end-to-end payload-inclusion attestation** by the pinned verifier.

**A2 + T1 (converged). Anchor validity ≠ class membership.** Dissent: hazard labels
are weaponisable, and "disproof" is judgment. Practitioner: nearly any finding can
carry *some* CWE. → **Anchor is a namespace, not a decision rule.** Every
hazard-class claim now requires a **structured basis: adversary · authority
boundary · security property violated · impact on a named asset.** Missing basis ⇒
malformed, returned for re-labelling (never silently downgraded). Plus a **rapid
human rejection path** for unsupported blocks, so a speculative hazard cannot hold
merge availability hostage.

**T2. Reject Pillar/Class CWEs.** CWE-20/-284/-664/-707 admit anything. Abstraction
level is a field in the catalog → **only Base or Variant CWEs are valid anchors —
`jq`, not judgment.** Kills the degenerate "some CWE fits" case.

**T3. CVSS is the wrong instrument, and reopens laundering one layer down.** It is
self-assessed by the party who benefits from a low score: we closed "reclassify as
non-security" and left open "score it 5.9." Two models routinely score the same
finding 4.3 and 8.8. → **Replace for first-party findings with a 5-bucket impact
ladder keyed to the named asset** (credential/secret exposure · cross-tenant access
· authn bypass · authz bypass · injection-into-interpreter/RCE · other),
reviewer-emitted, **widenable never narrowable** — the same asymmetry as the class
label. CVSS is retained **only in the dependency lane**, where it is native and
third-party-assigned (with EPSS/KEV for prioritisation).

**T4. "One namespace and dedupe" was false.** Semgrep often emits no CWE; CodeQL
emits several at mixed abstraction; OSV emits CVE/GHSA. Worse, taint scanners
report the **source** and models the **sink**. Dedupe on CWE alone **false-merges**
two distinct XSS sinks (both CWE-79) — one real vulnerability marked handled. →
Dedupe key: **normalized location (file + symbol, diff-mapped) primary, CWE
equivalence-class secondary (walking ChildOf/CanAlsoBe), merge only when both
agree. Never merge on CWE alone.**

**T5. The human key degrades into a click.** 12 marginal CWE-20 labels per PR ⇒ 12
`[BLOCKING]` items ⇒ SLO breach ⇒ batch approval; the same availability DoS as B,
relocated to the human queue. → Answered by T2 (Base/Variant only) + T3 (only the
top impact buckets need the key) + standing/dedupe caps from round 1.

**T6. Anchors missing two whole classes.** (a) **Supply chain** has no anchor —
add **CVE/GHSA/OSV id** and **SLSA level**. (b) **Agent-surface hazards** (prompt
injection, tool-call confused deputy, model output reaching a shell or DB) are the
pipeline's *own* highest-likelihood class and currently land in the weakest anchor
— add **OWASP LLM Top 10** and **MITRE ATLAS** as first-class anchors.

**T7. Detection gaps the labelling scheme cannot close.**
- **Business-logic authz** needs the intended policy, which exists in no artifact →
  slices touching authz **declare the policy as data (subject × resource × action)
  and compile it to probes**. The highest-value application of "compile, don't prose."
- **Multi-tenancy** defects are *absence of a clause* (a missing `WHERE tenant_id`);
  no diff-scoped reviewer sees an absence → **repo-level invariant probe, written once.**
- **Cross-slice emergent hazards**: each ≤500-line slice is individually safe, the
  composition is not; diff-scoped review structurally cannot see it. → The weekly
  whole-repo sweep's **hazard-class findings become blocking-by-adjudication**
  (they were advisory). Residual risk minuted, not hidden.

**T8. Version-pin the standards.** ASVS 5.0 renumbered chapters (our map is 4.0.3);
CWE deprecates IDs on MITRE's schedule. → **Pin ASVS version + level (L2 default)
and the CWE catalog version inside the pinned verifier**; claim coverage at
**requirement** level (V8.1.2), never chapter level.

**P2. The amended panel discipline has a symmetric cheap-answer incentive**
(dissent, medium). Rewarding "no dissent found" without measuring attack quality
invites formulaic survival reports. → **Seeded panel controls**: blind-seed known
design defects into a fraction of panels and measure detection, so false negatives
become visible. This mirrors the seeded-defect canary on the review lane — the same
trick applied to the panel itself.

#### DEFENDED — author holds position

**T-anchor. Keep the public taxonomy as the namespace.** Upheld that it does not
decide membership (see A2+T1). Defended that it still earns its place: it gives a
**shared namespace with scanner output**, enables **dedupe** (with the corrected
key), and makes the label **non-removable by the driver** — the property that
closes Plinth's laundering surface. The practitioner independently agreed
("anchoring to a public taxonomy rather than an in-house word list is correct" —
no drift failure constructible). Retained, subordinated to the structured basis.

**Author-defended-and-upheld: 1 of 15.** Recorded, per the discipline: a rate near
zero would mean the author is folding under panel pressure rather than judging.

**Status after round 2: sections A–D, the taxonomy scheme and the panel discipline
are all amended again. Round 2 changed the security boundary itself (D2), so the
pinned-verifier design needs one more targeted pass before ratification — but the
charter is now materially stronger than any single seat, including me, would have
produced alone.**


### Panel record — round 3 (security boundary), adjudicated 2026-07-31

Seats: **grok** (xAI) and **codex** (OpenAI) — **both cross-family from the author**,
correcting the round-1/2 composition defect. Scope: items D and D2 only.
Convergence here is worth more than round 1's, because no seat shares the author's
family.

**Verdicts:** grok — *"this holds"* given implementation musts. codex —
*"conditionally sound, not yet ratifiable as written"* on the strength of F1 below.
**codex is right**; the concept survives, my description of it did not.

#### UPHELD — critical, and neither the author nor grok found it

**F1. Pinning the executable is worthless if the PR controls the INVOCATION.**
Sequence: PR author → edits the local workflow to skip the pinned binary while
emitting the expected check name → branch protection sees green → unreviewed code
merges. **Complete gate bypass.**
→ The pinned surface is not "a verifier binary" but a **protected supervisor and
gate**: required-check registration, an immutable entrypoint (a reusable workflow
in a **separately protected repository**, referenced by full commit SHA), trusted
event acquisition, fresh isolated execution, and the status identity itself — all
outside PR control. *This is the same caller-control bound Plinth's own MANUAL
documented as an honest limitation and never closed; Canary closes it or inherits
it.*

#### UPHELD — convergent across both seats

**F2. Derivation must read git OBJECTS, never a checkout.** Strongest attack
(both seats, independently): a PR-controlled earlier step writes malicious git
config/`.gitattributes`, or the verifier shells out to filter-aware git on the
worktree — evidence is rewritten while the path inventory still matches.
→ Object traversal from trusted-origin commit/tree objects; **system/global/local
git config, hooks, external diff and textconv disabled**; symlinks are mode-120000
blobs and are **never followed**; submodules are mode-160000 gitlinks (a changed
gitlink triggers review; recursing needs its own attested policy); **LFS pointers
are not payloads** — fetch and hash or fail closed; **reject case-folding and
Unicode-normalization path collisions** before any checkout; sparse checkout and
`.gitignore` are irrelevant to object traversal.

**R1. Bind CONTENT, not paths.** A path-only inventory leaves content substitution
open. The payload manifest must carry **blob digests**, and the pin compares
digests of what was reviewed against digests derived from git.

**F3. Any parser that can DROP a finding belongs inside the pin.** Sequence: a
vendor tightens its schema, or a PR edits a lossful adapter → the adapter emits
valid-looking empty findings → the verifier attests invocation only → a security
finding disappears **before** human-waiver enforcement → the vulnerability ships.
→ Raw output preserved and digested; schema-valid response required; **zero
findings distinguished from missing/invalid output**; lane identity/version
recorded; unknown schema fails closed. And the strong form, adopted verbatim:
**if no stable lossless protocol exists for a lane, that lane cannot support a
security-completeness claim.**

**Honest limit on the positive control** (codex): a rotating seed detects **gross
blindness, not selective blindness**. It proves the lane is alive; it cannot prove
the lane looked at the part that mattered. Recorded as a known bound, not papered
over — content-digest binding (R1) is what covers selective omission.

**Latency, both seats:** broad latency is *not* reintroduced — prompts, CLI
releases, lanes, canaries and driver code all change immediately. Narrow latency
remains, deliberately, on gate semantics, trigger policy and the lossless parser,
"because those changes cannot judge themselves." grok's reframe is adopted as
doctrine: **the measured thrice-daily failures were instrument/gate CONFLATION,
not pinning per se; a small slow-moving pin restores self-protection without
re-vendoring the world, and that residual is the definition of a gate.** When a
vendor break needs a pinned-parser fix, the safe immediate outcome is **red or
unknown — never fabricated green**.

#### PRIOR ART — adopted as a SPLIT, per the sweep rule

Both seats independently reached the same disposition, and it is more useful than
either "build" or "adopt":

- **in-toto cannot replace the compare.** Its link **materials are self-asserted by
  the functionary** — an in-toto link of a PR-controlled payload step re-encodes D2
  exactly ("receipts about inputs"). Closing it still requires a trusted step that
  derives materials from git: the same small program in a different envelope.
- **Adopt the envelope and the trust model, not the mechanism**: an **in-toto
  Statement with a Canary-specific predicate** carrying `{base/head trees,
  inventory digest, payload digest, lane identity/version, raw-output digest,
  result}`; the **SLSA v1.2 trust model** (protected control plane produces
  provenance; verifier compares against pinned expectations — SLSA deliberately
  leaves the expectations to the adopter); **Sigstore / GitHub Artifact
  Attestations** for signing identity from a protected reusable workflow.
- **cosign proves signature identity, not input completeness. Reproducible builds
  prove build determinism, not review coverage.** Neither substitutes.
- **Recorded cost of adoption** (the sweep's question 4): GitHub/OIDC coupling,
  workflow permissions, attestation storage, and **private repos require
  Enterprise Cloud**. A full in-toto layout would add key/functionary/layout/link
  lifecycle *without* removing tree derivation, trigger policy or dynamic PR
  comparison.
- **Disposition:** bespoke policy comparison; standard envelope, identity and
  delivery. Recorded per the prior-art rule — this is what a bespoke mechanism
  shipping with a named reason looks like.

#### Residual, stated not hidden

A **malicious trusted driver** that coerces genuinely empty findings while keeping
seed and schema green is **out of v1 scope** (Non-goals: malicious-driver
hardening). Mitigations are scanners, the human security key and the async sweep —
**not** enlarging the pin. Recorded so the boundary's edge is explicit rather than
implied.

**Status: the security boundary is sound in concept and now specified. Pending
before ratification — the protected-supervisor requirement (F1) rewrites the
harvest list and slice c3, since "verifier" was scoped as a script and must become
a protected workflow in a second repository.**

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


### Seat assignment — independence AND measured capability

Two properties, both checkable, neither assumed:

1. **Family independence from the author.** Context-blindness is not
   independence — a fresh context in the same family carries correlated blind
   spots. *Measured instance: panel rounds 1–2 ran three of four seats in the
   author's own family, including the security seat, and nobody noticed until
   the operator asked who the seat was.* The pre-mortem's finding E (silent
   family collapse, exit 0, everything green) played out in the **process**, not
   the product. Family independence is now a **recorded property of a panel
   run**, and a run that cannot achieve it says so instead of proceeding quietly.
2. **Domain capability.** Seats route to the model that is actually strongest at
   the seat's job — security review to the strongest security model, breadth
   seats to the strongest generalist — subject to (1). *Measured instance: the
   security-practitioner seat was assigned by convenience rather than either
   property.*

**Reputation is a prior; seeded controls are the evidence.** The seeded panel
controls adopted in round 2 double as **seat calibration**: seed known defects of
a given class, measure which seats catch them. That converts "codex is good at
security" from folklore into a number, and it re-measures automatically as models
change — which they do on a scale of weeks, not releases.

**The seat map is versioned config with rationale, never hardcoded.** Each entry
records model, family, why it holds the seat, and when it was last calibrated.
A model upgrade invalidates the calibration, not the seat. (Harvested from
Plinth's `MODELS.md`, which already carried seat assignment, named fallbacks, and
a "when models change (they will)" contingency — prior art from our own history,
found by applying the prior-art rule inward.)

---

## Prior-art sweep — required before finalizing, never before generating

**Elon step 1 has a corollary: the dumbest requirement is one that re-solves a
solved problem.** Round 1 of this charter invented a private vocabulary for
hazard classes while MITRE (CWE), OWASP (ASVS) and Microsoft (STRIDE) had
maintained public, versioned, mechanically-checkable ones for two decades. The
panel caught it; the process should have.

**Ordering is the whole design, and it is deliberate:**

| Step | Why in this order |
|---|---|
| 1. **Generate independently** — candidate solution(s) first, no literature search | Researching first **anchors** the design onto the first existing answer found and silently deletes the option space. Creativity is cheapest before exposure. |
| 2. **Prior-art sweep** — what does the state of the art do? | Reinvention is only visible once you have something concrete to compare against. |
| 3. **Reconcile, on the record** | Neither anchoring nor reinvention: a recorded comparison. |

**The sweep gates plan finalization and mechanism implementation — never
ideation.** Four questions:

1. Is there a **standard, specification or published taxonomy** covering this?
   (Versioned, externally maintained, mechanically checkable?)
2. Is there a **reference implementation or well-worn library** — and what did it
   learn the hard way that we have not yet?
3. What is the **named failure mode** of the existing solution — the legitimate
   reason someone might not adopt it?
4. What does adopting it **cost** (coupling, version drift, scope mismatch)
   versus maintaining our own?

**Default: adopt the standard.** A bespoke mechanism ships only with a recorded
disposition naming the criterion on which it beats the prior art — the same
primitive as every other judgement, so "we built our own" is auditable. Adopted
standards are **version-pinned** (a lesson already paid for: ASVS 5.0 renumbered
chapters; CWE deprecates ids on MITRE's schedule).

**In the gauntlet, prior art enters as a CANDIDATE.** The tournament already runs
blind A/B between independently generated candidates; the state-of-the-art
solution is added as one of them, judged on the same compiled probes and hazard
cases. If the bespoke design cannot beat the standard head-to-head, the standard
wins by default and nobody argues about it. Measured instance: the invented hazard
vocabulary lost to CWE/ASVS/STRIDE outright, and the replacement was strictly
better on every criterion — mechanical checkability, scanner dedupe,
non-removability by the driver.

**A skipped sweep is itself recorded.** Prototype-tier slices may defer it, but no
mechanism reaches a hazard-class surface or a gate without one. The sweep costs one
seat and one call; the measured cost of skipping it was a full redesign of the
security section across two panel rounds.

## Driver contract (one page — this is the whole thing)

1. **Challenge requirements first, then check the prior art.** Every requirement
   has an owner and a reason. Requirements compile to probes; what cannot compile
   is guidance and cannot gate. Argue with dumb requirements before building —
   deletion is a disposition, not a failure. **Generate your solution first, then
   sweep the state of the art before finalizing**: researching first anchors you,
   never researching reinvents badly. Adopting the standard is the default; a
   bespoke mechanism needs a recorded reason it beats the prior art.
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


### Panel record — round 4 (the plan), adjudicated 2026-07-31

Seats: **grok** (xAI) and **codex** (OpenAI), both cross-family. Scope: the slice
plan only; the round-3 security boundary was declared settled and neither
re-litigated it. Verdicts: grok — *"the ordering holds; no slice must move."*
codex — *"not yet safe to execute."* **Both are right about different things**, and
codex found three defects grok did not.

#### UPHELD — critical

**O1. `g4` was referenced in prose and does not exist.** I wrote "from g4 onward
Canary gates itself" and never created the slice. Sequence: maintainer treats c1
as implicitly self-gated → pin/required-check installation differs between the two
repositories or is incomplete → driver development proceeds without the asserted
gate → **ungated changes receive false legitimacy**. → **g4 added: bootstrap
promotion and dogfood handover** — install and verify the exact full-SHA pin,
required checks, OIDC policy, failure behaviour and the recorded bootstrap
manifest **in both repositories**, before c1.

**B1/P1 (convergent). A poisoned trust root is self-validating.** Both seats,
independently: the suspect implementation defines both the evidence and its
acceptance, so every later green is *consistent with the lie*, and no downstream
slice can detect it. → Adopted, in ascending cost: (i) **progressive
self-hosting** — once g0 registers a real required check, gate g1–g3 with g0's own
F1 property, shrinking the unprotected window (grok); (ii) an **externally signed
bootstrap release manifest** — all source and dependency digests, exported
repository rules, OIDC expectations and fixture results — **approved by ≥2
independent owners** (codex); (iii) optional **clean-room re-implementation of the
inventory/payload verifier replaying the same fixture corpus**, for the bootstrap
release only, never permanent machinery. The residual stays recorded: selective,
time-delayed malice in the root is out of v1 scope.

**M1. Trust-root evolution has no design.** Changing `canary-gate` after freeze
means a candidate gate effectively reviews itself, or the old gate cannot
understand the new one → bad release promoted → **all consumers inherit it**. →
New slice **g5: trust-root change, shadow evaluation and promotion** (run
candidate alongside incumbent, compare decisions over a fixture corpus and real
history, promote only on agreement + human freeze).

#### UPHELD — epistemics of the proofs (the strongest thread in this round)

**g2 overclaims what a supervisor can know.** *"A supervisor can prove bytes were
constructed and submitted, not that an opaque model received or considered them."*
A provider that truncates or ignores content leaves the supervisor recording
success while claimed coverage is false. → **Claim narrowed to exactly that:**
*these bytes were submitted to this lane identity*. Coverage of the model's
attention is **not claimable** and is now stated as a bound, alongside the round-3
note that seeds catch gross not selective blindness.

**O3. g2's proof crosses into g3.** g2 can record an internally consistent but
incomplete payload; only g3's coverage decision would reject it, so g2 would be
"proven" with no enforcing consumer. → **g2 must itself deterministically reject
inventory ≠ payload.** (This also resolves the seat disagreement: grok called the
g2/g3 seam interface-coupled-but-separable, codex called the proof coupled. Per
doctrine, disagreement ⇒ specify the seam — enforcement in g2, issuance in g3.)

**Unprovable-as-written claims, all rewritten** (this is the hollow-probe pattern
in proof obligations — the same defect as yesterday's canaries):
- **c7**: *"caught by a probe no diff-scoped reviewer would see"* — a claim about
  **absent reviewers**, unprovable. → *the invariant fails on a fixture tree with a
  missing tenant scope.*
- **c8**: *"formulaic vs real survival is distinguishable"* — not decidable without
  a second judge (regresses to model-grading-model), **and a known seed is
  gameable** because the panel agent can recognise the fixture. → **blinded,
  rotated controls scored outside the panel transcript**; the provable claim is
  seed **detection rate**.
- **c2**: *"untestable requirement cannot gate"* — untestability is not mechanically
  decidable; a ceremonial test reference passes. → *every gating claim names an
  executable oracle and its expected evidence.*
- **c4**: *"a driver cannot narrow a label"* — unprovable without an explicit
  **per-taxonomy partial order**; a driver substitutes a differently-shaped label
  and incomparable values are accepted. → define the lattice, or the asymmetry is
  decorative.
- **c5**: one planted call site cannot prove **all** new sites fire (an unsupported
  language construct evades the scanner). → scope to **enumerated syntactic classes
  plus a maintained corpus**.
- **g0**: F1 proves one check-name spoof only; mutable dependencies, untrusted
  event fields and runner/network paths each need their own adversarial fixture.
- **g2 (lossless)**: one lossy-adapter fixture cannot prove general losslessness. →
  **schema-total parsing plus round-trip/property fixtures over every supported
  variant.**

#### UPHELD — sizing. Every trust-root slice was undersized.

Adopted roughly at codex's numbers (grok concurred in direction): **g0** 2–3
(workflow *plus* a hosted ruleset attack harness) · **g1** 2–3, split core object
inventory from the LFS/collision/special-object matrix · **g2** 3–4, split payload
binding from lane capture and normalization · **g3** 2–3, split the coverage state
machine from Sigstore issuance · **c3** 2 (temporal fixtures for expiry) · **c4**
2–3 · **c5** 3+ · **c6** 2 · **c7** 2–3. My 1–2 session budgets assumed slices that
did not have to produce their own adversarial fixtures — the fixtures **are** the
work.

#### ADOPTED — the kill test, which both seats answered identically

**c9 (self-tuning) is deleted from v1**, in both directions: it is the cheapest
slice to drop for speed *and* the safest to drop, because it is **the only slice
whose failure mode is removing or relaxing controls** — a mis-tuned pruner decays
coverage, and the error budget can only ever loosen. It also needs ledger history
that will not exist. → **Moved to v1.1**, gated on real history. **Mutation
testing is extracted from it** and becomes its own slice **after c7** (it had two
incompatible homes — "c2/c7 boundary" in prose, c9 in the table — which is exactly
how a mechanism ends up owned by nobody), and it stays **advisory, never a gate**.

#### Operational homes added (both seats; none existed)

**g6** bad-pin rollback and break-glass (who may move an immutable SHA, dual
control, reverting a pin that is wrong but *valid*) · **g7** Sigstore/OIDC identity
lifecycle: issuer/subject/root rotation, revocation, outage and offline
verification, plus the Enterprise-Cloud private-repo constraint from round 3 ·
**g8** ruleset/CODEOWNERS drift detection and disaster recovery · **c10** freeze
ceremony: a recorded human attestation that the frozen tree equals the reviewed
tree · **c11** human-queue SLO (round-2 item I, which never became a slice) ·
schema/attestation version migration and retention folded into g5.

**Status: the plan is materially larger and materially safer than the one I wrote.
Trust root is now g0–g8 with realistic budgets; v1 driver scope is c1–c8 plus
mutation; self-tuning is deferred to v1.1. Ratification is the operator's call —
this is round 4, the marginal return has fallen to operational detail, and the
remaining risk is concentrated in a bootstrap window that is now explicitly
bounded rather than hidden.**

## v1 slices (revised after round 4 — see the panel record above for what changed and why)

Round 3's F1 changed the shape: the pinned surface is a **protected supervisor in a
second repository**, not a script in this one. That is a trust root, so it comes
first and everything else is decoration on top of it (oracle round 1: *"prove the
completeness gate first"*). Slices are dependency-ordered; each names **what must
be PROVEN**, not merely built.

**Bootstrap problem, stated up front:** Canary cannot gate its own construction —
the gate does not exist yet. Slices g0–g3 are therefore built under **Plinth's**
existing loop (which works, is measured, and is maintenance-frozen but alive) plus
manual human review of the trust root. From g4 onward Canary gates itself. The
handover point is explicit and recorded rather than drifted through.

### Trust root (second repo: `canary-gate`, branch-protected, separate CODEOWNERS)

| id | objective | must be PROVEN | budget |
|---|---|---|---|
| **g0** | Protected reusable workflow + required-check registration; immutable full-SHA entrypoint; isolated execution; trusted event acquisition | A PR that edits its own workflow to emit the expected check name **cannot** turn the required check green (F1 fixture) | 1 session |
| **g1** | Object-DB inventory: commit/tree traversal from trusted-origin SHAs; blob **content digests**; git config/hooks/filters/textconv disabled | A PR-controlled `.gitattributes`/config/worktree substitution **cannot** alter the derived inventory (F2 fixture); symlink=120000 unfollowed, submodule=160000 gitlink, LFS fetch-or-fail, case-fold/Unicode collisions rejected | 1 session |
| **g2** | Payload binding + lane supervision: pinned invoker builds payload from g1, records payload digest, captures lane identity/version, argv, exit, stdout/stderr digests; lossless finding normalization | Omitting one file from the model payload while submitting the correct SHA and seed **fails** (R1 fixture); a lossful adapter that drops a finding **fails** (F3 fixture); zero-findings is distinguishable from missing/invalid | 1–2 sessions |
| **g3** | Coverage gate + attestation: adjudication/hazard-disposition checks (pure jq), in-toto Statement w/ Canary predicate, Sigstore identity, fail-closed decision | Stale / cancelled / never-fired review ⇒ **red**; a valid attestation verifies against pinned expectations; unknown schema ⇒ red, never green | 1 session |

### Driver side (main repo, gated by the trust root from here on)

| id | objective | must be PROVEN | budget |
|---|---|---|---|
| **c1** | One-page contract · `metrics.jsonl` · stop table · seat map as versioned config with rationale + last-calibrated | Contract fits one page; ledger appends; a seat map lacking family independence is **reported, not silently used** | 1 session |
| **c2** | Plan-as-data: slice schema, plan-diff dispositions, `discovery` slice type, reference-class estimates | Untestable requirement cannot gate; a plan diff without a reason is rejected | 1 session |
| **c3** | `canary adjudicate`: dispositions with **expiry + provenance**; standing/dedupe caps; delete-before-fix dismissals require the deletion within one train | Every open finding accounted for; a reasonless dismissal rejected; an expired `deferred` turns the ledger **red** | 1 session |
| **c4** | Security anchors + impact ladder: CWE(Base/Variant only)/ASVS(pinned version+level, requirement-level)/STRIDE/CVE-GHSA-OSV/SLSA/LLM-Top-10/ATLAS; structured basis (adversary · authority boundary · property · impact); widen-never-narrow | A Pillar/Class CWE is **rejected** as an anchor; a hazard claim without structured basis is malformed; a driver **cannot** narrow a label; dedupe is location-primary and does **not** false-merge two CWE-79 sinks | 1–2 sessions |
| **c5** | Security floor: deny-skip manifest (narrow identity, owner, rationale, **expiry**, dependency-change invalidation); manifest-widening PRs are hazard-class; scanners; specialist pass | A new parse/auth/network site outside the manifest **fires** the pass; `triggers.json` **cannot** change in a product PR; a manifest PR fires the pass on itself | 1–2 sessions |
| **c6** | Advisory lanes + async sweep: once-per-PR, lean payload, fail-loud; sweep hazard findings **blocking-by-adjudication** | A known-buggy fixture yields ≥1 finding (rotating seeds) or the lane is **declared dead**; a CLI error fails loudly; never triggers per push | 1 session |
| **c7** | Detection gaps: authz policy declared as data → compiled probes; multi-tenancy repo-level invariant probe | A missing tenant scope is caught by an invariant probe that no diff-scoped reviewer would see | 1–2 sessions |
| **c8** | Panel machinery: assigned roles, licence to find nothing, calibration fields, **seeded panel controls**, prior-art sweep step | A seeded design defect is detected; a formulaic "no dissent found" is distinguishable from a real survival | 1 session |
| **c9** | Self-tuning: mutation testing (**advisory ratio, never a gate**), dismissal-rate pruning with hard exclusions, error budget as a floor | A surviving mutant flags a probe; a security/rare-event check is **never** proposed for pruning; the budget never relaxes hazard handling | 2 sessions |

**Ordering rationale:** g0 before everything — an unprotected gate makes every later
guarantee decorative. g1 before g2 — you cannot bind a payload to an inventory you
cannot derive. g2 before g3 — attesting a comparison you have not implemented is
theatre. c4 before c5 — the manifest is expressed in anchor terms. c6 after c3 —
findings need somewhere to be dispositioned. c9 last: it needs ledger history.

**Mutation testing** was pulled forward from c9 in round 2 to sit immediately after
probe compilation (c2/c7 boundary) — advisory only, reported as a trend.

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
