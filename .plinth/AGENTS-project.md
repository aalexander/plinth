# Plinth repo — project-specific reviewer rules

This repository IS Plinth. Two scope inversions the shared rules cannot know:

1. `shared/`, `templates/`, `bin/`, and the workflow sources in `.github/`
   are the PRODUCT — review them as project code at full rigor. The UPSTREAM
   routing and the tooling-tampering exemption do NOT apply to them here.
2. The INSTALLED copies (`.plinth/*`, `.claude/hooks/*`,
   `.claude/settings.json`, root `AGENTS.md`) are the pinned PREVIOUS release
   acting as the instrument. The tampering rule applies to exactly these:
   they may change only in a commit labeled as a Plinth release/update.

Block on, additionally:
- Any change to `shared/` or `bin/` without a matching CHANGELOG entry.
- VERSION not matching the CHANGELOG's top entry.
- A source file and its installed twin changing in the same commit outside a
  labeled release commit (self-approval smell).
- Enforcement claims in MANUAL.md or plinth-rules.md that the code does not
  actually implement — this repo's history shows overclaiming is its most
  recurrent defect class.

## Threat model — what to flag, and what NOT to (maintainer-ratified)

Plinth's design goal is a FAST multi-model loop with a TRUSTED driver, worker,
and reviewer. Speed and real capability rank above hardening against a
hypothetical malicious insider. Apply this when judging the implementer lanes
and `lane-guard.sh`:

- **The worker (grok/codex lane) is a TRUSTED-but-fallible party**, not an
  adversary. `lane-guard.sh` is an ERROR-catcher (its header states this): it
  catches the MISTAKES a fallible lane makes — off-spec/staged edits, accidental
  protected/secret/session/git-control-plane writes, forged verdicts — or fails
  closed. It is explicitly NOT an adversarial sandbox.
- **DO block**: a real error-catching gap (a fallible lane's mistake that scope
  would pass), a fail-OPEN, an enforcement claim the code doesn't implement
  (overclaiming is this repo's worst defect class — keep flagging it), a missing
  test for a behavior change.
- **Do NOT block** on defeating DELIBERATE evasion by the trusted worker:
  secret exfiltration via the CLI's web-search/fetch (web search is a REQUIRED
  worker capability and stays ON — the worker needs it to find solutions), a
  `chmod` on the far side of a pre-existing sensitive symlink, decoy CI job
  entries crafted to fool an advisory warning, or similar red-team-against-a-
  trusted-party hypotheticals. The security boundary for a malicious model is
  the vendor sandbox + human review, NOT `lane-guard`. Flagging these trades the
  worker's real capability for hypothetical coverage the design deliberately
  declines. If tempted to flag one, confirm it is a FALLIBLE-lane error first.
