#!/usr/bin/env bash
# Plinth review gate v1 (shared, version-pinned). Stop hook: a session that
# created commits may not end its turn until ./.plinth/review.sh has recorded
# an APPROVED verdict at HEAD (.plinth/session/review/verdict.json).
# Receives Claude Code Stop JSON on stdin. Exit 2 = block (stderr shown to the
# model). Exit 0 = allow.
#
# Deliberately narrow: never enforces outside a git repo, without a SessionStart
# baseline, on sessions that made no commits, or on the base branch. Releases
# the session (loudly) after a recent infrastructure failure of review.sh, and
# after 5 blocks in one session — a gate, not a trap.
set -euo pipefail
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
proj="${CLAUDE_PROJECT_DIR:-.}"
SDIR="$proj/.plinth/session"
block() { echo "PLINTH REVIEW GATE: $1" >&2; exit 2; }

git -C "$proj" rev-parse --git-dir >/dev/null 2>&1 || exit 0
[ -n "$sid" ] || exit 0
[ -f "$SDIR/start-head-$sid" ] || exit 0          # no baseline recorded -> fail open
head=$(git -C "$proj" rev-parse HEAD 2>/dev/null) || exit 0
[ "$(cat "$SDIR/start-head-$sid")" != "$head" ] || exit 0   # no commits this session

branch=$(git -C "$proj" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)
case "$branch" in main|master|HEAD) exit 0 ;; esac  # base branch / detached: not this gate's job

# Infra escape: a recent mechanical review failure needs the human, not a trap
# that hides the breakage behind a session that can't end.
err="$SDIR/review/last-error"
if [ -f "$err" ] && [ -n "$(find "$err" -mmin -30 2>/dev/null)" ]; then
  echo "PLINTH REVIEW GATE: allowing stop despite missing approval — review.sh failed mechanically: $(cat "$err")" >&2
  exit 0
fi

# Anti-wedge cap.
cnt=$(cat "$SDIR/gate-blocks-$sid" 2>/dev/null || echo 0)
if [ "$cnt" -ge 5 ]; then
  echo "PLINTH REVIEW GATE: cap reached ($cnt blocks) — allowing stop WITHOUT an approved review. Committed work at $head is unreviewed." >&2
  exit 0
fi

vfile="$SDIR/review/verdict.json"
if [ -f "$vfile" ]; then
  v=$(jq -r '.verdict // empty' "$vfile" 2>/dev/null || echo "")
  vsha=$(jq -r '.sha // empty' "$vfile" 2>/dev/null || echo "")
  if [ "$v" = "APPROVED" ] && [ "$vsha" = "$head" ]; then exit 0; fi
fi

echo $((cnt + 1)) > "$SDIR/gate-blocks-$sid"
if [ -n "$(git -C "$proj" status --porcelain 2>/dev/null)" ]; then
  block "this session committed work, the tree is dirty, and there is no APPROVED review at HEAD. Commit (or stash), then run ./.plinth/review.sh; on exit 1 fix the findings, commit, re-run until it exits 0 (APPROVED). Then stop."
fi
block "this session committed work with no APPROVED review at HEAD ($head). Run ./.plinth/review.sh; on exit 1 fix the findings, commit, and re-run until it exits 0 (APPROVED). Then stop."
