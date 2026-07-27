# Plinth — User Manual (v4)

## What Plinth is
A subscription-funded, multi-model dev environment: a frontier model drives (any
vendor — see the driver contract below), and an INDEPENDENT adversarial reviewer — a
fresh session that did not write the code — scrutinizes it (the `reviewer_vendor`:
codex/GPT by default, or claude/grok; risk-tiered — inert docs are approved by the
deterministic floor, code and high-consequence changes get the model). The reviewer MAY
be a different vendor than the driver but need not be; a best-effort cross-vendor second
opinion is the auditor, which runs when `audit_vendor` differs from `reviewer_vendor` and
that CLI is available — if it cannot run it is recorded UNAVAILABLE (non-blocking) and the
primary review remains the gate. Then a
deterministic CI floor (tests + scanners) becomes a required status check that gates every
merge ONCE you enable branch protection (a one-time operator step after the first PR —
`plinth init` only reports branch-protection state, it cannot set it; until then CI is
advisory). A Codex cloud review, once connected, additionally posts adversarial findings on
each PR (security-briefed via the reviewer contract .plinth/reviewer.md). It is ADVISORY by
mechanism, not just by choice: it posts as PR comments and exposes no status-check context
that branch protection could require. Under the architect-resident DEFAULT the local
Stop gate enforces the review loop; under the grok-RESIDENT alternative the loop is
contract-bound until the APPROVED-at-HEAD receipt check (auto mode, v4.7 — the
server-side review gate) is REQUIRED in branch protection. Shipping it is not
enabling it: it gates only where an operator wires `receipt / verify` into ci.yml
AND requires that context (plus `strict: true`). Caller-control bound: a PR can
replace the receipt caller with a green spoof of the same context name (ci.yml
HONEST BOUND). The name is the design:
models are the statue, swapped freely; Plinth is the base that doesn't move. You
own two things — the spec (what to build) and the gates (what may merge).
Everything between is the model's call.

## Current models (July 12 2026 — see .plinth/MODELS.md, updated via `plinth update`)
- **Seats are assigned per model, across vendors (v4)** — three models work
  together. **DEFAULT topology (architect-resident):** the top model (Fable 5 by
  exception on credits, Opus 4.8 otherwise) sits in Claude Code as the ARCHITECT
  — judgment, specs, routing, and a final read-only audit; no routine typing —
  and **Grok 4.5 does most of the coding as the WORKER** (`grok-implementer`
  lane; the worker escalates open questions back to the architect). The local
  guard and Stop gate stay ENFORCED because the resident harness is Claude.
  **Alternative (grok-resident):** the grok CLI as the harness for
  wall-clock-critical sessions — it carries the KNOWN LIMITATION below, and its
  judgment channel is **Fable 5 advising** (`plinth advise`; peer tier Opus 4.8,
  `--impactful` → Fable — scaffolded live, since advise is non-blocking).
  Either way, **GPT-5.6** reviews
  (`reviewer_vendor = codex` + `reviewer_model_tier1/tier2 = gpt-5.6`, shipped
  COMMENTED in fresh scaffolds — GPT-5.6 GA'd July 9 2026 but access is
  per-account and needs Codex CLI >= 0.144.0: uncomment once `codex -m gpt-5.6`
  works for you; an ineligible account stays on the GPT-5.5 vendor default, and
  an active 5.6 knob there would fail loud, not fall back), and **Claude
  (Opus 4.8)** audits (`audit_vendor = claude` — a different family than both
  the WORKER that produced the diff and the reviewer, in either topology). Contingency: if Fable's availability lapses
  (export-control risk — it was suspended once already), the advisor seat moves to
  GPT-5.6 (`advisor_vendor = codex`); the audit seat keeps Anthropic coverage.
  **KNOWN LIMITATION (until auto mode is fully enabled):** under the grok-RESIDENT
  alternative the review-before-PR loop is CONTRACT discipline — no local Stop
  gate fires (grok 0.2.112 executes no `.claude/` hooks) and, until `receipt / verify`
  is wired, required with `strict:true`, **and** the real verifier still runs
  (caller-control bound — context name alone is spoofable; ci.yml HONEST BOUND), no
  status check reliably verifies APPROVED-at-HEAD. v4.7 ships that check; enabling
  it per repo is an operator step. Where those conditions do not all hold, the
  ENFORCED-gate path is a Claude driver; choose per task, and treat non-Claude-driven
  PRs accordingly (the PR body's review audit is the evidence trail).
- **Under the architect-resident default** the in-family routing still applies —
  Sonnet 5 for mechanical/doc work (Tier 0–1), Opus 4.8 default, Fable 5 by
  exception on usage credits — and the implementer lanes carry the typing
  (grok default, codex cross-vendor). Under the grok-RESIDENT alternative the
  lanes are dormant (they are Claude-Code subagents) and mostly moot: that
  driver is already the cheap fast typist and consults judgment UP via
  `plinth advise` instead. Either way the driver's model is its own speed/cost
  call: GUIDANCE, not a gate.
- Keep `audit_vendor` a DIFFERENT vendor than `reviewer_vendor` — a match disables
  the cross-vendor audit (review.sh notes it on Tier 2). The resume threshold
  scales per reviewer vendor automatically.
- The reviewer's risk tier is the immutable adversarial gate; the driver's model is
  not. The driver's only lever over review cost is tier hygiene — keep low-risk work
  in its own change so it takes the cheap path, don't bundle it into a Tier-2 diff.
- Orchestration: `/effort` -> `ultracode` for substantive tasks.

## Commands
- `plinth init ~/Dev/<repo>`    — scaffold a project (templates once + shared pinned),
  git-init if needed, offer GitHub repo creation, probe branch protection
- `plinth update ~/Dev/<repo>`  — pull new shared files after updating Plinth,
  backfill per-project files new to this version (never touches yours, with TWO
  managed exceptions: it appends any missing Plinth-managed security patterns to
  `.plinth/protected-paths`, since those must propagate — your own added lines are
  left intact; and it migrates a legacy root `NEEDS-HUMAN.md` into `.plinth/` so the
  dashboard finds it, warning instead of clobbering if both exist), re-run the GitHub
  preflight; review the diff, then commit
- `plinth goal ~/Dev/<repo>`    — drop a GOAL.md draft for auto-research mode
- `plinth watch ~/Dev/<repo>`   — live session dashboard (add `--once` for a
  single frame); see "The dashboard" below
- `plinth queue ~/Dev/<repo>`   — the full NEEDS-HUMAN queue, every item
  untruncated (the watch banner shows what fits the screen and points here).
- `plinth smoke ~/Dev/<repo> -- <command>` — run the real thing on real
  hardware; writes a SHA-bound execution receipt that the next review round
  verifies RUNTIME findings against. Failures are data — receipts record them
  identically.
- `plinth hookprobe <grok|codex>` — which wired `.claude/` hook EVENTS does this
  vendor CLI execute? Wires a marker for EACH of the four events Plinth
  enforcement uses (SessionStart = session-start, PreToolUse = guard,
  PostToolUse = pulse, Stop = review gate), drives the CLI once (one small model
  call, wall-clock capped: PLINTH_HOOKPROBE_TIMEOUT, default 120s), and reports
  each event separately, incl. whether JSON arrived on stdin (what the real hooks
  need). Exit 0 = ALL FOUR invoked; 1 = none or some — a NOT-invoked event is
  certainly unenforced, and an INVOKED event is necessary-but-not-sufficient
  (verify end-to-end before relying on it); 3 = CLI missing; 4 =
  INCONCLUSIVE (timed out, the CLI never executed the probe's sentinel command —
  unauth/sandbox/model failure — or it exited nonzero after executing it, where a
  late failure could swallow late hook events such as Stop; an inconclusive run
  is never hook evidence). Version/environment-dependent — trust the probe over
  vendor docs and over this manual. Re-run after CLI upgrades.
- `plinth advise [--impactful] "<question>"` — (run inside the project) the DRIVER
  consults a model as good or BETTER than itself, read-only, for a collaborative,
  NON-BLOCKING second opinion — distinct from the adversarial reviewer (the gate) and
  the cross-vendor auditor. It PROMPTS the advisor with a discipline preamble — give a
  VERDICT not a survey ("Do X, not Y, because Z" + the single deciding risk), read the
  code before opining, stay terse — and prints what the advisor returns; the shape is
  guidance to the model, not an enforced/validated output. `--impactful` (architectural /
  hard-to-reverse decisions) escalates to the stronger model. Vendor-agnostic and
  cross-family (a Grok driver can consult Fable); see the `advisor_*` knobs below.
- `plinth changelog-collate [<target-repo>]` — **Plinth-repo release helper** (not a
  per-project command). Folds every `changelog.d/*.md` fragment except `README.md`
  into a new top section of `CHANGELOG.md`, bumps `VERSION` from the highest fragment
  `bump:` (major > minor > patch), and deletes the collated fragments. Defaults to
  the current working directory; pass a target repo path to operate elsewhere.
  Empty `changelog.d/` is a no-op (exit 0). Invalid/missing `bump:`, empty body, bad
  slug, or malformed `VERSION` aborts without rewriting `VERSION` or `CHANGELOG.md`.
  Format and rationale: `changelog.d/README.md`.
- `plinth dash` / `plinth dashboard` — multi-instance HTML wallboard on
  **127.0.0.1** only (`--port N`, default 7348). Discovers Plinth projects
  (`PLINTH_DASH_ROOTS`, else `~/.config/plinth/dashboard-projects`, else
  `~/Dev/*/.plinth/config`), serves a dark card UI, and exposes
  `GET /api/snapshot`. `--snapshot` prints that JSON offline (no server). Does
  not replace `plinth watch`. See “Multi-instance wallboard” below.
- **Implementer lanes** (`.claude/agents/grok-implementer`, `codex-implementer`) — for a
  Claude/Fable driver, delegate the TYPING of well-specified work to a cheaper cross-family
  CLI instead of typing it yourself. Hand a lane a five-part spec (objective · files ·
  interfaces · constraints · verification); it drives grok/codex headlessly and re-runs the
  verification itself before reporting (a lane's "it works" is not evidence — Rule 10). The
  economics: spend the frontier model on judgment, the lanes on volume; both are non-Anthropic
  families, so the DRIVER's judgment of the diff is cross-vendor for free (the PR reviewer adds
  another family only when `reviewer_vendor` differs from the lane's producer — see
  `.plinth/MODELS.md`). Race both on one spec for
  high-stakes work — sequentially, or one worktree per lane; never two lanes
  concurrently in one checkout (they share the working tree, and scope
  authorizes by path, not producer). Needs the `grok` / `codex` CLI installed + signed in; a missing CLI reports
  `unavailable`, never a silent Claude fallback. See `.plinth/MODELS.md`.
- Per-project knobs live in `.plinth/`: `config` (spec_path, exec_gated paths,
  round_budget, reviewer_vendor, audit_vendor/audit_model, advisor_vendor/advisor_model/
  advisor_model_max, tier2_extra — the config itself is off-limits to the driver, so
  these are yours alone), `protected-paths` (paths the driver must not edit —
  tool-blocked under a Claude driver; project-owned entries reviewed as normal project
  code), `AGENTS-project.md`
  (project-specific reviewer rules), `DRIVER-project.md` (project-specific driver notes).
  None is ever overwritten by `plinth update`.
- The DRIVER contract is a thin, pinned shell in BOTH `CLAUDE.md` and `AGENTS.md`, so
  whichever file your driver's CLI auto-loads (Claude→CLAUDE.md, codex→AGENTS.md,
  grok→both) delivers the driver role; it imports the shared rules and your
  `.plinth/DRIVER-project.md`. `plinth init`/`update` write both shells byte-identical —
  UNLESS a CUSTOM `CLAUDE.md` already exists (a pre-v4.4.0 project on update, or `init`
  into a repo that already had its own `CLAUDE.md`): the same protection preserves it with
  a loud NOTE to move its notes into `.plinth/DRIVER-project.md` and delete it, so nothing
  is lost. Until you complete that one-time migration the two shells are NOT byte-identical
  and a Claude driver still auto-loads your old `CLAUDE.md`; the CI floor verifies
  `CLAUDE.md` against the shell, so it fails until the migration is done — that failure is
  the reminder. The REVIEWER contract lives in `.plinth/reviewer.md`, which the review
  harness passes to the reviewer explicitly.
- `.plinth/NEEDS-HUMAN.md` is the blocked-on-you queue: the driver records
  what only you can supply (hashes, credentials, smoke runs, budget acks);
  the dashboard shows a red banner while it's non-empty.

## Quick start (first time on a project — follow exactly)
0. Once per machine (SETUP.md has details): install Claude Code (the resident
   ARCHITECT harness, and the audit seat), the grok CLI
   ([x.ai/cli](https://x.ai/cli), sign in — the WORKER seat, and the alternative
   resident driver), Codex CLI (`npm i -g @openai/codex`, sign in
   with ChatGPT — the reviewer seat), `brew install jq gh`, `gh auth login`.
1. `plinth init ~/Dev/<repo>`. It scaffolds the project and runs a GitHub
   preflight: creates the git repo if missing, offers to create the GitHub
   remote (answer y; pick **public** unless the account has GitHub Pro —
   private repos on the free plan cannot enable branch protection, which means
   nothing is ever *required* to merge), and reports branch-protection status.
   **Read every `NOTE:` line it prints.** Each one names an enforcement layer
   that is currently missing. A silent run means everything is wired.
2. Write the spec: open a fresh claude.ai chat, paste PLANNING-PROMPT.md (from
   the Plinth repo), work it into a SPEC.md. Paste that into the project,
   commit, push.
3. Connect Codex cloud review once: chatgpt.com -> Codex (GitHub App with repo
   access + review on PR open). It auto-loads AGENTS.md (the driver shell), whose
   role-scope block tells any reviewer — including this cloud review — to STOP and
   read `.plinth/reviewer.md` as its contract (Verdict policy + security-review
   rules), since the cloud review does not auto-load that file itself. That is how
   it arrives security-briefed; there is no separate "Codex Security" product.
4. After your FIRST PR (whenever it comes): confirm the `floor` and `checks`
   jobs appeared and that the Codex review commented. Then enable branch
   protection requiring those checks. (The Codex cloud review posts as PR
   COMMENTS — it exposes no status-check context, so it cannot be made a
   required gate; treat it as an advisory second stream of findings.) Exact
   steps in "Branch protection"
   below. From then on the merge gate is real. Until you've SEEN both fire,
   treat them as absent.

## Kicking off the driver — you have SPEC.md; now what?
Your driver's CLI auto-loads the driver shell (Claude → CLAUDE.md and expands the
rules import; codex → AGENTS.md; grok → both), which pulls in the plinth rules and
your `.plinth/DRIVER-project.md` notes and points at the spec — the driver knows the
whole contract before your first word. (Non-Claude CLIs follow the shell's explicit
"read `.plinth/plinth-rules.md` now" line rather than a mechanical import.) Your
kickoff prompt only selects the work:

- **Scoped start (recommended):** "Implement R1–R4 from SPEC.md." Small slices
  keep review rounds cheap and PRs reviewable.
- **Full run:** "Work through SPEC.md top to bottom; stop at anything
  irreversible." Fine for small specs; expect a long session.
- **Continuation:** "Continue: R5–R7." State the next goal, nothing more —
  verdict and gate state live on disk, so the driver needs no recap.

Planning happens twice, at different altitudes — don't conflate them:
- **WHAT to build** was planned in Claude.ai and frozen into SPEC.md before
  any driver session. The driver never re-litigates it.
- **HOW to build this slice** is planned by the driver, in-session, and
  approved by you ONCE before code. That is Rule 1 and Rule 4's boundary:
  "loop until verified" explicitly applies only *after the plan is approved*.

First minutes, what good looks like: it reads the spec and project notes,
then — Rule 1 — states its assumptions and a brief plan of attack (often via
plan mode) and waits for your approval. That approval is the one built-in
check-in. After your nod, Rule 4 governs: it loops until verified without
asking permission per step. Two failure modes, two citations: starts coding
without ever showing a plan → cite Rule 1; keeps asking permission after the
plan was approved → cite Rule 4.

Don't: paste the spec into the prompt (it reads the file); micro-instruct
after approving the plan (shape the work AT the approval, not during the
loop); answer design questions it should resolve against the spec — redirect
it there instead.

Session hygiene: prefer a fresh session per requirement slice over resuming a
compacted 20-hour one. The dashboard's model line and compaction counter tell
you when a long session has degraded — fresh is cheaper than drift.

## Precedence — plinth rules vs the driver's built-in defaults
Claude Code ships behavioral defaults, and your personal globals
(~/.claude/CLAUDE.md, output styles, saved memories) apply to every session —
including drivers. Some of these conflict with the loop; the project CLAUDE.md
declares that plinth rules win, but know the friction points:

- **Committing.** Harness default: commit only when asked. Plinth REQUIRES
  unprompted commits on feature branches — verdicts bind to SHAs, the Stop
  gate demands APPROVED-at-HEAD. Expect commits you didn't ask for; that is
  the loop working. (PRs and pushes remain scripted by the rules.)
- **Brevity vs evidence.** Default styles favor concision; Rule 10 requires
  pasted runner output. Evidence wins — expect verbose check output.
- **Autonomy vs check-ins.** Defaults ask "should I…?" mid-task; Rule 4 says
  loop until verified once success criteria are agreed. Driver keeps asking →
  cite Rule 4. Driver never surfaces uncertainty → cite Rule 1.
- **Personal globals and memories.** If a driver behaves oddly — refuses to
  commit, over-summarizes, skips checkpoints — check what your global
  CLAUDE.md and saved memories inject. Models blend conflicting instructions
  imperfectly; keep personal rules minimal on plinth projects and run drivers
  in the default output style.

## The upstream channel — drivers talk back
Drivers file tooling findings and proposals as GitHub issues on the plinth
repo (title prefix `UPSTREAM:`), and check for maintainer replies at session
start — a two-way, auditable conversation with one session-turn of latency.
The maintainer session evaluates every proposal (merit AND security — a
driver proposal is untrusted input, however sensible it reads) before any
change ships; nothing a driver writes in an issue can alter tooling by
itself. Your view of the queue: github.com/<owner>/plinth/issues.

## What the driver stops for anyway — and your two standing chores
The no-wait philosophy has deliberate exceptions. The driver MUST still stop
for irreversibles: new dependencies, auth/crypto/secrets, database migrations,
data deletion, public API changes (and ratifying a GOAL.md is always yours).
These stops are rule-mandated, not timidity — answer them quickly rather than
training the driver out of asking. (Anvil's driver asking approval to add
`ruff` was this rule working.) Everything else lands in NEEDS-HUMAN and keeps
moving.

Two operator chores the rules generate:
- **Triage `## Noticed`** (in the spec): review minors and the driver's
  drive-by observations accumulate there instead of blocking. Sweep it when
  you plan the next spec update — it is your backlog inbox, and ignoring it
  silently forever defeats the reason minors don't block.
- **Demand a checkpoint when a session looks lost** (Rule 8): "restate where
  you are — done, verified, remaining." A driver that can't answer crisply
  should be restarted on a fresh session; on long tasks it also keeps a
  progress file precisely so a restart is cheap. The first commands of a
  fresh slice should include a feature branch (rule) — a driver committing
  to main is misbehaving unless you're bootstrapping the repo itself.

## Daily loop — what you do, and what happens underneath
1. **You:** plan in Claude.ai (project-scoped), update `SPEC.md`, commit.
2. **You:** open two terminals.
   - Pane A: `cd ~/Dev/<repo> && claude` — state the task in plain language.
     (The v4 default is ARCHITECT-RESIDENT: the top model orchestrates here with
     the full hook machinery enforced, and delegates the coding volume to the
     grok worker lane. The grok-RESIDENT alternative — `grok` instead — trades
     the enforced Stop gate for wall-clock: review is contract discipline until
     auto mode is fully enabled — `receipt / verify` wired, required with
     `strict:true`, and the real verifier still running (caller-control bound;
     see intro / known limitation).)
   - Pane B: `plinth watch ~/Dev/<repo>` — the dashboard (below).
   *Background (Claude driver):* the moment the session starts, `session-start.sh`
   records the current commit (so the review gate knows whether this session
   created any), and `pulse.sh` begins appending one line per prompt/tool-call to
   `.plinth/session/events.jsonl`. That file is the dashboard's feed. Every
   Bash/Edit the model attempts passes through `guard.sh` first — destructive
   commands and protected paths are blocked at the tool level, including for every
   Claude subagent. These are `.claude/` hooks — and whether a NON-Claude driver
   executes them is PROBEABLE, not assumed: run `plinth hookprobe <grok|codex>`
   (shipped tooling; one small capped model call). It wires a marker for EACH of
   the four hook events Plinth enforcement uses (SessionStart, PreToolUse =
   guard, PostToolUse = pulse, Stop = review gate), drives the CLI once, and
   reports each event separately — a NOT-invoked event is certainly unenforced;
   an INVOKED event means the CLI ran the hook command (necessary, not
   sufficient — the real hooks also need Claude-shaped stdin JSON and
   CLAUDE_PROJECT_DIR). At release time grok 0.2.112 reported: NONE executed
   (receipt: docs/receipts/hookprobe-grok-0.2.112.txt)
   (its Claude-compat is instruction/flag-level — CLAUDE.md auto-load,
   `--allowedTools` naming). Vendor compat moves — re-run the probe after CLI
   upgrades; trust the probe, not vendor docs or this sentence. An all-four
   result makes local enforcement PLAUSIBLE — verify END-TO-END before relying
   on it (wire the real hooks, run one session, confirm the pulse feed appears
   and a guard block fires); a PARTIAL result leaves the missing events
   certainly unenforced; everything below is the FLOOR unless end-to-end
   verification passes. Under a non-executing driver you get
   no local guard, no
   session-start/pulse feed, and no Stop gate — it is bound by the driver rules it
   is told to follow (trusted to run the review loop) and, server-side, by branch
   protection's required checks (floor + checks — CI and tooling integrity; they do
   not verify the review verdict, and the cloud review is advisory comments). The
   adversarial loop is contract-bound for a non-Claude driver until the receipt
   check (auto mode, v4.7) is wired, required as `receipt / verify`, and protected
   with `strict:true` — and only when the real verifier still runs (caller-control
   bound: a PR can replace the caller with a green spoof of the same context name;
   see ci.yml HONEST BOUND). That is the server-side, driver-agnostic path for the
   gap; it is not an unforgeable name. Wiring the hooks into codex's own hook
   system is future work.
3. **The model:** implements, writes real tests, runs the project's checks, and
   pastes real runner output (Rule 10: its commentary is not evidence).
   **You:** watch Pane B, not the scrollback. Under a CLAUDE driver the live feed
   is full: the evidence line shows the last real test run and its exit code, the
   model line shows who is actually answering, and red guard-blocks mean the base
   deflected something. Under the grok-RESIDENT alternative the hook-fed lines are
   SILENT (its CLI does not execute `.claude/` hooks — per-CLI, probe with `plinth
   hookprobe`; grok 0.2.112: none [receipt: docs/receipts/hookprobe-grok-0.2.112.txt]) — Pane B still shows review rounds and verdicts
   (written by `review.sh`), the NEEDS-HUMAN queue, and branch state. Those are
   local files, and a hookless driver could write them — the dashboard is
   OBSERVABILITY, not a gate; what actually binds any driver is server-side:
   branch protection's required checks on the PR. For Rule-10 evidence under
   grok, read the session scrollback and the review verdicts instead of the
   evidence line.
4. **The model:** commits, then runs `./.plinth/review.sh`.
   *Background:* the script refuses to run on uncommitted work (verdicts bind
   to a commit SHA), diffs the branch against main, and classifies the diff into
   a **risk tier** (deterministic, version-pinned, not driver-writable). The tier
   routes review DEPTH:
   - **Tier 0** — inert docs/text only: APPROVED by the deterministic floor with
     NO model round (the CI floor scanners still run at PR). This is the one case
     where model review is skipped, and only because the classifier proved every
     changed file is an inert doc blob; any code, tooling, or spec would have
     bumped the tier.
   - **Tier 1** — ordinary code: standard adversarial review by the second model
     (the `reviewer_vendor` — Codex by default; also Claude or Grok) with the
     reviewer rules in `.plinth/reviewer.md`. Approvals bind directly in every
     mode: a resumed approval carries its warm first-pass full read, and a
     SCOPED verify (a fresh session used when the prior thread is too large,
     dead, or from a different vendor) reads the open findings plus the
     CUMULATIVE fix diff since the last full read — across the loop's sessions
     the branch is fully covered (the anchor round read everything up to the
     anchor; this session reads everything after it, with repo read access for
     context), though the verify session itself sees only the delta and the
     open findings; the full diff is sent only when no usable anchor exists
     (anchor commit object missing, or legacy pre-v4.6 state). A rebase that
     keeps the old anchor object alive is NOT detected — the anchor is
     existence-checked only; the ancestry guard is backlog (see `## Noticed`).
   - **Tier 2** — high-consequence surface (tooling, spec, security, migrations,
     public API, dependencies, weakened tests): full review; a non-fresh
     approval is required to take a clean-slate full pass (a warm reviewer can't
     approve its own checklist) — **every** non-fresh Tier-2 approval requires
     that confirmation (v4.7+ retired the once-per-loop skip). v4.8.1 demotes non-fresh Tier-2 APPROVED to UNBOUND before launching confirmation
     so ship/Stop fail closed on an interrupted confirmation; re-run recovers.
   The verdict comes back as machine-readable JSON in `.plinth/session/review/`
   — **APPROVED**, **CHANGES_NEEDED**, or **UNBOUND** (non-fresh Tier-2 approval
   waiting for clean-slate confirmation; ship/Stop treat as non-APPROVED). Exit
   code 0 = approved after any required Tier-2 confirmation for this run has completed,
   1 = fix findings (the model fixes, commits, re-runs; re-review rounds reuse the
   same reviewer session with just the incremental diff, or — if that session is
   too large or dead — a SCOPED verify round that reads
   the open findings plus the cumulative fix diff since the last full read; Tier-1
   verify approvals bind directly, Tier-2 ones require clean-slate confirmation
   every time (UNBOUND until confirmation succeeds, v4.8.1). A reviewer-vendor swap mid-loop instead forces a FRESH full
   round: the recorded full read belongs to the previous vendor, and coverage credit
   does not transfer between models), 2 = the review DID NOT RUN. A hard `round_cap` circuit breaker (config
   knob: opt-in — unset or 0 means no cap; set a positive integer to cap) stops a loop that has not converged — exit 2,
   surface to the human. Operator env overrides — `PLINTH_REVIEWER_VENDOR`,
   `PLINTH_REVIEWER_MODEL`, `PLINTH_AUDIT_VENDOR`, `PLINTH_AUDIT_MODEL`,
   `PLINTH_ROUND_CAP` — beat the ratified-base config for ONE run (e.g. a vendor's
   credits run out mid-loop); they are OPERATOR-ONLY (a driver setting them is
   tampering-class), every override is announced and recorded in session state
   (`verdict.json` and the per-round `usage.jsonl` ledger) and must be listed in
   the PR body's audit summary. That disclosure IS cross-checked automatically
   wherever `receipt / verify` is wired, required, protected with `strict:true`,
   **and the real verifier still runs** (caller-control bound — a PR can replace
   the caller so the verifier never executes; see ci.yml HONEST BOUND): the receipt
   carries the override ledger and the verifier holds the PR body to EXACT
   tuple-set equality with it, rejecting a missing OR a phantom disclosure line
   (auto mode, v4.7+). Where those conditions do not all hold, the duty stays
   contract-bound and the operator audits `usage.jsonl` directly. A vendor swap never resumes the previous vendor's
   thread — and, since v4.7, forces a fresh full round rather than a scoped verify.
   *Background, enforcement (Claude driver):* if the model tries to end its turn
   with commits but no APPROVED verdict at the current HEAD, the `.claude/` Stop
   gate (`review-gate.sh`) refuses and sends it back with instructions. A driver
   whose CLI does not execute the Stop hook (per-CLI — `plinth hookprobe`; grok
   0.2.112 reported no execution; receipt: docs/receipts/hookprobe-grok-0.2.112.txt) has nothing LOCAL forcing it to review — it is bound
   by the driver rules (trusted to run the loop) and, at merge, by the required CI
   status checks that branch protection enforces. Those required checks verify the
   floor and tooling integrity, NOT the review verdict — and the Codex cloud review
   cannot close that gap (it posts comments, not a requirable status check). Under
   the grok-RESIDENT alternative the review loop is therefore contract-bound driver
   discipline wherever the receipt check is not fully enabled; the server-side check
   of `review.sh`'s own APPROVED-at-HEAD verdict — `receipt / verify` (auto mode,
   v4.7+) — is what closes it once wired into `ci.yml`, required in branch
   protection with `strict:true`, and still executed by the real verifier
   (caller-control bound; see intro and ci.yml HONEST BOUND).
5. **The model:** opens the PR. *Background:* `ci.yml` fires the floor
   (gitleaks secrets scan, semgrep SAST, OSV dependency scan) and the
   stack-detected checks; Codex cloud review posts on the PR if the repo is
   connected (SETUP step 4).
6. **You:** glance at the consolidated checks, merge. GitHub is the audit trail.

## The dashboard (`plinth watch`)
Run it in any second terminal or tmux split; it repaints within ~1s of session
activity (change-detection on the event feed, 10s heartbeat for the clocks;
ctrl-c to quit; `--once` prints a single frame). A "no event feed" banner is
NORMAL under a driver whose CLI does not execute `.claude/` hooks (per-CLI —
`plinth hookprobe`; grok 0.2.112: none [receipt: docs/receipts/hookprobe-grok-0.2.112.txt]; if the probe reports PostToolUse INVOKED,
investigate — the same banner may mean broken wiring instead): the frame reduces to
branch @ head, review verdict, and the NEEDS-HUMAN queue (observability from
local files — the binding gate for any driver is branch protection, not this
dashboard). If you are driving with CLAUDE and still see that banner, the pulse
hook isn't wired — `plinth update` will say so too.

```
 ◤ PLINTH WATCH fix auth token refresh on 401          <- the task (latest human prompt)
   feat @ c74d472 · claude-fable-5 · session 46m       <- branch @ commit · model · elapsed
 ✓ PLAN      6m 58s    175.5k tok                      <- finished stages: time + tokens
 ▶ REVIEW    11m 40s   351.9k tok                      <- ▶ = current stage
 tokens   20.6M  (in 16.8k · cache-write … · out …)    <- cumulative, split
 burn     59.2k/min  ▃▂▁▁▁▁▁▇▁█▃▂                      <- fresh+out per minute, last 12 min
 review   APPROVED · round 3 @ 964f178 ≠ HEAD …        <- verdict + does it match HEAD
 evidence python3 -m pytest -q → exit 0 · 16m ago      <- last real test run (Rule 10)
 signals  guard blocks 1 · compactions 1 · subagents 1
 now      Bash ./.plinth/review.sh · 11m ago           <- what it's doing right now
```

What to act on: the **model** changing mid-task (Fable→Opus fallback — quality
and limits changed); **evidence** old or a red exit code while the model claims
success; **review** showing `≠ HEAD` (work continued past the approval — a
re-review is required and the gate will insist); **guard blocks** going red
(look at what was attempted: `jq 'select(.event=="guard_block")'
.plinth/session/events.jsonl`); a **burn** spike you didn't expect.
Stage caveat: REVIEW/PR transitions are hard events; PLAN/IMPLEMENT/VERIFY are
heuristics from tool traffic and legitimately bounce.

Once the session opens a PR, a **CI row** appears under the pipeline with the
live check rollup (`✓ passed  ✗ failed  ◌ pending`, red/yellow/green) pulled
from GitHub each repaint. `PLINTH_CI_STATUS='{"pass":N,"fail":N,"pending":N}'`
overrides the source for non-GitHub CIs.

Prefer one line inside Claude Code instead of a second pane? Wire the
statusline (opt-in, in project or user settings.json):

    "statusLine": { "type": "command", "command": "plinth statusline" }

It shows the current stage + time in stage, the verdict vs HEAD, and red
guard/gate alerts. Token economics stay on `plinth watch`.

## Multi-instance wallboard (`plinth dash`)
`plinth watch` is one project in a TTY. When you have several Plinth checkouts
going, use the HTML wallboard:

```
plinth dash            # http://127.0.0.1:7348/  (loopback only)
plinth dashboard       # alias
plinth dash --port 7349  # pick a free high port (1–65535)
plinth dash --snapshot   # print the same JSON the UI polls (offline / CI)
```

Requires **python3** on PATH to serve the UI (`--snapshot` is bash+jq only).
The server binds **127.0.0.1 only**, is read-only, and serves a single static
page plus `GET /api/snapshot`. The server keeps a **single-flight snapshot body
with a 2.5s TTL** (≥ the 2s UI poll) so steady-state polling reuses one builder
result instead of re-shelling every tick; concurrent callers share that flight.
Observed burn/tokens come from the last **300 lines** of the Claude transcript
when reachable; burn_per_min is the sum of all token categories in that tail
with timestamps in the last **5 minutes**, divided by 5. Session task /
session age use a **`tail -n 10k`** of `events.jsonl` then a stream (no full-file
`wc`); `session_secs` is set only from the **first** `SessionStart` still inside
that window for the active SID (resume re-emits are ignored; otherwise null).
A review round is
RUNNING when a `request-N` outruns the verdict **and** either there is no
`last-error`, or the request file is **strictly newer** than `last-error`.
Subsecond newer requires **python3** (nanosecond mtime); without it, bash
`-nt` is whole-second on some platforms and same-second ties stay infra-error
(not RUNNING). It does **not** replace `plinth watch`.

**Discovery** (first match wins):

1. `PLINTH_DASH_ROOTS` — colon-separated absolute paths (useful for tests).
2. `~/.config/plinth/dashboard-projects` — one absolute path per line (`#` comments; `~/` expanded).
3. **Default:** every `~/Dev/*` directory that has a `.plinth/config`.

Each card shows project path, branch @ head, review verdict / round / stale vs
HEAD, time since `events.jsonl` activity (when a pulse feed exists), NEEDS-HUMAN
open/blocking counts (click the orange chip to list open items from
`.plinth/NEEDS-HUMAN.md`), a **feedless** flag when there is no event feed
(typical for non-Claude drivers), **models** (live driver/reviewer plus config
seats for audit/advisor), **phase timing** (coarse seconds from event gaps +
review `usage.jsonl` durations: coding / research / reviewing / advising / ci /
planning / shell), and **observed** driver burn when a Claude transcript is
reachable.

**Vendor plan quota (overall weekly)** is polled from official CLIs — not scraped
web UIs — into a top-level `quota` object (~15 min cache at
`~/.config/plinth/dash-quota.json`; `PLINTH_DASH_QUOTA_TTL`, `PLINTH_DASH_QUOTA=0`
to disable). Claude: `claude -p /usage --output-format json` (week-all-models %
used + reset text). Codex/grok currently report `no_headless_usage_surface`
until a stable headless `/status` or `/usage` exists. When two samples ≥10 min
apart exist, the UI projects time-to-100% weekly usage for comparison with the
reset clock.

Smoke (canary CI): `shared/dashboard/smoke-snapshot.sh` — offline `--snapshot`
fixture matrix (with `PLINTH_DASH_QUOTA=0`), a node unit test of pure card HTML
(error tone / no-review suppression / NEEDS-HUMAN chip / phases), and a
short-lived loopback HTTP check (`/`, `/api/snapshot`, POST 405) with process
cleanup.

## When something blocks — who acts
- `review.sh` exit 1 (CHANGES_NEEDED): normal. The model fixes, commits, re-runs.
- Exit 2, "working tree is dirty" / "HEAD unchanged" / "empty diff": loop
  discipline — the model must commit (or actually change something) first. Its
  problem; it will be told.
- Exit 2, infrastructure ("codex CLI not found", "codex exec failed", schema
  missing): **yours.** Fix the pipeline (usually `codex` login or `plinth
  update`), then tell the model to re-run. The session gate opens automatically
  after an infra failure so the session is never trapped by a broken reviewer.
- "NOTE — last round cost N input tokens": the budget warning. Advisory only —
  the loop continues; spend is on the dashboard (`review` line's Σ). Interrupt
  if it looks wrong; nothing waits for you.
- "AUDIT DISAGREEMENT" after an approval: the cross-vendor audit (config
  `audit_vendor`, on every Tier-2 approval) found blocking issues the primary
  reviewer missed. The verdict stands; adjudication is yours. "audit UNAVAILABLE"
  means the configured auditor couldn't run — recorded, non-blocking; the primary
  review remains the gate.
- "PLINTH REVIEW GATE:" when the model tries to stop: the gate working. It runs
  the review or it doesn't finish. (Anti-trap: releases after
  PLINTH_GATE_MAX_BLOCKS blocks, default 10 — and every release is a red
  `gate releases` count on the dashboard, so nothing escapes silently.)
- "PLINTH BLOCKED:": the guard stopped a destructive command or a protected
  path. If the operation is genuinely intended, run it yourself.
- **Never edit or delete anything under `.plinth/session/`** — not to unblock,
  not to tidy. If the loop appears wedged, that is a Plinth bug: fix Plinth,
  not the instrument (see CHANGELOG v3.9 for the precedent).

## Branch protection (the merge gate) — what it is and how to enable it
Without branch protection, CI is advisory: checks run, turn red, and the merge
button still works — for you and for any agent with push access. Branch
protection is the GitHub setting that makes named checks MANDATORY: a PR into
`main` cannot merge until those exact checks report green. It is the one
enforcement layer that survives anything done on a laptop, which is why Plinth
treats it as the floor of the whole system. (Private repos need GitHub Pro;
public repos get it free — `plinth init` probes and reports your state.)

Enable it AFTER the first PR, not before: GitHub identifies checks by the names
they report, and those names exist only once they've run. Configuring guessed
names that never report leaves every future PR blocked forever.

UI route, once the first PR shows its checks:
1. Repo -> Settings -> Branches -> "Add branch protection rule".
2. Branch name pattern: `main`.
3. Tick "Require status checks to pass before merging" (add "Require branches
   to be up to date" if you want rebase-before-merge discipline).
4. In the search box, pick EVERY floor context and the checks context. GitHub
   names a required check by its JOB name, NOT the workflow name — for a
   reusable-workflow job the context is `<caller-job> / <reusable-job>`. With the
   scaffold's `floor` and `checks` caller jobs that is:
   `floor / secrets`, `floor / sast`, `floor / dependencies / osv-scan`,
   `floor / harness`, and `checks / checks` (or just `checks` if you replaced the
   reusable checks call with a direct-steps job). There is NO `CI / ` prefix. The
   floor is FOUR independent required contexts, not one: any you omit stays
   advisory. The Codex cloud review will NOT appear in this list — it posts PR
   comments, not a status check, so it cannot be required here.
5. Create. From then on red = unmergeable, for humans and agents alike.

CLI route (same contexts; use `checks` alone if your checks job is direct-steps):

    gh api -X PUT repos/OWNER/REPO/branches/main/protection --input - <<'JSON'
    {"required_status_checks":{"strict":false,
      "contexts":["floor / secrets","floor / sast",
                  "floor / dependencies / osv-scan","floor / harness",
                  "checks / checks"]},
     "enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null}
    JSON

Verify either route the same way: open a trivial PR and confirm the merge
button is disabled until everything is green.

## The smoke runner — execution evidence without waiting on a human
The Smoke workflow (per-project smoke.yml) runs the set-once `smoke_cmd` from
`.plinth/config` on YOUR hardware via a self-hosted GitHub runner, on every PR.
Receipts upload as artifacts; RUNTIME findings get burned down automatically
instead of queuing on you. One-time setup per machine+repo (run as yourself,
not root):

    mkdir -p ~/actions-runner-<repo> && cd ~/actions-runner-<repo>
    ver=$(gh api repos/actions/runner/releases/latest -q .tag_name | tr -d v)
    curl -sL -o r.tar.gz "https://github.com/actions/runner/releases/download/v${ver}/actions-runner-osx-arm64-${ver}.tar.gz"
    tar xzf r.tar.gz && rm r.tar.gz
    ./config.sh --url https://github.com/<owner>/<repo> \
      --token "$(gh api -X POST repos/<owner>/<repo>/actions/runners/registration-token -q .token)" \
      --name "$(hostname -s)" --labels plinth-smoke --unattended
    ./svc.sh install && ./svc.sh start    # launchd service; survives reboots

Security: a self-hosted runner executes PR code on your machine. Keep the repo
private (no fork PRs can reach it), and remember the guard/review/floor already
gate what lands on branches. Make the smoke job a required check only after
it has run green with a real smoke_cmd.

## Auto-research mode (GOAL.md) — for numeric rubrics only (e.g. Anvil scores)
1. `plinth goal <repo>`; have the driver draft the metric, constraints, action
   catalog. 2. **You ratify** (set `STATUS: RATIFIED`) — agents never self-ratify.
3. Add the eval-script pattern to `.plinth/protected-paths` (a Claude driver's
   guard then blocks edits to it at the tool level; for every driver the reviewer
   checks GOAL runs for metric-gaming, so an eval-script change to inflate the score
   is caught in review). 4. Have Codex attack the rubric for gameability first.
5. Let the driver loop. It exits into the normal review -> PR -> CI path, where the
   reviewer explicitly checks for metric gaming.

## Hard blocks (don't rely on the model behaving)
- Guard hook: common destructive commands (an enumerative, heuristic pattern set —
  bare and prefixed forms like `sudo rm -rf` are caught, but a command hidden inside a
  shell wrapper's quotes such as `bash -c "..."` is NOT — deliberate obfuscation evades
  text matching by design), secret paths, and anything matching `.plinth/protected-paths`
  are blocked at the tool level — for every Claude subagent too (the guard is a `.claude/`
  hook, so it binds Claude drivers/subagents; whether another driver executes it is
  probeable — `plinth hookprobe <vendor>`; grok 0.2.112 reported no execution [receipt: docs/receipts/hookprobe-grok-0.2.112.txt]). The guard is a
  CLIENT-SIDE tripwire, not the security boundary: CI required-checks and branch protection
  are the hard layers.
- Deny-ship tripwire (same hook): the plain `gh pr create`/`gh pr merge` command is
  refused unless the branch has an APPROVED review at HEAD. Like every `.claude/` hook it
  fires only under a Claude driver, or a CLI verified END-TO-END to run the guard —
  a positive `plinth hookprobe` alone shows invocation, not enforcement (grok 0.2.112
  reported no execution [receipt: docs/receipts/hookprobe-grok-0.2.112.txt]). Under a non-executing
  driver this hook does NOT fire — their merge gate is branch protection's required
  checks (floor + checks — CI and tooling integrity; the review verdict has no
  server-side verifier until `receipt / verify` is wired, required, and protected
  with `strict:true` **and** the real verifier still runs — caller-control bound;
  the cloud review is advisory comments). Deliberately-quoted obfuscation is out of
  scope (see above); the merge gate proper is branch protection's required status checks.
- Review gate (`.claude/` Stop hook, Claude driver only): a session that created
  commits cannot end its turn until review.sh records APPROVED at HEAD. Scoped to
  feature branches and commit-making sessions; releases loudly on review
  infrastructure failure or after PLINTH_GATE_MAX_BLOCKS blocks (default 10), so it
  can't trap a session. A driver whose CLI does not execute the Stop hook (per-CLI —
  `plinth hookprobe`; grok 0.2.112: no execution [receipt: docs/receipts/hookprobe-grok-0.2.112.txt]) has no
  local hard block; the server-side hard gate is branch protection's required checks
  (floor + checks), and the driver is trusted to run the risk-tiered review loop — unless
  `receipt / verify` is wired, required, and protected with `strict:true` **and** the
  real verifier still runs (caller-control bound: a PR can replace the caller with a
  green spoof of the same context name — ci.yml HONEST BOUND). That combination is what
  puts its APPROVED-at-HEAD verdict under a server-side verifier (auto mode, v4.7+).
  Where those conditions do not all hold, the verdict still has no reliable
  server-side check. Every gate release (a Claude driver ending its turn without
  approval, e.g. on a broken review pipeline) is logged as a `gate_release` event
  the dashboard shows in red.
- Branch protection: ALL FOUR floor jobs (secrets, sast, dependencies/osv-scan,
  harness) + `checks` required to merge (requires public repo or GitHub Pro; the
  preflight reports which state you're in AND names any missing required
  context). The cloud review is advisory; enabling auto mode for the review
  verdict means requiring `receipt / verify` **with `strict:true`** (and accepting
  the caller-control bound: the context name alone is not unforgeable).

## When models change (they will)
- New reviewer: set `reviewer_vendor` (codex | claude | grok) in `.plinth/config` —
  each runs its own CLI and the resume threshold scales per vendor automatically.
  Staying on codex but changing its model? Edit `~/.codex/config.toml` instead. (env
  `PLINTH_RESUME_MAX` still overrides the threshold if you ever need to.)
- New driver: launch whichever vendor CLI you want — claude, codex, or grok — in the
  project; the byte-identical CLAUDE.md/AGENTS.md driver shell gives each the driver
  role (see Commands). Swap the Claude MODEL with `/model`. Configure the advisor the
  driver consults via `advisor_vendor`/`advisor_model`/`advisor_model_max`.
- New recommendations ship in `shared/MODELS.md`: `git -C <plinth> pull`, tag, then
  `plinth update` each project when YOU choose. Nothing propagates silently.
- **Plinth product changes (`shared/`, `bin/`) — changelog fragments (transition).**
  Parallel branches that each edit `VERSION` and the top of `CHANGELOG.md` collide
  (same next number, same insert point). Fragments fix that: unique files under
  `changelog.d/`, number computed at release. **Recording rule (exactly once per
  change):** either the legacy dual-write (new top `CHANGELOG.md` section + matching
  `VERSION` bump on that PR) **or** a single `changelog.d/<slug>.md` fragment that
  the same ship consumes via `plinth changelog-collate` (so the merged PR carries
  the new VERSION/CHANGELOG), never both. Dual-write still matches the still-ratified
  project-notes rule; fragment+collate in one ship also produces a matching pair.
  Fragment-only PRs (no collate, no VERSION bump) wait on the follow-up that switches
  review/CI + project notes. **Bootstrap exception for landing the mechanism itself:**
  the collate feature is recorded as a bullet under the existing `v4.7.0` section with
  `VERSION` left at `4.7.0` and no pending fragment — a deliberate one-time exception
  so introducing the serial-work fix does not itself race on VERSION. Ordinary product
  PRs after this land do not inherit that exception. See `changelog.d/README.md`.

## Watch list
- **First PR per repo**: confirm the Codex review actually posts (connection
  is per-repo, SETUP step 4) and enable branch protection once the check names
  are visible.
- **Fable 5 availability** (standing; export-control volatility, credits-only, no
  automatic fallback): if access lapses, move the advisor seat to GPT-5.6 per the
  v4 contingency in `.plinth/MODELS.md`.
- **GPT-5.6 eligibility**: GA landed July 9, 2026 (per-account; Codex CLI >=
  0.144.0). VERIFIED 2026-07-25 on the maintainer's account: plain `gpt-5.6` is
  REJECTED ("not supported when using Codex with a ChatGPT account") and
  `gpt-5.6-sol` WORKS — pin the `-sol` name, not the bare one. Probe before
  believing either way, and probe CAREFULLY: `codex exec` exits **0** both on a
  hard model rejection and on "Not inside a trusted directory" (without
  `--skip-git-repo-check`), so a naive check reports a rejected model as working.
  Same hazard as grok printing "You are not authenticated." on exit 0.
- **The worker seat is not a config knob.** Nothing in `.plinth/config` selects it:
  the worker is the `grok-implementer` subagent plus driver discipline. Readiness is
  `.plinth/lane-guard.sh preflight grok`. Upstream #19 (the sensitive-path snapshot
  stalling minutes on any repo with `node_modules`/`.venv`) is FIXED in this release —
  the per-path fork storm is replaced by one bulk ERE filter, measured 232s -> 0.43s on
  25k ignored files with byte-identical output. #32/#43 resolved in v4.8.1
  (Write-tool + delegation receipt + canary). Treat lane reports as claims under Rule 10.
- **Fable 5 back on plans**: Anthropic says "when capacity allows" — recheck before
  buying credit bundles.
- Verify on first run: the hooks schema; scanner action tags in `plinth-floor.yml`.
  (`codex exec` flags — sandbox, --json, resume, --output-schema — verified
  against codex-cli 0.142.5 in v3.6.)

## Next (v4.8) — make the worker seat real, then split the reviewer tiers
Ratified 2026-07-25, in this order. The ordering is the point: items 1 and 2 come
first because item 3 is meant to be BUILT through the lane, and building it through
a lane that stalls or silently self-implements would defeat the exercise twice.

1. **Upstream #19 — the lane-guard stall. RESOLVED in v4.7.1.** `sens_snapshot`
   classified each enumerated path with a `printf | grep` pair PER PATTERN, so cost was
   O(ignored files x patterns) in PROCESSES — certeus measured ~6 minutes across ~28,000
   files before the lane ever reached grok. The fix is a bulk ERE prefilter: one
   `grep -E -f` running the same pattern set (`active_pats` plus the builtin secret
   constants) over the whole list, with `sens_match` still run on every survivor as the
   sole classification authority, so the filter can only ever be a SUPERSET. Measured
   232s -> 0.43s on 25k ignored files, byte-identical output.
   NOTE, because the original plan here was WRONG: this deliberately does NOT push
   pathspecs into `git ls-files`. The enumeration was never the cost (~31ms), and
   `.plinth/protected-paths` entries are `grep -E` REGEXES, not git pathspecs — a
   pathspec-derived candidate list would be faster AND silently blind to any path that
   is sensitive only by project policy. The full ignored listing is retained: that IS
   the security property.
2. **Upstream #32 / #43 — delegation CHECKABLE + Write-tool. RESOLVED in v4.8.1.**
   Write-tool project-local prompt + `lane-guard.sh delegation` + canary.
3. **Per-tier reviewer VENDORS.** `reviewer_vendor` is a single knob read BEFORE the
   risk tier is known, so today tier1/tier2 can only differ by MODEL within one vendor
   — and with codex offering exactly one usable model here, they cannot meaningfully
   differ at all. Add `reviewer_vendor_tier1` / `reviewer_vendor_tier2` resolved AFTER
   risk classification, each with its own model, so Tier 1 can run a fast cheap vendor
   and Tier 2 the deepest one. Keep the audit vendor different from BOTH.

**Auto mode is an ordering, not a switch.** Enabling the receipt gate requires, in
sequence: merge v4.7 → refresh the instrument to v4.7+ (a pre-v4.7 instrument mints no
receipt) → wire the `receipt` job into `ci.yml` → add `receipt / verify` to branch
protection **with `strict:true`**. Requiring the context before the refresh fails every
PR closed. Caller-control bound: requiring the context name alone does not prove the real
verifier ran (a PR can replace the caller — ci.yml HONEST BOUND).

**Audit-seat rule, refined.** The auditor must differ from whoever PRODUCED the diff,
not merely from the reviewer. While the driver types directly, `audit_vendor = grok`
keeps it independent; once the grok lane carries the volume, that becomes
`claude`/`opus`. Evidence for taking the seat seriously: across the v4.7 loop the
cross-vendor auditor raised a blocking finding the primary reviewer had missed in
**three of three** audits, including one sharper than the driver's own note on the
same code.

## Your role, in one paragraph
Write the spec. Stand up the gates (init preflight + first-PR checklist). Then
read the dashboard, not the transcript, and let the machinery run. The trust
order when anything conflicts: deterministic floor (CI) > cross-model review >
driver self-report — `verdict.json` and runner output are evidence; the model's
summary is commentary. You intervene for exactly three things: infra failures
(exit 2), guard blocks you actually intended, and merges.

## Noticed
Non-blocking findings and drive-by observations — the backlog inbox (see
"Triage `## Noticed`" above). Fix in `shared/`/`bin/` product sources, never in
installed copies.

- **`plinth dash` backlog (v4.8 review):** (a) ThreadingHTTPServer still allows
  unlimited concurrent *caller threads* (builders are single-flight). (b) a
  discovered path with `.plinth/config` but no git repo paints branch
  `detached` / head `-` rather than "git unavailable". (c) 10k-line events cap
  is not a byte cap; transcript mktemp/tail failure modes; config CRLF/whitespace
  discovery; `sha_match` min-length; smoke port cleanup via lsof (not only the
  spawn group); failing-builder stderr is buffered fully before 2k truncation;
  `PLINTH_DASH_SNAPSHOT_BIN` / `PLINTH_DASH_PORT` / `PLINTH_DASH_DEV_ROOT` env
  knobs are lightly documented; fail-server smoke port is SRV+1 without probe;
  serve-mode `json.loads` accepts any JSON (not only a snapshot object) before cache;
  cardHTML interpolates numeric burn/token fields without esc() (local-data hardening).
- **The `codex exec resume -m` receipt evidences ACCEPTANCE, not BEHAVIOR**
  (`docs/receipts/codex-exec-resume-model-0.145.0.txt`). It captures `--help` listing the
  flag, unlike the hookprobe receipts which capture the behavior they claim. If codex ever
  accepted-but-ignored `-m` on a resumed thread, an override would be recorded and disclosed
  as APPLIED while the round ran on the thread's original model — a dishonest disclosure
  trail. Wants a behavioral probe: two resumed rounds with different `-m` values, assert the
  recorded model differs. Raised by the primary reviewer (v4.7, new-loop round 1).
- **The receipt workflow's REAL-NETWORK behaviour is still unexercised**
  (`.github/workflows/plinth-receipt.yml`). Fixture (9d) now extracts the workflow's own
  `run:` blocks and drives them end-to-end — verifier fetch, notes fetch, base-tip
  resolution, the `gh` TOCTOU re-check, the event guard, and the malformed-pin paths — so
  the GLUE LOGIC is covered. What remains uncovered is what only a real PR can exercise:
  fetching a commit from GitHub over the network (the fixture substitutes a local
  `url.insteadOf` rewrite), private-repo/PAT visibility of the pinned plinth source, and
  the real `gh api` response shape. Wants a documented RUNTIME receipt from the first PR
  that runs the check for real.
- **`plinth advise` still reports every failure as "CLI missing or not signed in"**
  (`bin/plinth` `run_advise`, all four vendor branches). v4.7 fixed the wiring bug
  that this message was masking, but the mask itself remains: each branch is
  `<cli> ... 2>/dev/null || { echo "$unavail"; ... }`, so a future flag change,
  auth error, or model rejection is still reported as an absent CLI. That is what
  made the variadic-prompt bug invisible for a full release. Fix: capture stderr
  and surface its tail in the unavailable line (advise is non-blocking, so there is
  no reason to hide the cause). Found in the v4.7 self-review pre-flight.
- **Every seat-swap path re-anchors coverage except a swap that lands on a fresh
  round anyway** (`shared/.plinth/review.sh`, #26 fix). The vendor check compares
  only the IMMEDIATELY preceding round's vendor, which is sound today because the
  per-loop markers reset together and only fresh rounds write the anchor. If a
  future change ever writes `lastfullread` from a non-fresh round, or persists it
  across loops, that transitivity argument silently breaks. A vendor-stamped anchor
  file would make the invariant local instead of global. Not fixed: it would add a
  parse format for a property nothing currently violates.

- **guard.sh: protected-path loops fail open on heredoc temp failure**
  (`shared/.claude/hooks/guard.sh`, both pattern loops). If Bash cannot create
  the heredoc temp file, the loop is skipped and the hook still exits 0 —
  project protections AND the builtin `.plinth/session/` protection silently
  off. Reproduced under a non-writable TMPDIR (v4.5.0 refresh review, round 1).
  Fix: temp-create preflight or status-checked input, plus failure-injection
  coverage.
- **guard.sh: unreadable/invalid protected-path policy fails open**
  (`shared/.claude/hooks/guard.sh` policy read). `grep ... || true` discards an
  unreadable policy; an invalid pattern makes `grep -Eq` return 2 inside `if`,
  treated as no-match — the protected write is then permitted despite MANUAL's
  tool-level-blocking claim. Fix: validate readability, node type, and each
  regex before use (as lane-guard does). (Round 1, same review.)
- **guard.sh: secret denylist omits `*.pem`/`*.key`**
  (`shared/.claude/hooks/guard.sh` secret classes vs `templates/.gitignore`).
  Bash and Edit/Write writes to e.g. `server.pem`/`deploy.key` pass (both
  reproduced). Align the hook's denylist with the gitignore's declared secret
  classes. (Round 1, same review.)
- **review.sh: dirty-tree check loses the `git status` exit status**
  (`shared/.plinth/review.sh` porcelain enumeration via process substitution).
  If status enumeration fails, the loop sees no records, `dirty=0`, and review
  proceeds as if clean. Capture and validate the producer status; add
  failure-injection coverage. (Round 1, same review.)
- **review.sh: ratified-base probes conflate producer errors with absence**
  (`shared/.plinth/review.sh` — `git cat-file -e` probes for base config
  (~line 114), base project rules (~line 231), and the reviewer contract
  (~line 386); `git diff --name-only` for tooling-path detection (~line 351)).
  A probe ERROR currently reads as "absent", enabling working-tree fallback for
  config/rules/contract, and a diff error reads as "no tooling paths", which can
  leave a forged Tier-0 classification in force. Distinguish absence (rc 1)
  from failure (rc >= 2 / 128) and fail closed; existing tests cover absence
  only. (v4.5.0 refresh review, round 3 sweep.)
- **review.sh: porcelain `-z` rename records are mis-parsed**
  (`shared/.plinth/review.sh` dirty-tree loop, ~line 61). A rename/copy emits
  its second pathname as a separate NUL record with no `XY ` prefix, but the
  loop strips three bytes from every record — a staged rename from a short
  name (e.g. `a` → `.plinth/NEEDS-HUMAN.md`) can exempt the destination and
  truncate the source record to empty, permitting review of a dirty index.
  Parse rename/copy continuation records explicitly; add a regression test.
  (v4.5.0 refresh review, round 6.)
- **lane-guard: sensitive-directory MODES are not snapshotted**
  (`shared/.plinth/lane-guard.sh` `sens_snapshot`, ~line 194). The snapshot
  records sensitive files and symlinks but not the modes of the sensitive
  DIRECTORIES themselves (`secrets/`, `credentials/`, `.ssh/`, `.aws/`, …), so
  a fallible lane that widens a directory's permissions without changing any
  file record passes `scope`. Record directory modes in the snapshot and
  compare them; extend the canary beyond the regular-file `.env` case.
  (v4.5.0 refresh review, round 9.)
- **review.sh: auditor isolation is overclaimed for codex/agy**
  (`shared/.plinth/review.sh` ~line 252). The comment says an empty cwd means
  the auditor "CANNOT" read the repository, but codex's `read-only` sandbox
  prevents writes while permitting filesystem reads — cwd merely hides the
  path. Either enforce the isolation or reword the claim (overclaiming is this
  repo's worst defect class). (v4.5.0 refresh review, round 11.)
- **Lane + auditor temp files: SNAP/OUT cleanup backlog** (SPEC is cleaned after
  CLI in v4.8.1; residual is SNAP/OUT and interrupted pre-invocation residue in
  `shared/.claude/agents/*-implementer.md` temps and
  `shared/.plinth/review.sh`'s per-audit `mktemp -d`). Prompt/output data and
  snapshot metadata accumulate under the system temp dir; add a post-report /
  post-audit cleanup step. (Round 11, minors.)
- **review.sh: verify/resume anchors are existence-checked, not ancestry-checked**
  (`lastfullread` and `prev_sha`: `git cat-file -e` only). After a rebase the anchor
  commit can still exist while no longer being an ancestor of HEAD, so the
  "cumulative fix diff" can diff unrelated trees. Add a `git merge-base
  --is-ancestor` guard routing to the full-diff fallback. (v4.6 round 1, minor —
  pre-existing pattern, hardening backlog per the phase charter. Round-13 grok
  audit escalated the DOCS half — MANUAL/CHANGELOG/verify-prompt claimed the
  fallback fires "after a rebase" — as an overclaim; the claims were corrected
  in v4.6.0, the code guard itself remains backlog.)
- **Leading-zero octal footgun in numeric knob parsing** (pre-existing:
  ROUND_BUDGET, RESUME_MAX use digit-only case checks; a value like `08` then
  crashes bash arithmetic as invalid octal). round_cap now normalizes with
  `$((10#...))`; apply the same to the sibling knobs. (v4.6 round 10, minor.)
- **v4.6 canary gaps (round 6 minors):** no fixture for a NON-NUMERIC
  PLINTH_ROUND_CAP (must die_infra); no end-to-end two-round fixture proving a
  mid-loop PLINTH_REVIEWER_VENDOR swap falls back to a scoped verify rather than
  ever reaching a foreign --resume (covered today only by the extracted
  resumable_prev unit calls). Add with the next canary touch.
- **v4.6 canary gap: explicit PLINTH_AUDIT_MODEL pass-through untested.** Fixture 4d
  covers drop-model-on-audit-vendor-swap, but no test asserts an explicit
  PLINTH_AUDIT_MODEL survives and reaches the auditor CLI (structurally identical to
  the tested reviewer case — low risk). Add alongside the next canary touch.
  (v4.6 round 4, minor.)
- **v4.6 accepted tradeoffs / follow-ups (from the pre-flight self-review).** (a) Findings
  marked resolved drop from the verify payload — a regression resurfaces only as code in
  the cumulative diff; consider carrying resolved findings for one extra round. (b) The
  canary's six v4.6 fixtures repeat a 5-line repo recipe — extract a mk_loop_repo helper
  on the next canary touch. (c) `.DS_Store` is git-tracked and churns — untrack and
  gitignore it. (d) The full branch diff is still materialized+hashed even on scoped verify
  rounds where it is not sent — lazy-materialize if large-repo wall-clock ever matters.
- **review.sh: round_cap breaker message is misleading on a naive recovery
  retry.** The crash-recovery path (unconfirmed APPROVED, `recovery=1`) sets
  `round=prev_round+1`, which can exceed ROUND_CAP and hit the generic breaker
  at ~line 942 ("rethink the change or the spec") instead of the accurate
  confirmation-path message at ~line 978 ("PLINTH_ROUND_CAP=<n> to run the
  confirmation"); `die_infra` overwrites `last-error`, so a naive re-run
  replaces the good guidance with the misleading one. Exit code and safety
  unaffected. Route the recovery path to the confirmation-specific message; add
  a fixture. (v4.6 post-approval round, minor.)
- **v4.6 canary gap: round_cap = 0 (breaker disabled) has no fixture.** Fixtures
  cover round_cap=1 and 2 only; nothing drives a loop past round 8 with
  round_cap=0 to prove the breaker never trips. Same class as the non-numeric
  PLINTH_ROUND_CAP gap above. Add with the next canary touch. (v4.6
  post-approval round, minor.)
- **Canary seat-override fixtures use fixed /tmp capture paths**
  (`/tmp/ov-claude-args`, `/tmp/ov-grok-args`). Sequential today, race-prone if
  the canary job is ever split or parallelized; prefer mktemp per fixture.
  (v4.6 round-13 grok audit, minor.)
- **Chain-of-sessions binding: the binding APPROVED session never held pre-anchor
  code.** The session that produces a binding APPROVED sees only the open findings
  plus the cumulative diff since `lastfullread`; pre-anchor code is reachable only
  via optional read tools, so a fix diff can break a pre-anchor invariant that no
  binding session is structurally guaranteed to re-read. Distinct from the
  resolved-findings-drop tradeoff above (that is about dropped FINDINGS; this is
  about never-re-read CODE). (v4.6 round 12, minor.)
- **Review-prompt payload duplication in this repo: reviewer.md phase/convergence
  charter also lives in `.plinth/AGENTS-project.md`.** v4.6 promoted the "Review
  phases" / "Convergence — bound the loop" sections into `shared/reviewer.md`, but
  this repo's ratified `.plinth/AGENTS-project.md` still carries them verbatim;
  `inline_contract()` concatenates both, so every review prompt here includes the
  charter twice. No functional impact — trim the duplicate from AGENTS-project.md
  on the next ratified charter touch. (v4.6 post-approval fresh round, minor.)
- **`plinth update` cannot complete the driver-shell migration autonomously.**
  The one-time pre-v4.4 migration (move notes to `.plinth/DRIVER-project.md`,
  delete `CLAUDE.md`, regenerate) ends in a step the guard rightly blocks the
  driver from performing (`rm CLAUDE.md`), so it lands in NEEDS-HUMAN on every
  affected repo (plinth, certeus, anvil). If that recurs beyond this one-time
  wave, consider an explicit `plinth update --regen-shell` that completes the
  migration under a byte-honest no-content-loss check.
- **`changelog-collate` is not multi-file atomic across CHANGELOG + VERSION +
  fragment deletes.** Each file is written via temp+mv (so no half-written single
  file), but if the VERSION install or a fragment `rm` fails after CHANGELOG is
  installed, a retry can double-insert a section. The command reports the
  condition; a transactional rollback or a collate lockfile would harden
  environment failures. (changelog-fragments review round 1, minor.)
- **`changelog-collate` accepts a 9-digit component that increments past its own
  next-read bound.** Components of 10+ digits are rejected on input, but
  `999999999` + 1 produces a 10-digit VERSION the next collate will refuse.
  Reserve increment headroom (reject 9-digit all-nines) or accept the generated
  range on read. (changelog-fragments review round 6, minor.)
