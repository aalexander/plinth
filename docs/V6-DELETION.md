# v6.0 — the deletion train

**Ratified by operator 2026-07-30** (sequencing: ship 5.1.0, then delete). Deliberately short: a long plan for a
simplification train would be self-refuting.

## The dumb requirement

> The model reviewer's verdict is a hard gate the driver may not override.

Everything below exists to work around it. A hard gate plus a fallible, chatty
reviewer equals deadlock, so you need severity rewriting; rewriting is a fail-open
inside a gate, so you need floors, lexicons, allowlists, Tier-2 protection, receipt
disclosure, canaries; and you still need prose to talk the reviewer down. 29 rounds,
~5M input tokens each, ~145M tokens to ship a few hundred lines.

**Replace with:** reviewer **advises** → driver **adjudicates on the record** → CI
**gates**. An independent model still reads the diff and reports mistakes — that was
always the goal. It just stops being an authority, because it never was one.

## Order matters: receipt semantics FIRST

`receipt / verify` is a required check with `strict:true`. It attests *"a model
approved this."* Until that changes, "review advises" cannot pass the merge gate and
no downstream deletion is shippable.

**v6 receipt attests:** a review ran at this subject; here are the findings; here is
the driver's adjudication of each (fixed / dismissed+reason / deferred+reason). Same
server-enforceable check, same auditability, no authority claim. A dismissal with a
bad reason is now *visible* rather than impossible — which is strictly better than
today, where the driver's only options are comply or grind.

## Deletion list (after the receipt change)

| Delete | Why it existed |
|---|---|
| Thrash demotion: classifier, class allowlist, `SEC_DESC_RE`/`CORRECTNESS_DESC_RE`, `is_precedence_must_block`, `is_external_security`, coverage/canary-depth/fake-CLI/docs-prose/queue-nit arms | Undo findings that shouldn't have blocked |
| Demotion receipt ledger + verifier shape check | Audit the fail-open demotion created |
| Sticky AUTO-RESOLVE, `thrash_class`, sticky ledger | Manage findings recurring across rounds |
| verify/resume modes, coverage credit, seat-swap coverage rules, `round_cap` | Multi-round loop machinery |
| ~120 of `reviewer.md`'s 207 lines | Severity negotiation |
| Stop gate's APPROVED@HEAD condition | Enforce at merge, not at turn end |

**Keep:** the independent review itself; L3 security pass (one cheap call); CI
required checks (tests, scanners, VERSION/CHANGELOG — deterministic, no opinions);
the receipt under new semantics; the destructive-command guard.

## Payload reduction (independent of the above, ~100× on its own)

1. Review the **delta since last review**, not `base...HEAD`. 5M → ~200k tokens.
2. Stop re-inlining the full spec + contract every round (fixed ~50–100k floor).
3. Cap the review unit: one train per branch. Diff-growth is what manufactures
   asymptotic findings — fix → bigger diff → more surface → more findings.

## Success criteria

1. Ship a real change with **one** review pass and a recorded adjudication.
2. Round cost < 500k input tokens.
3. `reviewer.md` under 90 lines.
4. No code path rewrites a finding's severity. Anywhere.
5. The receipt shows what was dismissed and why — auditable after the fact.

## Honest risks

- **A driver dismisses a real defect.** Mitigation: adjudications are on the receipt
  and spot-checkable; CI scanners still gate deterministically; and an advisory
  reviewer can afford to be *more* aggressive, so expect more findings, not fewer.
- **This is the trusted-driver threat model**, already ratified. If the driver is
  adversarial, none of the current machinery stops it either — it just costs more.
- **Deletion is not free**: sticky ids, verify-mode scoping, and the same-open cap
  are load-bearing for today's loop. They come out *with* the loop, not before it.

## Not in scope

Rebuilding the reviewer prompt, new vendors, dashboard work, or anything that adds a
mechanism. If a v6 change adds a knob, it is probably wrong.

## Evidence from the v5.1 train (why this is not a preference)

Recorded so v6 is argued from data, not taste:

- **30 rounds, ~5.07M input tokens each** — ~145M input tokens to ship a few hundred
  lines of real change. Every round re-inlines `base...HEAD` plus the contract plus
  the spec.
- **The loop DIVERGED**: round 29 → 14 open blocking, round 30 → 15. The same findings
  were re-reported at shifting counts on unchanged code ("drops 32 of 33 milestones"
  became "rejects 21 of 33"). A gate whose output moves when its input does not is not
  measuring the code.
- **The escape hatch was booby-trapped**: `.plinth/RESIDUAL.json` was missing from the
  reviewer contract's tooling exemption list, so drafting a residual — the designed way
  out of a non-converging loop — was filed as a TAMPERING **blocker**. The mechanism
  for stopping endless rounds could only be used by triggering one.
- **Three separate diagnosability failures cost more than the bugs they hid**: the
  lifecycle canary reported "26 OK" for a run that aborted a third of the way through
  and still exited 0 (real total: 63); a fixture discarded the subject's output with
  `>/dev/null 2>&1`, making a CI-only red undiagnosable; and the installed pinned guard
  could not honor escape hatches the product already shipped (`build_defer`,
  residual-land). None of these are logic bugs, and none would be caught by more rules.
- **Adding mechanism made it worse.** The v5.1 train added ~1,500 lines of demotion
  bounds; round 29 then found five defects *in that new mechanism*, three of them
  overclaim (a "security is never demoted" floor that demoted XSS, CSRF, plaintext
  passwords and account takeover, because its canary was written by the same author
  as its regexes, using the same words).

### The rule that generalizes

**Triage by architectural survival before debugging.** Ask "does this code survive the
next architecture?" before spending anything on fixing it. Applied to the v5.1 train's
final red: the failing fixture tests multi-round verify orchestration, which this plan
deletes — so it was documented and left, not repaired. An hour spent earlier fixing
demotion internals was avoidable by asking the same question first.

**Corollary for canaries (L1 survives v6, so fix these):** assert expected-vs-actual
assertion counts so a truncated run cannot pass, and never discard a subject's output
on failure.
