bump: patch
---
- **Targeted `gh pr merge` binds to origin-resolved PR head (upstream #16).** A merge with a
  positional PR number/URL and/or `-R`/`--repo` (including `github.com/owner/repo`) is
  authorized only by APPROVED at the resolved PR head for that branch slug — not the
  checkout branch alone, not gh's default repo. Resolve always uses
  `gh pr view … -R <origin-owner/repo>`. Multi-segment Bash gates each real create/merge
  independently. Bare current-branch create/merge and outside-git bare fail-open are
  unchanged; targeted merges fail closed outside a git checkout or on unparseable argv.
