# Plinth — User Manual (v3)

## What Plinth is
A subscription-funded, multi-model dev environment: a frontier Claude model drives,
Codex/GPT-5.5 adversarially reviews, and a deterministic CI floor (tests + scanners,
plus Codex Security once connected) gates every merge. The name is the design:
models are the statue, swapped freely; Plinth is the base that doesn't move. You
own two things — the spec (what to build) and the gates (what may merge).
Everything between is the model's call.

## Current models (July 3, 2026 — see .plinth/MODELS.md, updated via `plinth update`)
- Driver through July 7: **Fable 5** (included on Max up to 50% of weekly limits;
  spend the window on the heaviest long-context work; it burns limits faster than
  Opus and its new classifier occasionally falls back to Opus 4.8 on coding).
- Driver from July 8: **Opus 4.8** default. Fable 5 becomes usage-credits-only with
  NO automatic fallback — if you'll rely on it at all, enable credits with a
  monthly cap now as insurance. Anthropic intends to restore it to plans later.
- Mechanical tier: **Sonnet 5** for refactors, test fixes, dep bumps.
- Reviewer: **GPT-5.5** (one line in `~/.codex/config.toml`). GPT-5.6 is out only
  to ~20 gov-approved orgs; evaluate when it reaches Codex GA (mid-July earliest).
- Orchestration: `/effort` -> `ultracode` for substantive tasks.

## Commands
- `plinth init ~/Dev/<repo>`    — scaffold a project (templates once + shared pinned),
  git-init if needed, offer GitHub repo creation, probe branch protection
- `plinth update ~/Dev/<repo>`  — pull new shared files after updating Plinth,
  backfill per-project files new to this version (never touches yours), re-run
  the GitHub preflight; review the diff, then commit
- `plinth goal ~/Dev/<repo>`    — drop a GOAL.md draft for auto-research mode
- `plinth watch ~/Dev/<repo>`   — live session dashboard (add `--once` for a
  single frame); see "The dashboard" below
- Per-project knobs live in `.plinth/`: `config` (spec_path), `protected-paths`
  (agent-immutable files), `AGENTS-project.md` (project-specific reviewer rules).
  None is ever overwritten by `plinth update`.

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
3. Connect Codex Security once: chatgpt.com -> Codex -> connect the repo.
4. After your FIRST PR (whenever it comes): confirm the `floor` and `checks`
   jobs appeared and that Codex Security commented. Then repo Settings ->
   Branches -> protect main, requiring those two checks. From then on the
   merge gate is real. Until you've SEEN both fire, treat them as absent.

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
   to a commit SHA), diffs the branch against main, and sends the diff to the
   second model (Codex) with the reviewer rules in AGENTS.md. The verdict comes
   back as machine-readable JSON in `.plinth/session/review/` — APPROVED or
   CHANGES_NEEDED with file:line findings. Exit code 0 = approved, 1 = fix
   findings (the model fixes, commits, re-runs; re-review rounds reuse the same
   reviewer session with just the incremental diff, and fall back to a fresh
   full review automatically if that session is too large or dead), 2 = the
   review DID NOT RUN. Approval only ever binds through a clean-slate full
   review — a warm reviewer can't approve its own checklist.
   *Background, enforcement:* if the model tries to end its turn with commits
   but no APPROVED verdict at the current HEAD, the Stop gate (`review-gate.sh`)
   refuses and sends it back with instructions. It cannot skip the review.
5. **The model:** opens the PR. *Background:* `ci.yml` fires the floor
   (gitleaks secrets scan, semgrep SAST, OSV dependency scan) and the
   stack-detected checks; Codex Security reviews the PR if the repo is
   connected (SETUP step 4).
6. **You:** glance at the consolidated checks, merge. GitHub is the audit trail.

## The dashboard (`plinth watch`)
Run it in any second terminal or tmux split; it repaints within ~1s of session
activity (change-detection on the event feed, 10s heartbeat for the clocks;
ctrl-c to quit; `--once` prints a single frame). If it says "no event feed", the pulse
hook isn't wired — `plinth update` will say so too.

```
 ◤ PLINTH WATCH fix auth token refresh on 401          <- the task (your first prompt)
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

## When something blocks — who acts
- `review.sh` exit 1 (CHANGES_NEEDED): normal. The model fixes, commits, re-runs.
- Exit 2, "working tree is dirty" / "HEAD unchanged" / "empty diff": loop
  discipline — the model must commit (or actually change something) first. Its
  problem; it will be told.
- Exit 2, infrastructure ("codex CLI not found", "codex exec failed", schema
  missing): **yours.** Fix the pipeline (usually `codex` login or `plinth
  update`), then tell the model to re-run. The session gate opens automatically
  after an infra failure so the session is never trapped by a broken reviewer.
- "PLINTH REVIEW GATE:" when the model tries to stop: the gate working. It runs
  the review or it doesn't finish. (Anti-trap: releases after
  PLINTH_GATE_MAX_BLOCKS blocks, default 10 — and every release is a red
  `gate releases` count on the dashboard, so nothing escapes silently.)
- "PLINTH BLOCKED:": the guard stopped a destructive command or a protected
  path. If the operation is genuinely intended, run it yourself.
- **Never edit or delete anything under `.plinth/session/`** — not to unblock,
  not to tidy. If the loop appears wedged, that is a Plinth bug: fix Plinth,
  not the instrument (see CHANGELOG v3.9 for the precedent).

## Auto-research mode (GOAL.md) — for numeric rubrics only (e.g. Anvil scores)
1. `plinth goal <repo>`; have the driver draft the metric, constraints, action
   catalog. 2. **You ratify** (set `STATUS: RATIFIED`) — agents never self-ratify.
3. Add the eval-script pattern to `.plinth/protected-paths` (guard makes it
   physically immutable). 4. Have Codex attack the rubric for gameability first.
5. Let the driver loop. It exits into the normal review -> PR -> CI path, where the
   reviewer explicitly checks for metric gaming.

## Hard blocks (don't rely on the model behaving)
- Guard hook: destructive commands, secret paths, and anything matching
  `.plinth/protected-paths` are blocked at the tool level — for every subagent too.
- Review gate (Stop hook): a session that created commits cannot end its turn
  until review.sh records APPROVED at HEAD. Scoped to feature branches and
  commit-making sessions; releases loudly on review infrastructure failure or
  after PLINTH_GATE_MAX_BLOCKS blocks (default 10), so it can't trap a session
  on a broken pipeline — and every release is logged as a `gate_release` event
  the dashboard shows in red.
- Branch protection: `floor` + `checks` required to merge (requires public repo
  or GitHub Pro; the preflight reports which state you're in).

## When models change (they will)
- New reviewer: one line in `~/.codex/config.toml`, then revisit
  `PLINTH_RESUME_MAX` (~65% of the new reviewer's context window — see the
  reviewer-swap checklist in `shared/MODELS.md`).
- New driver: `/model` in Claude Code.
- New recommendations ship in `shared/MODELS.md`: `git -C <plinth> pull`, tag, then
  `plinth update` each project when YOU choose. Nothing propagates silently.

## Watch list
- **First PR per repo**: confirm Codex Security actually reviews it (connection
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
