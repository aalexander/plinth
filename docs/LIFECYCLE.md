# Plinth lifecycle — command reference card

**Version:** 5.0.0 · **Ship gate:** always `APPROVED@HEAD` (unchanged)  
**Default phase:** **build** (Stop does **not** force review)

```
[optional plan] → build (default) → plinth harden → ./review.sh → PR/ship
```

Restart any session: **Read `HANDOFF.md` and continue.**

---

## One-screen cheat sheet

| When | Command |
|------|---------|
| See phase | `plinth phase [path]` |
| Enter ship-prep (Stop needs APPROVED) | `plinth harden [path]` |
| Back to default build | `plinth build [path]` |
| Refresh handoff file | `plinth handoff [path]` |
| Paid adversarial review | `./.plinth/review.sh [base]` |
| Advisor (any phase) | `plinth advise "…"` / `plinth advise --impactful "…"` |
| Open PR (needs APPROVED@HEAD) | `gh pr create …` |

`[path]` defaults to **CWD** for lifecycle commands.

---

## Happy paths

### A) Typical feature (light)

```bash
git checkout -b feat/my-thing
# implement + commit freely (build phase default)
plinth handoff                    # optional, end of session
# when product looks right:
plinth harden
./.plinth/review.sh               # fix → commit → re-run until exit 0
git push -u origin HEAD
gh pr create
```

### B) New product / ambiguous scope (deep planning)

```bash
git checkout -b feat/new-product
# Write PLAN.md: problem, users, non-goals, AC, risks, tradeoffs+recs
# Optional: 1–2 independent agents critique PLAN.md; human decides tradeoffs
plinth handoff
# implement…
plinth harden
./.plinth/review.sh
gh pr create
```

> **Note:** `plinth plan` / `plinth plan --deep` are **not shipped yet** in 5.0.0.
> Deep planning is **convention + PLAN.md + human** until that CLI lands.

### C) Leave harden without shipping

```bash
plinth build                      # Stop defers review again; ship still blocked
```

---

## Phase behavior

| Phase | How you get there | Stop gate | Ship (`gh pr create\|merge`) |
|-------|-------------------|-----------|------------------------------|
| **build** (default) | Missing phase file, or `plinth build` | Allows stop without APPROVED; logs `build_defer` | **Blocked** without APPROVED@HEAD |
| **harden** | `plinth harden` | **Requires** APPROVED@HEAD | **Blocked** until APPROVED@HEAD |

Phase state: `.plinth/session/phase-<slug>.json` (CLI-written only).

---

## Commands (detail)

### `plinth phase [project-path]`
Print current lifecycle phase, branch, and Stop implications.

### `plinth harden [project-path]`
- Sets phase → **harden**
- Stop will block until `./.plinth/review.sh` exits 0 at HEAD
- Refuses `main` / `master` / detached HEAD
- Does **not** run the reviewer for you

### `plinth build [project-path]`
- Sets phase → **build**
- Stop again allows end-of-turn without APPROVED
- Does **not** create APPROVED or open ship

### `plinth handoff [project-path]`
Writes/overwrites repo-root **`HANDOFF.md`** (goal, next, restart prompt, phase, verdict snippet).

**Restart phrase:**  
`Read HANDOFF.md and continue from ## Next.`

### `./.plinth/review.sh [base]`
- Default base: `main`
- Exit **0** = APPROVED@HEAD (+ receipt mint when applicable)
- Exit **1** = CHANGES_NEEDED — fix, commit, re-run
- Exit **2** = did not run (infra / dirty tree / empty diff / …)
- Run only when ship-ready (after `plinth harden`), not every micro-commit

### `plinth advise ["question"]`
Non-blocking judgment. Available in plan, build, and harden. Never replaces APPROVED.

### Ship (unchanged)
- Client: guard blocks `gh pr create|merge` without APPROVED@HEAD  
- Server: branch protection + CI (+ `receipt / verify` where wired)

---

## Choosing plan depth

| Situation | Depth |
|-----------|--------|
| Clear AC, small feature | **Light** — HANDOFF / short notes; skip formal plan |
| New product, unclear users/problem | **Deep** — full PLAN.md + multi-agent critique + human ratify |
| Tiny hotfix | **Minimal** — optional one-line AC |
| Trust boundary (auth, money, public API) | Prefer **deeper plan** and/or sooner `plinth harden` |

Rule of thumb: if a wrong product call wastes more than ~a week of build → deep; else light.

---

## Install / upgrade note

Product Stop hook ships in `shared/.claude/hooks/review-gate.sh`.  
Projects pick it up via **`plinth update`**. Until then, installed `.claude/hooks/` may still be the old “always require APPROVED” gate.

```bash
plinth update /path/to/project
# review diff, commit
```

---

## Quick troubleshooting

| Symptom | Check |
|---------|--------|
| Stop still forces review mid-build | Phase? `plinth phase` → should be `build`. Updated hooks? `plinth update` |
| Stop allows everything in harden | Ran `plinth harden`? Feature branch? |
| Can’t open PR | Need APPROVED@HEAD: `plinth harden` + `./.plinth/review.sh` |
| Lost context after compact | `Read HANDOFF.md` or `plinth handoff` then edit Next |

---

## Related docs

- Driver rules: `.plinth/plinth-rules.md` (lifecycle section; source `shared/plinth-rules.md`)
- Manual: `MANUAL.md` (commands + workflow)
- Changelog: `CHANGELOG.md` → v5.0.0
- Design backlog (full panel/dual ideas): session plan, not required for v5
