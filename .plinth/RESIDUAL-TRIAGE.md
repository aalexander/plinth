# Residual triage (v5 thrash list → 2026-07-29)

Source: bound residual at land (`RESIDUAL.json`, 12 items). Disposition after
code inspection on `main` @ 5.0.1+ and small follow-up fixes in this branch.

| # | Severity | Topic | Disposition |
|---|----------|--------|-------------|
| 1 | major | Corrupt phase → empty → ship | **FIXED** (5.0.x fail-closed harden) |
| 2 | major | Encoded dir masks legacy verdict | **FIXED** (`_lifecycle_review_dir` prefers `verdict.json`) |
| 3 | major | Tier-0 floor ignores legacy phase | **FIXED** (legacy phase path fallback) |
| 4 | major | HANDOFF Goal discarded under placeholder | **FIXED** (keep freeform if any non-edit line) |
| 5 | major | Error card omits `lifecycle` | **FIXED** this PR |
| 6 | major | Canary depth for lifecycle guarantees | **KEEP** — follow-up canary expansion (not ship-blocking) |
| 7 | minor | Slug `%` collision | **DROP** — exotic branch names; revisit if dogfood hits it |
| 8 | minor | LIFECYCLE.md sticky overstatement | **FIXED** this PR (docs) |
| 9 | minor | Deep-plan seat setdefault | **FIXED** this PR |
| 10 | minor | Codex quota full-file read | **DROP** — asymptotic local |
| 11 | minor | Sub-cent cost strip | **DROP** — asymptotic UI |
| 12 | minor | HANDOFF Next sed optional prefix | **FIXED** this PR |

**Still open (not residual thrash):** plinth#51 remaining scope beyond #49 bare-merge
(infra fail-closed on `git diff` / base config probe) — see NEEDS-HUMAN if reopened.

**Operator action:** re-bind residual after this PR lands, or clear `RESIDUAL.json`
when shipping with full APPROVED@HEAD instead.
