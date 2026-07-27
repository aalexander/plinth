# Plinth lifecycle — command reference card

**Version:** 5.0.0 · **Ship gate:** always `APPROVED@HEAD`  
**Default phase:** **build** (Stop does **not** force review)

```
plinth plan [--deep]  →  build  →  plinth harden  →  ./review.sh  →  PR
```

**In-session:** all of these run from a driver shell in the repo (or `bin/plinth` from a Plinth checkout).  
**Restart:** `Read HANDOFF.md and continue from ## Next.`

---

## Cheat sheet

| When | Command |
|------|---------|
| Light plan scaffold | `plinth plan [path]` |
| Deep plan (3 agent critiques) | `plinth plan --deep [path]` |
| Phase | `plinth phase [path]` |
| Ship-prep | `plinth harden [path]` |
| Back to build | `plinth build [path]` |
| Handoff file | `plinth handoff [path]` |
| Review | `./.plinth/review.sh [base]` |
| Advisor | `plinth advise "…"` |
| Dashboard | `plinth dash` / `plinth dash --snapshot` |
| PR | `gh pr create` *(needs APPROVED@HEAD)* |

`[path]` defaults to **CWD**.

---

## Happy paths

### Typical feature (light)

```bash
git checkout -b feat/my-thing
plinth plan                         # optional scaffold
# edit PLAN.md lightly or skip
# implement + commit
plinth handoff
plinth harden
./.plinth/review.sh
gh pr create
```

### New product (deep plan)

```bash
git checkout -b feat/new-product
plinth plan --deep                  # scaffold if needed + 3 parallel seats → PLAN-REVIEW.md
# human: resolve blockers/questions; edit PLAN.md
# implement…
plinth harden && ./.plinth/review.sh
gh pr create
```

### In this kind of agent session

```bash
bin/plinth plan                     # if plinth on PATH not updated yet
bin/plinth plan --deep
bin/plinth phase
bin/plinth harden
./.plinth/review.sh
bin/plinth handoff
```

Stop-hook behavior follows phase only if the harness runs `.claude` hooks (Claude yes; grok often no — ship still needs APPROVED).

---

## Phase vs ship

| Phase | Stop | Ship |
|-------|------|------|
| **build** (default) | OK without APPROVED (`build_defer`) | Blocked |
| **harden** | Needs APPROVED@HEAD | Blocked until APPROVED |

---

## Plan depth

| Command | Does |
|---------|------|
| `plinth plan` | Create `PLAN.md` skeleton if missing; never clobber |
| `plinth plan --deep` | Same + 3 parallel critics → `PLAN-REVIEW.md` |

Deep seats (from `.plinth/config`):  
1. **security_ops** — `reviewer_vendor` / tier2 model  
2. **completeness** — `audit_vendor` / audit_model  
3. **delete_simplify** — `advisor_vendor` / advisor_model_max  

Human adjudicates; majority is advisory only.

| Work | Depth |
|------|--------|
| Most features | light or skip |
| New product / fuzzy scope | `--deep` |
| Tiny hotfix | skip |

---

## Dashboard

Cards show:

- **BUILD** / **HARDEN** chip  
- **PLAN** / **PLAN-REVIEW** / **HANDOFF** if files present  
- lifecycle line (phase + ages)  
- existing review verdict / rounds / NEEDS-HUMAN  

`build_defer` is a known event (does not break snapshot parse).  
Requires current `bin/plinth` + `shared/dashboard/index.html` (this release).

```bash
plinth dash --snapshot | jq '.projects[] | {name, lifecycle, review}'
```

---

## Install

```bash
plinth update /path/to/project   # Stop hook + rules from shared/
```

---

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Stop still forces review | `plinth phase`; hooks updated? |
| `--deep` seats empty | CLIs installed/signed in? |
| Dash no lifecycle | Old plinth binary / old index.html |
| Lost context | `Read HANDOFF.md` or `plinth handoff` |
