# Plinth changelog

## v4.2 (continued) — audit/tier review-integrity fixes — July 8, 2026
Surfaced by the clean-slate confirmation reviewing this branch:
- review.sh: an unknown `audit_vendor` (a config typo like `gork`) no longer
  silently falls through to codex. Falling through ran the SAME vendor as the
  primary reviewer and recorded it under the bogus name — a false cross-vendor
  guarantee AND a fail-open. `run_auditor` now returns nonzero for any vendor
  outside {codex, grok, agy}, so the audit is recorded UNAVAILABLE (non-blocking,
  primary review still stands) and the message names the misconfiguration.
- review.sh: the binding rule is now one predicate, `binds_directly(mode, tier)`,
  shared by the post-round gate and the reviewer-facing note so they can't drift.
  A fresh full review binds; a warm Tier-1 RESUME binds directly (its thread holds
  the round-1 full read); a Tier-2 approval and ANY fallback VERIFY (a fresh
  session that saw only prior findings + the incremental diff — never the full
  current diff) get a clean-slate confirmation before binding. This closes two
  gaps: the resume/verify prompts previously told the reviewer a clean-slate pass
  would confirm even when (for Tier 1) its verdict bound directly, AND a Tier-1
  fallback verify could bind final APPROVED off that narrow view. `bind_note` now
  states the truth for the actual (mode, tier).
- review.sh: closed the lineage leak in the above — a verify round that returned
  CHANGES_NEEDED recorded its session_id, and the NEXT run resumed it as
  `mode=resume`, where `binds_directly(resume, tier1)` bound a thread that had only
  ever seen the incremental diff. A verify-origin session is now non-resumable
  (`resumable_prev`, and the round's `mode` is recorded in the verdict): the next
  round goes fresh and re-reads the full diff before any bind. `resumable_prev`
  fails CLOSED — it resumes only a mode KNOWN to carry a full-diff read (`fresh` or
  a prior `resume`); an empty/unknown mode (e.g. a verdict.json written before the
  `mode` field existed, or an in-flight upgrade) goes fresh rather than resuming a
  possibly-narrow thread.
- risk-classify.sh: an invalid `tier2_extra` regex (a typo in this agent-immutable
  routing knob) now fails CLOSED to Tier 2 instead of silently disabling the
  project Tier-2 surface — `grep -Eq` returns exit 2 on a bad pattern, which the
  per-file check read as a plain "no match", letting intended Tier-2 paths slip to
  Tier 0/1. Validated once against empty input at startup.
- risk-classify.sh: ANY modification of an existing test now escalates to Tier 2,
  not just ones with a removed line. The prior check keyed on `^-[^-]` (removed
  text), a binary diff, or an added skip token — so an ADDITION-ONLY weakening
  (e.g. inserting an early `return` before the assertions) slipped to Tier 1. Now
  any touch of existing test content (status != added) is Tier 2, matching the
  classifier's own stated intent that assertion-counting is gameable by padding.
  This subsumes the removed-line and binary-baseline checks; only a brand-NEW test
  file stays Tier 1 (unless it lands pre-skipped).
- risk-classify.sh: the TESTS regex now recognizes the pytest `test_*` PREFIX
  convention (`test_core.py`, `app/test_core.py`), not just the `*_test`/`*.spec`
  suffixes — deleting or modifying a `test_*.py` outside a `tests/` dir was
  slipping through as ordinary Tier-1 code instead of the required Tier-2
  weakened/deleted-test path.
- review.sh: the cross-vendor auditor now inlines the WHOLE canonical spec tree
  (new `inline_spec`): a directory-tree spec had only `.md`/`.rst`/`.txt` files
  inlined, so a project whose spec tree includes YAML/JSON/other files gave the
  tools-forbidden auditor an INCOMPLETE spec — a false cross-vendor guarantee. Now
  every text file in the tree is inlined (binaries skipped); a file spec is
  unchanged.
- plinth watch: an UNAVAILABLE cross-vendor audit rendered as "audit ✓" (its
  blocking==0 matched the concur branch). The dashboard now shows "audit
  unavailable" distinctly, so a failed auditor is not mistaken for a passing one.
- Canary: added the previously-missing `reviewer_model_tier1/tier2` regression
  test — asserts the primary reviewer receives `codex -m <model>` as two argv
  tokens on the MATCHING tier (Tier 1 uses tier1's model, Tier 2 uses tier2's),
  the same argv-collapse class the audit_model probe guards. Also an `inline_spec`
  unit probe (non-.md spec file inlined, binary skipped).
- Canary: regression probes for every fix above — unknown `audit_vendor` =>
  UNAVAILABLE (not a codex fallthrough); the full `binds_directly`/`bind_note`
  mode×tier matrix (incl. Tier-1 verify must NOT bind); invalid `tier2_extra` =>
  fail-closed Tier 2; modified-binary-test => Tier 2 (new binary test stays Tier 1);
  and the dashboard audit badge's three-way discrimination (unavailable / ✓ /
  DISAGREES).
- MODELS.md: spelled out the two SEPARATE reviewer integration paths a field driver
  conflated. `audit_vendor` = grok|agy runs that vendor's OWN CLI (subscription-
  authed, independent of codex config; missing => non-blocking UNAVAILABLE).
  `reviewer_model_tier1/tier2` are passed to `codex -m`, so making grok the PRIMARY
  reviewer needs an xAI `model_provider` + key in `~/.codex/config.toml` plus a
  `PLINTH_RESUME_MAX` reset — not automatic; leave unset to keep gpt-5.5.

## v4.2 (continued) — explicit driver model routing — July 7, 2026
- MODELS.md + MANUAL.md: the DRIVER now gets the same explicit routing the reviewer
  already had. A task-shape → risk-tier → model table replaces the stale two-phase
  "Fable through July 7 / Opus from July 8" prose (that window closes tomorrow):
  Sonnet 5 for mechanical/doc work (Tier 0–1), Opus 4.8 default (Tier 1), Opus at
  high effort or Fable 5 by exception for high-consequence work (Tier 2). The point
  is speed and efficiency — don't drive a doc tweak on Opus, don't drive a security
  change on Sonnet.
- Named the asymmetry the design rests on: driver-model choice is a self-interested
  speed/cost decision with NO adversarial stakes (the CI floor + cross-model review
  catch bad work whoever wrote it), so it is GUIDANCE, not a gate — deliberately the
  opposite of the reviewer's risk tier, which is immutable precisely because it IS
  the adversarial gate. That is why driver routing stays doc guidance and is not a
  new knob or script: a driver-writable model gate would be worthless anyway.
- Made explicit the driver's one real lever over review COST: tier hygiene. A single
  Tier-2 signal drags the whole diff onto the deep clean-slate + cross-vendor path,
  so low-risk work belongs in its own commit/PR. The driver never picks the reviewer
  — the diff does — and that is the only "direction over the reviewer" it has.
- Canary coverage closes (surfaced reviewing this branch): the classifier canary now
  probes PLANNING-PROMPT.md => Tier 2 (round 29's TOOLING classification had no test,
  so the regex could silently regress to Tier 0); and the protected-paths update test
  now writes a user line with NO trailing newline and asserts whole-line survival
  (`grep -qxF`), actually exercising round 29's `ensure_protected_paths` concat guard
  — the prior test wrote a trailing newline and used a substring grep that a corrupted
  concatenation would still satisfy.

## v4.2 — smoke no-hang fix — July 8, 2026
- smoke.yml: a github-hosted `precheck` job now decides whether there is anything
  to smoke (smoke_cmd set in the base config) BEFORE any self-hosted runner is
  requested. Previously the self-hosted `smoke` job was queued unconditionally,
  so a repo with no `plinth-smoke` runner (and/or no smoke_cmd) left the job
  `queued` forever — blocking PR merges. With the gate, no-smoke_cmd repos skip
  the self-hosted job entirely (green no-op, no runner needed). The precheck
  reads ONLY the base config (never the PR checkout), so a PR cannot add
  smoke_cmd to re-trigger the self-hosted job (which reads base and would no-op
  anyway). Found in the field: certeus PRs hung 2h+ on a queued smoke with no
  runner and no smoke_cmd.
  NOTE: smoke.yml is a per-project file (never overwritten by update) — existing
  projects must copy the new template in.

## v4.2 (continued) — July 7, 2026
Planning-prompt overhaul + trust-but-verify + optimal cross-vendor assignment.
- SPEC template + PLANNING-PROMPT (kept in sync): requirements now carry STABLE
  IDs (REQ-<AREA>-<NN>), explicit `prereqs:` (a dependency DAG, not a linear
  list — enables small vertical slices + safe parallel work), and a `validate:`
  line naming unit / integration / RUNTIME-smoke / post-merge checks. "Has a
  test" is no longer enough — the runtime-smoke question is forced, closing the
  blindspot class that let the anvil real-run layer go unvalidated. NEW spec
  sections: Core Invariants (near-immutable), Execution-gated surface
  (exec_gated + smoke_cmd), High-consequence surface (tier2_extra).
- DROPPED (built, then removed): trust-but-verify Tier-0 sampling. The dogfood
  review proved it can't work — any sample computed locally from the commit SHA
  is grindable (amend the commit until the roll escapes the rate), and any
  per-run random is re-runnable. Local sampling cannot be unpredictable to an
  adversarial driver. Real Tier-0 verification belongs in CI (deterministic
  re-classification of the merge diff — ungameable), deferred with the receipt
  work. A clean example of the loop killing over-clever hardening that can't
  deliver what it promised.
- Optimal reviewer assignment across the three subscription CLIs (MODELS.md):
  codex/GPT-5.5 primary (deepest) + binding confirmation; grok (fast, xAI) as
  the default Tier-2 cross-vendor audit (`audit_vendor = grok`) and optional
  fast tier1 reviewer; agy/Gemini kept as a third option (refuses adversarial
  framing, so audit-only). New projects default to audit_vendor=grok; plinth
  update reminds upgraded projects to add it.
- Hardening from the dogfood-review loop (plinth reviewing its own risk-routing
  change — 14 rounds, every finding real): classifier now fails CLOSED (a
  non-empty diff that processes 0 files emits Tier 2, never Tier 0; switched off
  the here-string that could fail on temp-file creation); the cross-vendor audit
  prompt inlines the reviewer rules (AGENTS.md + AGENTS-project.md) and
  directory-tree specs so a tools-forbidden auditor applies mandatory blocking
  policy; MANUAL.md rewritten to describe the tiered model (Tier 0 floor-approved,
  Tier 1 warm-binds, Tier 2 clean-slate + cross-vendor); and the classifier
  canary now exercises 12 bypass
  classes (deps, security, symlink, build, spec, tier2_extra, executable,
  skip/delete/weaken tests, submodule, rename-to-doc, type-change).
- More dogfood fixes: the codex CLI is required only for a model round, so a
  Tier-0 docs approval genuinely needs no model infrastructure (verified: Tier-0
  approves with codex off PATH, Tier-1 still fails loud); BUILD classification is
  case-insensitive (lowercase `makefile` now floors to Tier 2); and `plinth
  update`'s protected-paths backfill is documented as the one managed exception
  to "update never touches your per-project files."
- ensure_protected_paths now ensures a trailing newline before appending, so a
  user's last protected-paths line lacking a newline isn't concatenated/corrupted
  by the first managed pattern. PLANNING-PROMPT.md is classified TOOLING/Tier 2
  (it is prompt-as-code that shapes future specs, not inert docs).
- audit_model override was silently broken: `${AUDIT_MODEL:+-m "$AUDIT_MODEL"}`
  collapsed to a single argv token `-m model` instead of two, so a configured
  audit_model never reached the auditor. Fixed with a proper 2-element array
  across all three vendor call sites; canary now asserts the auditor receives
  `-m` and the model as separate tokens.
- More dogfood fixes: review.sh now fails CLOSED when the classifier is
  missing/broken (defaults Tier 2, not Tier 1 — an unclassified high-consequence
  diff is over-reviewed, never under-reviewed); the floor byte-compare skips
  files the PINNED release predates (so the plinth repo's own canary, whose
  installed .plinth/ is an older release, is not permanently red on a
  not-yet-shipped file); and the canary now stubs a primary reviewer + grok
  auditor to exercise the cross-vendor audit path (records the audit verdict on
  concur, UNAVAILABLE on a failing auditor). All verified locally.
- Two more routing holes closed: `CLAUDE.md` (imports the plinth rules, controls
  the driver) is now classified TOOLING/Tier 2 instead of falling through to the
  inert-docs rule; and `.plinth/protected-paths` was removed from review.sh's
  HARNESS_RE so a bad protected-paths change stays BLOCKING (AGENTS.md excludes
  it from the UPSTREAM/tooling exemption) instead of being filtered as non-blocking.
- DEFERRED (removed before merge): a CI review-receipt verifier that would
  recompute tier+digest at merge to close a hypothesized approve-then-swap
  TOCTOU. Built, but it generated every dogfood-review finding (a gate deadlock,
  a push-event CI failure, a protected-paths gap, an untested security workflow)
  without an OBSERVED problem justifying it — the definition of premature
  hardening. Pulled per "get the core working, then harden." Returns as its own
  tested increment if real use shows the need. `diff_digest` is still recorded in
  the verdict as a forensic fingerprint (no longer an enforcement point).

## v4.2 — July 7, 2026
First increment of the multi-model-panel-converged improvement plan: **risk-based
review routing** (P1) — the top speed/efficiency win that also closes the worst
trust hole, with NO new human bottleneck (a deterministic mechanism holds the
pen, not a human).
- NEW `shared/.plinth/risk-classify.sh` (version-pinned, agent-immutable): a
  deterministic classifier that assigns each change a risk Tier from the diff
  alone — no model, no human, and the driver cannot de-escalate it (guard-
  protected, in HARNESS_RE, in the CI byte-compare).
  - Tier 0 (inert docs/text only) → APPROVED by the deterministic floor with
    ZERO model rounds. A docs change no longer costs reviewer tokens.
  - Tier 1 (ordinary code) → standard adversarial review (unchanged).
  - Tier 2 (tooling, spec, security/auth/crypto/secrets, migrations/schema,
    public API, dependency manifests, DELETED or WEAKENED tests) → full review.
    Conservative: unknown → Tier 1; Tier 0 only when EVERY file is inert.
  - Implements the panel's "loosen hides in the test diff" catch mechanically:
    a test whose diff removes more assertions than it adds is floored to Tier 2.
- review.sh routes depth AND treatment by tier, recording `risk` + a
  `diff_digest` (sha256 of the reviewed diff) in verdict.json:
  - **Tier 1** (ordinary code): may use a cheaper reviewer model
    (`reviewer_model_tier1`), and a resumed APPROVED binds directly — the
    clean-slate confirmation round is SKIPPED (faster iterative convergence;
    the digest binds it). No cross-vendor audit.
  - **Tier 2** (high-consequence): the frontier model
    (`reviewer_model_tier2`), ALWAYS a clean-slate confirmation, and a
    cross-vendor second opinion on EVERY approval when `audit_model` is set
    (a different-vendor model, not just every 5th) — the reviewer-collusion
    fix. No human in this path; a different isolated model is the authority.
- `.plinth/config` gains `tier2_extra`, `reviewer_model_tier1/tier2`. Classifier
  + config are agent-immutable; per-tier model routing (P2) is now real.
- HARDENED against a cross-vendor red-team (GPT + Grok + Gemini — all three
  independently flagged the same Tier-0 bypasses as "critical"):
  - No global `.txt` in Tier 0 (CMakeLists.txt / constraints.txt were shipping
    as inert docs). NEW `BUILD` Tier-2 block (Makefile, CMakeLists, Dockerfile,
    setup.py, gradle, bazel, cmake, release/deploy scripts).
  - Metadata names (LICENSE/NOTICE/…) anchored — `LICENSE.py` is no longer docs.
  - Classifier now reads `git diff --raw`: renames classify BOTH paths (moving
    code/tests into a doc name no longer laundered), and mode is checked —
    symlinks, submodules, executables, and type-changes can never be Tier 0.
  - Test heuristic replaced: net assertion counting was gameable by padding.
    Now ANY modification of an existing test (removed content), a deleted test,
    a test moved out of the test tree, or an added skip/ignore → Tier 2. Pure
    new/addition-only tests stay Tier 1. Test surface widened to fixtures,
    golden, snapshots, testdata, helpers.
  - Tier-2 path triggers broadened (security synonyms: access/policy/identity/
    sso/mfa/csrf/cors/cert/tls/…; ORM/model schema; API routes/controllers/
    *.graphql; more dependency ecosystems; CI/build files).
- NEW cross-vendor auditor adapters: the Tier-2 second opinion can now run on a
  GENUINELY DIFFERENT VENDOR, not just a different OpenAI model — closing the
  reviewer-collusion risk (the reviewer is otherwise a sibling of the driver).
  `audit_vendor = codex|grok|agy` selects a subscription-authenticated CLI
  (OpenAI / xAI Grok Build / Google Antigravity) — all no-per-use-cost, same
  pattern as codex. Agentic auditor CLIs are driven with a self-contained,
  tools-forbidden prompt (spec + diff inlined) so they answer directly; an
  unparseable audit FAILS LOUD (never a silent concur). Verified end-to-end
  with real grok: it independently caught 3 blocking findings a passing primary
  reviewer missed and recorded the disagreement in verdict.audit.
- NOT yet done — the one gap all three flagged and confirmed: `diff_digest` is
  recorded but not VERIFIED at merge (TOCTOU: approve a benign diff, swap the
  payload before merge). The digest is forensic-only until a CI job recomputes
  the tier + digest against the real merge SHA and hard-fails on mismatch. That
  CI verification is the next increment.

## v4.1.9 — July 7, 2026
- watch + queue: [BLOCKING] items are sorted to the TOP of the human list
  (order preserved within each group) and rendered in bold red; non-blocking
  items are dim below. The banner already carried the blocking count; now the
  ordering and color make "what's stalling work right now" unmissable. Applies
  to `plinth watch` and `plinth queue` identically.

## v4.1.8 — July 7, 2026
- watch: the frame can no longer scroll its own top off-screen — which was
  hiding the header, branch, and (newly added) models line. The repaint is
  cursor-home, not full-clear; one line taller than the viewport scrolls
  everything up and the next home lands mid-frame, permanently losing the
  top. Now the emitted frame is HARD-CAPPED to (terminal rows − 1) lines, so
  the top is always preserved; the queue (bottom) is what yields, and it
  already points at `plinth queue` for the remainder. Queue reserve
  recalibrated for the taller fixed frame (the v4.1.7 models line).
  Restart any running watch pane to pick this up.
- watch: models are now a dedicated, bright line showing BOTH — "models
  driver <model> · reviewer <model>" — instead of the driver model buried in
  the dim metadata line (easy to miss; the reviewer model was never shown at
  all). Driver model from the transcript as before; reviewer model newly
  recorded in verdict.json by review.sh (the `model` from ~/.codex/config.toml
  — what codex actually runs). Existing verdicts predate this and show "—"
  until the next review round; run `plinth update` to record it going forward.
- watch: fixed a v4.1.5 regression — capture_tty_size leaked
  "/dev/tty: Device not configured" to stderr in headless/background contexts
  (a device node can exist but not be openable). Now tested by actually
  opening it in an error-swallowing subshell; real terminals are unaffected.

## v4.1.6 — July 7, 2026
- guard hardening from upstream issue #1 (first driver-filed report through
  the v4.1 channel — certeus reviewer flagged it as a nonblocking UPSTREAM
  major):
  - backtick added to the command-boundary class, so `` `rm -rf x` `` and
    `$(rm -rf x)` command substitutions are caught (they were bypasses).
  - multiline: no code change needed — grep matches per line, so ^ already
    anchors every line of a multiline command; verified the second-line
    bypass now blocks.
  - prose false-positives eliminated: single/double-quoted spans are
    stripped before matching the rm/git patterns, so a printf'd note or a
    `gh issue --body` that merely NAMES the commands passes. (The reporter
    had to file #1 with --body-file to get past the old guard.)
  - stated non-goals: a destructive command hidden inside quotes that reach
    a shell (`bash -c "rm -rf x"`) was never caught by anchoring and remains
    out of scope — the CI harness byte-check is the hard layer. DROP stays
    unstripped (real destructive SQL lives in quotes); prose naming DROP
    TABLE still trips it — use --body-file/heredoc.

## v4.1.5 — July 7, 2026
- watch: the queue budget now uses your REAL window height. Inside the
  repaint's command substitution, tput talks to a pipe and reports the
  terminfo default (24×80) no matter how tall the window is — every user
  saw ~8 queue lines. The watch loop now reads `stty size </dev/tty` per
  repaint (resize-aware) and hands it down via the PLINTH_WATCH_* overrides,
  which still win if set by hand. Reserve tightened to include the live
  footer so a full queue can never push the frame top off-screen.
  (Restart any running watch pane to pick this up.)

## v4.1.4 — July 7, 2026
- watch layout: fixed dashboard (cycle/pipeline/review/signals) anchored at
  the TOP; the variable-height NEEDS-HUMAN queue moved to the BOTTOM where
  growth displaces nothing.
- Queue prioritization: plinth-rules now direct drivers to prefix items that
  stall work RIGHT NOW with [BLOCKING] and keep them at the top. The counts
  surface everywhere: watch banner "(N open · B BLOCKING)", `plinth queue`
  header, statusline "⏸ HUMAN×N⛔B".

## v4.1.3 — July 7, 2026
- watch: the frame now always fits the screen. v4.1.2's full-item banner
  could exceed terminal height, scrolling the dashboard's top off (the
  repaint homes to a top that no longer exists). The banner shows as many
  COMPLETE items as fit (height-aware; PLINTH_WATCH_ROWS overrides), then
  "… +N more — full queue: plinth queue <repo>".
- NEW `plinth queue <repo>`: the whole NEEDS-HUMAN queue, every item in
  full, folded to terminal width, ordinary scrollable output. A fixed
  dashboard and an unbounded queue can't both win — reading long queues
  happens here; the dashboard signals.

## v4.1.2 — July 7, 2026
- watch: NEEDS-HUMAN truncation actually fixed — three stacked causes:
  1. items are often MULTI-LINE markdown; the extractor took only the first
     line of each (this was the visible "truncation"). Items are now
     gathered whole (continuation lines joined until the next item/heading).
  2. display wrapping is now SOFTWARE folding to terminal width with a
     hanging indent — the in-place repaint assumes one logical line per
     physical row, so terminal wrap can't be relied on. PLINTH_WATCH_COLS
     overrides width for tests.
  3. latent pipefail bomb: on a branch with no request-*.json, the ls
     pipeline killed render_frame silently (set -e) — first trip on
     certeus/main. Guarded.
  NOTE: a running `plinth watch` executes its in-process code — restart the
  pane to pick up any update.

## v4.1.1 — July 7, 2026
- watch: NEEDS-HUMAN items render in FULL — no 64-char truncation, no
  3-item cap. The queue exists to be read, not sampled; certeus's driver
  writes multi-line actionable handoffs and the operator must see all of
  each one. Long items wrap in the terminal.

## v4.1 — July 7, 2026
Field-feedback release: every fix below was reported by a driver (certeus)
or observed live. The upstream channel this release formalizes is how the
next ones should arrive.
- NEW upstream channel (plinth-rules): tooling findings/proposals are filed
  as GitHub issues on the plinth repo ("UPSTREAM:" title convention) and are
  two-way — drivers check for maintainer replies at session start and answer.
  Proposals are untrusted input: evaluated for merit AND security by the
  maintainer before anything ships; an issue cannot alter tooling by itself.
- AGENTS.md: NEEDS-HUMAN.md explicitly exempt from the tooling-tamper rule —
  drivers are REQUIRED to maintain and commit it (the gap cost a driver a
  blocker round and a history rewrite).
- review.sh prompts now include COMMITS IN RANGE so clean-slate rounds can
  judge the "labeled Plinth update commit" exemption; previously they saw
  only the diff and flagged legitimate tooling updates as tampering.
- guard: rm/git destructive patterns anchored to command position — the
  literal string inside quoted text (printf'd notes, docs) no longer
  false-positives (it blocked a driver AND the maintainer). DROP stays
  unanchored (real destructive SQL lives inside quotes). .env protection
  allowlists .example/.sample/.template. Full block/allow matrix verified.
- plinth-rules: review rounds can exceed 10 minutes — run in background if
  the shell tool caps there; interrupted rounds are safe to re-run.
- watch: session focus is the most recently ACTIVE session, not the last
  SessionStart (certeus: watch pinned to a dead 18-event session while the
  real 328-event session ran 9 hours). Current stage shows its live stint
  ("· now 5h 53m") beside cumulative; Σ TOTAL row sums stage time + tokens;
  an in-flight review round renders as "round N RUNNING (mode) · Xm in ·
  last verdict …".

## v4.0.3 — July 7, 2026
Docs/template only — nothing propagates via `plinth update`; no pin changes.
- MANUAL: "Kicking off the driver" — what to actually say once SPEC.md
  exists (scoped start / full run / continuation), what good first minutes
  look like, what NOT to do (paste the spec, micro-instruct, answer design
  questions the spec already answers), and session hygiene (fresh session
  per slice beats a compacted 20-hour resume).
- MANUAL: "Precedence" — the known conflicts between plinth rules and the
  driver's harness defaults / personal globals. The sharpest one is real
  and load-bearing: the harness default is "commit only when asked," while
  the loop REQUIRES unprompted commits (verdicts bind to SHAs; the Stop
  gate demands APPROVED-at-HEAD) — a driver obeying the default deadlocks.
- templates/CLAUDE.md (and appended to existing projects' CLAUDE.md, which
  is created-once): an explicit Precedence section instructing drivers that
  plinth rules override defaults and personal/global preferences — commit
  without being asked, evidence over brevity, and declare (never silently
  blend) any conflict with personal instructions.
- NEW RULE (plinth-rules.md, found by the certeus bootstrap): work on a
  feature branch, never commit directly to base — the gate deliberately
  doesn't guard base branches and the PR needs a branch. This was always
  assumed, never stated; anvil's driver did it by taste.
- FIX unborn-branch rendering (certeus, zero commits): `git rev-parse
  --abbrev-ref HEAD` prints "HEAD" AND fails on an unborn branch, so
  `|| echo` fallbacks produced two-line branch strings across watch,
  statusline, smoke, review.sh, and the gate. All six capture sites now use
  `git symbolic-ref --short -q HEAD`. Preflight also warns loudly when a
  repo has no commits: commit the scaffold BEFORE starting a driver.
- MANUAL: kickoff section restores the Rule 1→4 plan-approval beat (plan
  approved once, then autonomy); new section on the deliberate stops
  (irreversibles) and the two operator chores (triage `## Noticed`; demand
  Rule 8 checkpoints from lost sessions).

## v4.0.2 — July 7, 2026
- Security fixes from the first manual Codex security review (run via CLI
  against anvil PR #1):
  - smoke.yml read smoke_cmd from the PR checkout — a PR could choose what
    executes on the self-hosted host. The command now comes from the BASE
    branch config only. Residual stated in the workflow: PR code still runs
    under that command; self-hosted smoke assumes a private, no-fork repo.
  - pulse.sh now redacts common credential shapes (API keys, gh/AWS/slack
    tokens, JWTs) before prompt/command text persists to the event feed.
- Docs honesty pass: "Codex Security" does not exist as a separate product —
  what exists is Codex cloud code review (GitHub App, fires on PR open,
  per-repo), which reads AGENTS.md and therefore arrives security-briefed via
  its standing "Security review (always)" section. SETUP/MANUAL/MODELS/rules/
  review.sh all renamed accordingly; PR-time security = floor scanners +
  security-briefed cloud review + the manual security-scoped CLI pass.
- watch: NEEDS-HUMAN renders as a real list (open-checkbox count, first three
  items, +N overflow; checked items drop off); statusline shows ⏸ HUMAN×N.
  Task header now shows the session's LATEST human prompt — on long-lived
  driver sessions the first prompt stops being "the task" within hours.
- Pins @v4.0.2. Tag v4.0.2 on push.

## v4.0.1 — July 7, 2026
- FIX anvil PR #1 "CI didn't fire": v4.0 placed the gitleaks permissions at
  the floor's WORKFLOW level, narrowing every job — the nested osv reusable
  workflow then requested security-events/actions permissions its caller no
  longer held, and GitHub refuses to START such a workflow (startup_failure,
  no check runs on the PR — only Smoke, a separate workflow, reported).
  Permissions now live at job level; the caller ci.yml grants the union.
- Dogfood: the Plinth repo is now a Plinth project (init on itself). The
  sources (shared/, templates/, bin/, workflow files) are the product, fully
  reviewable; the installed copies are the pinned previous release acting as
  the instrument. Custom protected-paths ((^|plinth/) anchoring) and
  AGENTS-project.md encode the split; SPEC.md points at MANUAL.md +
  CHANGELOG.md; this repo's smoke.yml scaffolds a fixture on ubuntu instead
  of targeting self-hosted hardware. Harness changes now pass through the
  same review loop, Stop gate, and floor as every other project.
- review.sh: HARNESS_RE is root-anchored (^ not (^|/)) so subdirectory
  copies — e.g. this repo's shared/ sources — are never mis-routed as
  UPSTREAM tooling; and hoisted to global scope, fixing the cross-model
  audit's blocking count (it previously tested against an empty regex, so
  audits always reported agreement).
- Pins @v4.0.1 (template + projects). Tag v4.0.1 on push — v4.0 was never
  a working release for callers; leave its tag be, nothing should pin it.

## v4.0 — July 6, 2026
The blind-spot release: every truth source the two instruments (CI, review)
could not see gets its own instrument. Plus the fixes surfaced by anvil PR #1.

Execution evidence (ends the static-guessing treadmill):
- NEW per-project Smoke workflow (smoke.yml, copied once): runs the set-once
  `smoke_cmd` from .plinth/config on a self-hosted runner on every PR and
  uploads the receipt — the run gate's supply side stops waiting on a human.
  No-ops green until smoke_cmd is set; make it a required check once real.
  Runner setup is a one-time block in the MANUAL ("The smoke runner").
- NEW `plinth smoke <repo> -- <cmd>`: runs the real thing, writes a SHA-bound
  receipt (.plinth/session/run/<branch>/receipt.json — cmd, exit, duration,
  hardware, log tail). Failures are data.
- Projects declare execution-gated paths in .plinth/config (`exec_gated`).
  Reviewer marks runtime-truth findings "RUNTIME:"; the effective verdict
  treats them as non-blocking ONLY when both keys agree (prefix + path match).
  They join the run gate; receipts are fed into review prompts so the next
  round verifies against observation.

Human-in-the-loop protocol:
- `.plinth/NEEDS-HUMAN.md` is the blocked-on-human queue (rules tell the
  driver to use it and keep working). watch shows a red NEEDS-HUMAN banner;
  statusline shows ⏸ HUMAN.

Budget visibility (advisory by principle — the system continues loudly, it
never parks the loop waiting for a human; hard stops are reserved for
irreversibles like deps/secrets/merges):
- Rounds costlier than round_budget (default 4000000 input tokens) print a
  loud NOTE and keep going. Per-round usage ledger (usage.jsonl) feeds a
  reviewer-total Σ in watch — the human interrupts if it looks wrong.
  Config is agent-immutable (protected-paths); its knob surface is
  deliberately two set-once keys: spec_path and exec_gated.

External-drift canary:
- NEW plinth-canary.yml (weekly cron + manual): runs the floor against this
  repo (do all pinned actions still resolve/run?) and scaffolds a fixture
  project exercising review.sh's fail-loud paths without codex. Rot surfaces
  on a schedule, not inside a real PR.

Spec attack:
- When a diff changes the canonical spec, the review round explicitly attacks
  the spec changes for ambiguity/untestability/contradiction (AGENTS.md).

Reviewer error bar:
- `audit_model` in .plinth/config: every 5th binding approval triggers a cold
  cross-model audit round; disagreement is recorded in verdict.json and
  reported loudly — never auto-adjudicated. Off until you pick a model.

Concurrency:
- Review/run session state is now branch-keyed (.plinth/session/review/<slug>/,
  .plinth/session/run/<slug>/); gate, watch, statusline follow. Parallel
  branches no longer fight over verdict.json. Existing mid-loop state at the
  old path is ignored — the next review starts a fresh round 1 (one-time cost).

Anvil PR #1 fixes (merge-gate shakedown):
- gitleaks "Resource not accessible by integration": the floor and template
  ci.yml now carry the permissions chain (contents: read, pull-requests:
  write, + actions: read / security-events: write for osv's reusable
  workflow). Called workflows can't escalate, so callers must grant.
- osv v1-tag retirement was fixed in v3.15 (reusable workflow @v2.3.8);
  carried forward unchanged.
- Template ci.yml pins @v4.0. EXISTING PROJECTS: replace/patch ci.yml
  (permissions block + pins), add `(^|/)\.plinth/config$` to protected-paths,
  and tag plinth v4.0 on push (the harness job clones by tag).

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
