# Plinth — User Manual (v3)

## What Plinth is
A subscription-funded, multi-model dev environment: a frontier Claude model drives,
Codex/GPT-5.5 adversarially reviews, and a deterministic CI floor (tests + scanners
+ Codex Security) gates every merge. The name is the design: models are the statue,
swapped freely; Plinth is the base that doesn't move. You own two things — the spec
(what to build) and the gates (what may merge). Everything between is the model's call.

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
- `plinth init ~/Dev/<repo>`    — scaffold a project (templates once + shared pinned)
- `plinth update ~/Dev/<repo>`  — pull new shared files after updating Plinth
  and backfill any per-project files new to this version (never touches yours);
  review the diff, then commit
- `plinth goal ~/Dev/<repo>`    — drop a GOAL.md draft for auto-research mode
- Per-project knobs live in `.plinth/`: `config` (spec_path — point it at your
  spec file or tree), `protected-paths` (agent-immutable files), and
  `AGENTS-project.md` (project-specific reviewer rules). None is ever overwritten
  by `plinth update`.

## Starting a new project
Use PLANNING-PROMPT.md (in this repo) in a fresh chat to produce SPEC.md, the
CLAUDE.md project-notes section, and (if warranted) GOAL.md. Then `plinth init`,
paste the outputs in, commit.

## Daily loop
1. Plan in Claude.ai (project-scoped). Update `SPEC.md`. Commit.
2. `cd ~/Dev/<repo> && claude` — state the task; the model orchestrates itself.
3. It implements, writes real tests, runs checks, pastes real output (Rule 10:
   commentary is not evidence; only runner output counts).
4. Its last step: commit, then `./.plinth/review.sh` (Codex, read-only, SHA-bound).
   Exit 1 returns structured findings; it fixes, commits, re-runs until exit 0
   (APPROVED — recorded in `.plinth/session/review/verdict.json`).
5. Open the PR. CI floor + Codex Security fire automatically.
6. Glance at the consolidated checks. Merge. GitHub is the audit trail.

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
  after 5 blocks, so it can't trap a session on a broken pipeline.
- Branch protection: `floor` + `checks` required to merge.

## When models change (they will)
- New reviewer: one line in `~/.codex/config.toml`.
- New driver: `/model` in Claude Code.
- New recommendations ship in `shared/MODELS.md`: `git -C <plinth> pull`, tag, then
  `plinth update` each project when YOU choose. Nothing propagates silently.

## Watch list
- **July 7**: last day Fable 5 is plan-included. Decide: Opus 4.8 default (free) vs
  capped credits for Fable on hard tasks. No automatic fallback exists.
- **GPT-5.6 GA** (mid-July earliest): evaluate as reviewer; one-line swap.
- **Fable 5 back on plans**: Anthropic says "when capacity allows" — recheck before
  buying credit bundles.
- Verify on first run: the hooks schema; scanner action tags in `plinth-floor.yml`.
  (`codex exec` flags — sandbox, --json, resume, --output-schema — verified
  against codex-cli 0.142.5 in v3.6.)
