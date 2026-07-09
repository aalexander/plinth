# Plinth — User Manual (v3)

## What Plinth is
A subscription-funded, multi-model dev environment: a frontier Claude model drives,
Codex/GPT-5.5 adversarially reviews (risk-tiered — inert docs are approved by the
deterministic floor, code and high-consequence changes get the model), and a
deterministic CI floor (tests + scanners, plus Codex cloud review once connected —
security-briefed via the reviewer contract .plinth/reviewer.md) gates every merge. The name is the design:
models are the statue, swapped freely; Plinth is the base that doesn't move. You
own two things — the spec (what to build) and the gates (what may merge).
Everything between is the model's call.

## Current models (July 2026 — see .plinth/MODELS.md, updated via `plinth update`)
- **Driver: Opus 4.8** default, routed to the work for speed and efficiency —
  **Sonnet 5** for mechanical/doc changes (they land Tier 0–1), Opus at high effort
  for high-consequence work (Tier 2), **Fable 5 by exception** on usage credits for
  the heaviest long-context tasks (no automatic fallback — enable credits with a
  monthly cap first). This is the driver's own speed/cost call: GUIDANCE, not a gate.
- **Reviewer: `reviewer_vendor`** — codex / GPT-5.5 by default (one line in
  `~/.codex/config.toml`), or `claude` / `grok`, each its own CLI (no codex config
  needed). Risk-tiered, with a Tier-2 cross-vendor second opinion (`audit_vendor`,
  default grok). Keep `audit_vendor` a DIFFERENT vendor than `reviewer_vendor` — a
  match disables the cross-vendor audit (review.sh notes it on Tier 2), so if you
  make grok the primary, switch `audit_vendor` to codex or agy. The resume threshold
  scales per vendor automatically. GPT-5.6 is gov-only for now; evaluate at Codex GA.
- The reviewer's risk tier is the immutable adversarial gate; the driver's model is
  not. The driver's only lever over review cost is tier hygiene — keep low-risk work
  in its own change so it takes the cheap path, don't bundle it into a Tier-2 diff.
- Orchestration: `/effort` -> `ultracode` for substantive tasks.

## Commands
- `plinth init ~/Dev/<repo>`    — scaffold a project (templates once + shared pinned),
  git-init if needed, offer GitHub repo creation, probe branch protection
- `plinth update ~/Dev/<repo>`  — pull new shared files after updating Plinth,
  backfill per-project files new to this version (never touches yours, with ONE
  managed exception: it appends any missing Plinth-managed security patterns to
  `.plinth/protected-paths`, since those must propagate — your own added lines
  are left intact), re-run the GitHub preflight; review the diff, then commit
- `plinth goal ~/Dev/<repo>`    — drop a GOAL.md draft for auto-research mode
- `plinth watch ~/Dev/<repo>`   — live session dashboard (add `--once` for a
  single frame); see "The dashboard" below
- `plinth queue ~/Dev/<repo>`   — the full NEEDS-HUMAN queue, every item
  untruncated (the watch banner shows what fits the screen and points here).
- `plinth smoke ~/Dev/<repo> -- <command>` — run the real thing on real
  hardware; writes a SHA-bound execution receipt that the next review round
  verifies RUNTIME findings against. Failures are data — receipts record them
  identically.
- `plinth advise [--impactful] "<question>"` — (run inside the project) the DRIVER
  consults a model as good or BETTER than itself, read-only, for a collaborative,
  NON-BLOCKING second opinion — distinct from the adversarial reviewer (the gate) and
  the cross-vendor auditor. `--impactful` (architectural / hard-to-reverse decisions)
  escalates to the stronger model. Vendor-agnostic and cross-family (a Grok driver can
  consult Fable); see the `advisor_*` knobs below.
- Per-project knobs live in `.plinth/`: `config` (spec_path, exec_gated paths,
  round_budget, reviewer_vendor, audit_vendor/audit_model, advisor_vendor/advisor_model/
  advisor_model_max, tier2_extra — the config itself is agent-immutable, so these are
  yours alone), `protected-paths` (agent-immutable files), `AGENTS-project.md`
  (project-specific reviewer rules), `DRIVER-project.md` (project-specific driver notes).
  None is ever overwritten by `plinth update`.
- The DRIVER contract is a thin, pinned shell in BOTH `CLAUDE.md` and `AGENTS.md`, so
  whichever file your driver's CLI auto-loads (Claude→CLAUDE.md, codex→AGENTS.md,
  grok→both) delivers the driver role; it imports the shared rules and your
  `.plinth/DRIVER-project.md`. `plinth init` writes both shells byte-identical. MIGRATION
  CAVEAT: on `plinth update`, `AGENTS.md` is regenerated but a pre-existing CUSTOM
  `CLAUDE.md` (from a pre-v4.4.0 project) is PRESERVED with a loud NOTE to move its notes
  into `.plinth/DRIVER-project.md` and delete it — so on an upgraded project the two shells
  are byte-identical only AFTER you complete that one-time migration; until then a Claude
  driver still auto-loads your old CLAUDE.md. The REVIEWER contract lives in
  `.plinth/reviewer.md`, which the review harness passes to the reviewer explicitly.
- `.plinth/NEEDS-HUMAN.md` is the blocked-on-you queue: the driver records
  what only you can supply (hashes, credentials, smoke runs, budget acks);
  the dashboard shows a red banner while it's non-empty.

## Quick start (first time on a project — follow exactly)
0. Once per machine (SETUP.md has details): install Claude Code, Codex CLI
   (`npm i -g @openai/codex`, sign in with ChatGPT), `brew install jq gh`,
   `gh auth login`.
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
   access + review on PR open). It reads AGENTS.md (the driver shell), whose
   role-scope line points any reviewer — including this cloud review — at
   `.plinth/reviewer.md`, so it arrives security-briefed; there is no separate
   "Codex Security" product.
4. After your FIRST PR (whenever it comes): confirm the `floor` and `checks`
   jobs appeared and that the Codex review commented. Then enable branch
   protection requiring those checks — exact steps in "Branch protection"
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
   - Pane B: `plinth watch ~/Dev/<repo>` — the dashboard (below).
   *Background:* the moment the session starts, `session-start.sh` records the
   current commit (so the review gate knows whether this session created any),
   and `pulse.sh` begins appending one line per prompt/tool-call to
   `.plinth/session/events.jsonl`. That file is the dashboard's feed. Every
   Bash/Edit the model attempts passes through `guard.sh` first — destructive
   commands and protected paths are blocked at the tool level, including for
   every subagent.
3. **The model:** implements, writes real tests, runs the project's checks, and
   pastes real runner output (Rule 10: its commentary is not evidence).
   **You:** watch Pane B, not the scrollback. The evidence line shows the last
   real test run and its exit code; the model line shows who is actually
   answering; red guard-blocks mean the base deflected something.
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
     reviewer rules in `.plinth/reviewer.md`. A resumed approval binds
     directly — the warm reviewer thread still holds its first-pass full read, and
     iterative convergence speed is worth more than a second full read for ordinary
     code. A fallback verify (a fresh session, used when the prior thread is too
     large to resume) reads the prior findings plus the FULL diff — thorough, but
     anchored on those findings, so it does NOT bind on its own; like Tier 2 it gets
     a clean-slate confirmation first.
   - **Tier 2** — high-consequence surface (tooling, spec, security, migrations,
     public API, dependencies, weakened tests): full review, approval binds only
     through a clean-slate full pass (a warm reviewer can't approve its own
     checklist). When a cross-vendor auditor is configured (`audit_vendor` — new
     projects default to `grok`; on an upgraded project you add the line yourself,
     and `plinth update` reminds you if it is unset), every Tier-2 approval also
     gets a best-effort second opinion from that different vendor; its failure is
     recorded but the primary review remains the gate.
   The verdict comes back as machine-readable JSON in `.plinth/session/review/`
   — APPROVED or CHANGES_NEEDED with file:line findings. Exit code 0 = approved,
   1 = fix findings (the model fixes, commits, re-runs; re-review rounds reuse the
   same reviewer session with just the incremental diff, or — if that session is too
   large or dead — a verify round that reads prior findings plus the FULL diff
   (anchored on those findings) and does NOT bind on its own, so an approval still
   gets a clean-slate full confirmation first), 2 = the review DID NOT RUN.
   *Background, enforcement:* if the model tries to end its turn with commits
   but no APPROVED verdict at the current HEAD, the Stop gate (`review-gate.sh`)
   refuses and sends it back with instructions. It cannot skip the review.
5. **The model:** opens the PR. *Background:* `ci.yml` fires the floor
   (gitleaks secrets scan, semgrep SAST, OSV dependency scan) and the
   stack-detected checks; Codex cloud review posts on the PR if the repo is
   connected (SETUP step 4).
6. **You:** glance at the consolidated checks, merge. GitHub is the audit trail.

## The dashboard (`plinth watch`)
Run it in any second terminal or tmux split; it repaints within ~1s of session
activity (change-detection on the event feed, 10s heartbeat for the clocks;
ctrl-c to quit; `--once` prints a single frame). If it says "no event feed", the pulse
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
4. In the search box, pick the floor and checks jobs EXACTLY as they appeared
   on the PR (e.g. "CI / floor / secrets", "CI / checks / ...").
5. Create. From then on red = unmergeable, for humans and agents alike.

CLI route (same timing; paste the names the PR showed):

    gh api -X PUT repos/OWNER/REPO/branches/main/protection --input - <<'JSON'
    {"required_status_checks":{"strict":false,"contexts":["CHECK NAME 1","CHECK NAME 2"]},
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
3. Add the eval-script pattern to `.plinth/protected-paths` (guard makes it
   physically immutable). 4. Have Codex attack the rubric for gameability first.
5. Let the driver loop. It exits into the normal review -> PR -> CI path, where the
   reviewer explicitly checks for metric gaming.

## Hard blocks (don't rely on the model behaving)
- Guard hook: common destructive commands (an enumerative, heuristic pattern set —
  prefixed and wrapped forms are caught, but deliberate obfuscation can evade text
  matching; CI and branch protection are the hard layers), secret paths, and anything
  matching `.plinth/protected-paths` are blocked at the tool level — for every
  subagent too.
- Review gate (Stop hook): a session that created commits cannot end its turn
  until review.sh records APPROVED at HEAD. Scoped to feature branches and
  commit-making sessions; releases loudly on review infrastructure failure or
  after PLINTH_GATE_MAX_BLOCKS blocks (default 10), so it can't trap a session
  on a broken pipeline — and every release is logged as a `gate_release` event
  the dashboard shows in red.
- Branch protection: `floor` + `checks` required to merge (requires public repo
  or GitHub Pro; the preflight reports which state you're in).

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

## Watch list
- **First PR per repo**: confirm the Codex review actually posts (connection
  is per-repo, SETUP step 4) and enable branch protection once the check names
  are visible.
- **July 7**: last day Fable 5 is plan-included. Decide: Opus 4.8 default (free) vs
  capped credits for Fable on hard tasks. No automatic fallback exists.
- **GPT-5.6 GA** (mid-July earliest): evaluate as reviewer; one-line swap.
- **Fable 5 back on plans**: Anthropic says "when capacity allows" — recheck before
  buying credit bundles.
- Verify on first run: the hooks schema; scanner action tags in `plinth-floor.yml`.
  (`codex exec` flags — sandbox, --json, resume, --output-schema — verified
  against codex-cli 0.142.5 in v3.6.)

## Your role, in one paragraph
Write the spec. Stand up the gates (init preflight + first-PR checklist). Then
read the dashboard, not the transcript, and let the machinery run. The trust
order when anything conflicts: deterministic floor (CI) > cross-model review >
driver self-report — `verdict.json` and runner output are evidence; the model's
summary is commentary. You intervene for exactly three things: infra failures
(exit 2), guard blocks you actually intended, and merges.
