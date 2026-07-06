# Plinth changelog

## v3.15 — July 6, 2026
Hotfix: the first real PR (anvil) caught the floor referencing a retired
action tag — google/osv-scanner-action@v1 no longer resolves. Root cause was
floating-major pins, so all three scanners were hardened, not just the one
that broke (each reference verified against the live repos, not memory):
- osv: v2 dropped the configurable root action; now called the documented
  way — its reusable workflow @v2.3.8 (nested reusable: ci -> floor -> osv),
  scan-args "-r ./", upload-sarif OFF (Code Scanning upload needs Advanced
  Security on private repos and would fail unrelated to vulns).
- gitleaks: pinned exact @v2.3.9 (was floating @v2).
- semgrep: semgrep/semgrep-action is ARCHIVED — replaced with semgrep's own
  container image running `semgrep scan --error` (registry rulesets, no
  token). :latest image is a stated exception to the pin policy: the tag
  always exists; a pinned archived action can vanish.
- Pin policy comment added to the floor. Template + project ci.yml pins
  bumped @v3.15. TAG v3.15 when pushing — the harness job clones by tag.

## v3.14 — July 6, 2026
Fixes anvil round 12: the reviewer applied the v3.12 policy's taxonomy
(labeled the tooling finding "UPSTREAM:", marked all project findings
resolved) and then blocked on it anyway. Verdict arithmetic was the last
piece still delegated to model judgment; now it's the instrument's:
- review.sh computes the EFFECTIVE verdict deterministically from the
  structured findings: open blocker/major findings on project paths block;
  harness-path findings never block; a mechanical tamper check (commits
  touching version-pinned tooling without 'plinth' in the subject) always
  blocks. Works in both directions — a reviewer APPROVED with open project
  blockers is forced back to CHANGES_NEEDED. The reviewer's raw verdict is
  recorded in verdict.json as reviewer_verdict; AGENTS.md now tells the
  reviewer its verdict field is advisory and its labels are load-bearing.
- NEW `harness` job in plinth-floor.yml (the hard guarantee guard.sh's
  header promises): clones plinth at the project's pinned version tag and
  byte-compares every version-pinned tooling file; any local modification —
  however it was made — fails the PR. Requires the plinth repo readable
  from Actions (public or PAT) and release tags (v<VERSION>). Known limit:
  a .plinth-version downgrade pins to an older-but-valid release; reviewers
  treat .plinth-version changes outside plinth-update commits as tampering.
- Template ci.yml now pins the reusable workflows @v3.14. EXISTING
  PROJECTS: bump the two `uses:` refs in .github/workflows/ci.yml (yours,
  never overwritten) and tag plinth releases going forward.

## v3.13 — July 6, 2026
- watch: live CI row — once the feed shows `gh pr create`, each repaint pulls
  the PR's check rollup (`gh pr view --json statusCheckRollup`) and renders
  ✓/✗/◌ counts colored by state. PLINTH_CI_STATUS overrides for non-gh CIs.
- NEW `plinth statusline`: one-line renderer for Claude Code's statusLine
  setting (stage + time-in-stage, verdict vs HEAD, red guard/gate alerts).
  Opt-in wiring documented in the MANUAL; reads only the event feed, so it is
  cheap at statusline cadence — token economics stay on `plinth watch`.
- MANUAL: branch protection explained for operators — why checks are advisory
  without it, why it must wait for the first PR (check names don't exist until
  they've reported), and exact UI + gh-api steps with verification.

## v3.12 — July 6, 2026
Fixes the anvil round-15 structural deadlock: the branch diff contained
version-pinned tooling the session may not fix, and the verdict policy had no
category for that — an honest reviewer re-flags it forever, so APPROVED was
unreachable by fixing the project. Three changes:
- guard v3 closes the actual flagged gap: bash-level WRITES to protected paths
  (redirections and mutating commands naming a protected pattern) are now
  blocked, with `.plinth/session/` protected as a BUILTIN (no per-project
  config needed). Heuristic by design — obfuscated writes can evade text
  matching; the CI hash-manifest job remains the planned hard guarantee.
  Reads (cat/jq/grep) stay allowed.
- Verdict policy learns scope and severity (AGENTS.md): blockers/majors in
  project code block; minors are reported but non-blocking and MUST be
  appended to the spec's `## Noticed` before the PR; findings in version-
  pinned tooling are "UPSTREAM:" — reported, never blocking, routed to the
  Plinth repo by the human. Tampering (tooling modified outside a labeled
  plinth-update commit) always blocks. APPROVED = nothing blocking ships,
  not "nothing left to say" — ends the 5M-token nit treadmill.
- Cheap verify fallback: when the reviewer thread can't be resumed, the round
  is now a fresh-session VERIFICATION (prior findings + incremental diff,
  O(delta) cost, non-binding) instead of a full re-read; the clean-slate full
  review runs once per milestone, to bind. Full-diff cost drops from
  once-per-round to once-per-approval.
- protected-paths template now seeds the harness paths (.claude/hooks/,
  settings.json, review.sh, schema, rules, MODELS.md, AGENTS.md, and
  protected-paths itself). EXISTING PROJECTS: append those lines manually
  (session/ needs nothing — it's builtin in guard v3).
- New rule: the PR body is the audit summary of the review loop, derived from
  .plinth/session/review/ artifacts (rounds, final verdict + SHA, real check
  output, Noticed minors, labeled tooling commits, UPSTREAM handoffs) — not
  narrated. A `plinth pr-body` generator is a candidate follow-up.

## v3.11 — July 6, 2026
- Gate honesty + hardening (found by the Anvil adversarial review, round 9,
  reviewing the Plinth tooling commit itself — the reviewer caught the rules
  doc overclaiming what review-gate.sh enforces, and the driver correctly
  refused to patch the harness from inside a reviewed session):
  - plinth-rules.md now states the real enforcement boundary (feature
    branches; two pressure valves) instead of an absolute.
  - EVERY release of provably-unreviewed commits is now logged as a
    `gate_release` event in the session feed — base-branch commits, the infra
    escape, and the block cap all previously released to an unstored stderr.
    `plinth watch` shows a red GATE RELEASES count.
  - Block cap is configurable: PLINTH_GATE_MAX_BLOCKS, default raised 5 -> 10
    (each block costs a full model turn).
- watch: change-detection refresh — 1s poll on event-feed/verdict file stamps,
  re-render only on change plus a 10s heartbeat for the clocks. Sub-second
  responsiveness without re-parsing megabytes of idle transcript every cycle.

## v3.10 — July 6, 2026
- `plinth init`/`update` now run a GitHub preflight: local `git init` happens
  automatically when missing (Plinth's review, gates, and dashboard are inert
  without git — the certeus lesson); creating the GitHub remote is offered
  interactively and never assumed (`gh repo create`, public suggested since
  free-plan private repos can't enable branch protection); branch protection
  is PROBED and reported (configured / available-but-unset / impossible on
  plan) but deliberately not configured — required-check names only exist
  after the first CI run, and guessing them can block merging forever behind
  checks that never report.
- watch polish: the task header now picks the first human prompt (skipping
  harness notification payloads that start with markup); refresh interval
  10s (was 2s); repaint is now in-place (cursor home + per-line erase)
  instead of clearing the screen each cycle — no more blink.
- MANUAL rewritten as an operator guide: quick start with exact commands, the
  daily loop annotated with what each hook does in the background, an
  annotated dashboard frame with "what to act on", a who-acts table for every
  blocking state, and the your-role summary. Written to be followable by an
  engineer new to the system.

## v3.9 — July 6, 2026
- FIXED the big-diff review deadlock (hit by anvil round 7): v3.8 resumed
  fix-verification rounds by re-sending the FULL diff into the same reviewer
  thread, which overflows on large diffs — and the retry path could only ever
  resume that same dead thread. Three changes:
  1. Resumed rounds now send only the INCREMENTAL diff (last-reviewed SHA ->
     HEAD); the thread already holds the prior context. Binding approval is
     unchanged — the clean-slate confirmation round still reviews the full diff.
  2. If `codex exec resume` fails for any reason, the round automatically
     falls back to a clean-slate full review in a fresh session (which binds
     directly — it IS the clean-slate pass). No more die-on-resume.
  3. Resume is skipped preemptively when the prior round processed more than
     PLINTH_RESUME_MAX input tokens (default 650000 ≈ 65% of GPT-5.5's
     1,005,000-token window — a model-layer fact; revisit on reviewer swap,
     checklist in MODELS.md), or when the last reviewed commit no longer
     exists (rebase).
  Protected session state never needs manual deletion to recover — by design.
- Honest-docs fix: "CI floor + Codex Security fire automatically" overstated
  it. Codex Security is the cloud-side integration connected per-repo
  (chatgpt.com -> Codex, SETUP step 4), distinct from the codex CLI reviewer;
  MANUAL now says to verify it on the first PR. Watch list gained: private
  repos on GitHub Free cannot enable branch protection at all — floor/checks
  are not required checks until the repo is public or the plan is Pro.

## v3.8 — July 6, 2026
- NEW `plinth watch <repo>` [--once]: live session dashboard (2s refresh, alt
  screen). Shows the task (first prompt), a PLAN→IMPLEMENT→VERIFY→REVIEW→PR
  stage pipeline with accumulated time and tokens per stage, cumulative tokens
  split fresh-in/cache-write/cache-read/out, burn rate with a 12-minute
  sparkline, the model actually answering (a silent Fable→Opus fallback is
  visible immediately), review verdict + whether it matches HEAD, reviewer
  token spend, last test-runner command with exit code and age, guard blocks,
  compactions, subagent completions, and the last tool call.
- NEW shared hook `pulse.sh`: appends one raw JSONL event per hook firing to
  .plinth/session/events.jsonl (SessionStart, UserPromptSubmit, PostToolUse,
  SubagentStop, PreCompact, Stop). Events are facts; ALL interpretation (stage
  classification, rates) lives in the renderer, so heuristics can improve
  without invalidating old logs. Never blocks; always exits 0.
- guard.sh now logs each block to the same feed (best-effort) so `watch` can
  show the base defending itself. session-start.sh rotates events.jsonl at
  5 MB. Token/model data comes from the Claude Code transcript referenced in
  the events — nothing new is recorded on the driver side.
- Stage semantics, stated: REVIEW/PR transitions are hard events (review.sh,
  gh pr create); PLAN/IMPLEMENT/VERIFY are heuristics from tool traffic and
  can bounce — the pipeline accumulates time per stage rather than pretending
  a one-way ratchet.
- EXISTING PROJECTS: `plinth update`, then add pulse.sh wiring to
  .claude/settings.json — copy the template's SessionStart / UserPromptSubmit /
  PostToolUse / SubagentStop / PreCompact / Stop entries. init/update now warn
  when pulse wiring is missing, same as the review gate.

## v3.7 — July 6, 2026
- The review loop's trigger is now mechanical, not conventional. NEW shared
  hooks: `session-start.sh` (records HEAD per session under .plinth/session/)
  and `review-gate.sh` (Stop hook — a session that created commits cannot end
  its turn until verdict.json says APPROVED at HEAD).
- The gate is deliberately narrow: it never fires outside a git repo, without
  a SessionStart baseline, on sessions that made no commits, or on main/master.
  Q&A and planning sessions are untouched.
- Anti-trap releases, both loud: a review.sh *infrastructure* failure within
  30 min (codex/jq missing or broken, bad schema, unparseable verdict — now
  recorded to .plinth/session/review/last-error and cleared on the next
  successful round) opens the gate so breakage reaches the human instead of
  wedging the session; and a 5-block cap per session backstops everything else.
  Loop-discipline refusals (dirty tree, empty diff, unchanged HEAD) do NOT
  open the gate.
- `plinth init`/`update` now warn when .claude/settings.json (yours, never
  overwritten) lacks the gate wiring — enforcement must never be silently
  absent. EXISTING PROJECTS: run `plinth update`, then add to settings.json
  "hooks":
      "SessionStart": [
        { "hooks": [ { "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/session-start.sh" } ] }
      ],
      "Stop": [
        { "hooks": [ { "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/review-gate.sh" } ] }
      ]
- Known limits, stated: the gate scopes by HEAD movement, so a session that
  edits but never commits can still stop (the work is visible locally and
  can't reach a PR); and verdict.json remains forgeable via bash redirection.
  Merge-level backstops (CI floor + Codex Security) still cover both; the CI
  verdict-receipt gate remains the deferred hard fix.

## v3.6 — July 5, 2026
- review.sh v2: the review/fix loop is now a file protocol, not prose over
  stdout. Verdicts are SHA-bound and schema-forced (`--output-schema`); state
  lives in `.plinth/session/review/` (request-<n>/findings-<n>/verdict.json +
  raw codex event streams, self-gitignored). Exit codes carry the signal:
  0 APPROVED, 1 CHANGES_NEEDED (fix, commit, re-run), 2 the review DID NOT RUN.
- Closed two false-pass paths: a dirty tree is now refused (uncommitted work
  was invisible to `git diff base...HEAD`, so fixes were reviewed stale or not
  at all), and empty/failed diffs exit 2 instead of "nothing to review" exit 0
  (the gate failed open on any git error).
- Fix rounds have memory: re-runs resume the reviewer's codex session
  (`codex exec resume`), re-verify each prior finding as resolved/open, and
  review new changes at first-pass rigor. A resumed APPROVED does not bind —
  a clean-slate confirmation review runs first, so session continuity can't
  soften the adversarial read. Re-running at an unchanged HEAD after
  CHANGES_NEEDED is refused; at an APPROVED HEAD it short-circuits (exit 0).
- Prompt now passes via stdin (ARG_MAX-safe for large diffs). Reviewer token
  usage per round is recorded in verdict.json.
- NEW shared file `.plinth/review-schema.json` (propagates via `plinth update`).
- New projects get `(^|/)\.plinth/session/` seeded in protected-paths so agents
  can't Edit/Write verdict state; add that line manually to existing projects.
- Verified against codex-cli 0.142.5: `--sandbox read-only`, `--json` thread
  ids, `exec resume` memory, `--output-schema` + `-o` interplay.
- Still convention-tier: nothing yet *forces* review.sh to run before a PR, and
  verdict.json remains writable via bash redirection (the guard covers
  Edit/Write only). The Stop-hook and CI verdict-gate are the follow-up that
  makes the trigger mechanical; verdict.json is now shaped for them (SHA-bound,
  machine-readable).

## v3.5 — July 5, 2026
- REMOVED `plinth migrate`: no Forge-era repos remain; the rename map lives in
  the v2 changelog entry if one ever surfaces from a backup.
- `plinth update` now also backfills per-project files introduced by newer
  Plinth versions (created only if absent, with created/kept reporting) — so
  picking up e.g. the v3.4 .gitignore no longer requires re-running init. The
  init/update distinction is now exactly its names: init bootstraps anywhere;
  update refuses non-Plinth directories and reports the version transition.
- Added the Plinth repo's own root .gitignore (.DS_Store, *.zip, *.plinth-tmp)
  — the harness shipped ignore protection to projects while lacking its own.

## v3.4 — July 5, 2026
- NEW templates/.gitignore (per-project, copied once): secrets, model weights
  (*.gguf/*.safetensors/etc.), OS junk, and build artifacts for the four
  detected stacks. Closes the gap where `git add -A` could commit weights or a
  stray .env — the guard blocks edits, not adds, and gitleaks fires post-commit.
- `plinth init` now reports every per-project file as "created" or
  "kept (yours)" — replaces manual post-init verification. (Note: init never
  rewrote existing files; the [ -f ] || guard predates this. The reporting
  makes that visible instead of trusted.)
- PLANNING-PROMPT: project notes must pin exact toolchain versions;
  requirements must be dependency-ordered (each testable using only its
  predecessors).

## v3.3 — July 5, 2026
- Zero-edit scaffolding: `plinth init` auto-detects the GitHub owner (target
  origin -> Plinth checkout origin -> git config github.user) and injects it
  into ci.yml; warns if undetectable.
- NEW reusable `plinth-checks.yml`: runtime stack detection (Rust/Node/Python/Go)
  runs conventional check commands at CI time — works for greenfield repos where
  nothing exists at scaffold time. Template ci.yml is now two `uses:` lines with
  an optional macos-latest runner input. Nonstandard stacks: replace the checks
  job locally (ci.yml is per-project, never overwritten).
- Tradeoff, stated: auto-detected checks run conventional commands, not
  project-specific ones. The driver still runs the project's real checks locally
  (Rule 10); CI detection is the backstop.

## v3.2 — July 5, 2026
- NEW `.plinth/config` (per-project, never overwritten): `spec_path` declares the
  canonical spec location — a file (SPEC.md) or a directory tree (ARCH/, spec/).
  Kills the reserved-SPEC collision at the harness level instead of forcing every
  project to work around it. review.sh, plinth-rules.md, AGENTS.md, and the
  CLAUDE.md template now reference spec_path instead of hardcoding SPEC.md.
- NEW `.plinth/AGENTS-project.md` (per-project, never overwritten): project-
  specific reviewer blocking criteria that extend the shared AGENTS.md. Fixes the
  defect where domain rules added to AGENTS.md were clobbered by plinth update.
- Rules: "Noticed" logging goes to the canonical spec, or NOTICED.md at repo root
  when the spec is a directory tree.

## v3.1 — July 4, 2026
- Fix: `bin/plinth` resolved PLINTH_ROOT via `dirname "$BASH_SOURCE"`, which
  returned /usr/local when invoked through the /usr/local/bin/plinth symlink,
  breaking init/update/goal/migrate. Now follows the symlink chain with a
  readlink loop (handles relative and chained links). Regression cause: the CLI
  had only ever been tested via `bash <path>`, never through the symlink. All
  CLI changes must now be tested through the symlink.


## v3 — July 3, 2026
- MODELS.md rewritten for the post-export-control landscape: Fable 5 suspended
  June 12 -> relaunched July 1; plan-included (50% of weekly limits) through
  July 7 ONLY; usage-credits-only after, with no automatic fallback. New default
  from July 8: Opus 4.8 driver, Fable 5 by exception via capped credits.
  Sonnet 5 added as the mechanical tier. GPT-5.5 remains reviewer; GPT-5.6 is
  gov-gated (~20 orgs), evaluate at Codex GA.
- NEW `plinth migrate`: one-shot Forge -> Plinth repo migration (carries over
  protected-paths, fixes CLAUDE.md import, ci.yml floor reference, GOAL.md paths).
- NEW PLANNING-PROMPT.md at repo root with a keep-in-sync header tying it to
  templates/SPEC.md and templates/GOAL.template.md.
- bin/plinth: in-place edits made macOS-portable (no `sed -i`).
- ci.yml template and floor workflow references bumped to @v3.

## v2 — June 9, 2026 (renamed from Forge; ForgeCode name collision)
- Project renamed Forge -> Plinth throughout.
- Driver: Claude Fable 5 at launch. Guard v2 with per-project protected-paths.
- NEW `plinth goal` auto-research mode: human-ratified metric, guard-enforced
  immutable eval, reviewer metric-integrity check.
- Rule 10 hardened per Fable 5 system card: commentary is not evidence.

## v1 — May 30, 2026 (as Forge)
- Initial versioned scaffold: shared vs per-project split, init/update CLI,
  reusable CI floor, guard hook, PR-creation review boundary.
