#!/usr/bin/env bash
# Plinth session-start recorder v1 (shared, version-pinned). Records HEAD at
# session start so the review gate (Stop hook) enforces only on sessions that
# create commits. Receives Claude Code SessionStart JSON on stdin.
# Never blocks; never writes to stdout (stdout would be injected as context).
set -euo pipefail
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
proj="${CLAUDE_PROJECT_DIR:-.}"

[ -n "$sid" ] || exit 0
git -C "$proj" rev-parse --git-dir >/dev/null 2>&1 || exit 0

SDIR="$proj/.plinth/session"
mkdir -p "$SDIR"
[ -f "$SDIR/.gitignore" ] || printf '*\n' > "$SDIR/.gitignore"

# Don't reset the baseline when an existing session is resumed — the gate would
# stop enforcing for commits made before the resume.
if [ ! -f "$SDIR/start-head-$sid" ]; then
  git -C "$proj" rev-parse HEAD > "$SDIR/start-head-$sid" 2>/dev/null \
    || echo "none" > "$SDIR/start-head-$sid"
fi

# Hygiene: session-scoped files older than 7 days; cap the event log.
find "$SDIR" -maxdepth 1 \( -name 'start-head-*' -o -name 'gate-blocks-*' \) -mtime +7 -delete 2>/dev/null || true
EV="$SDIR/events.jsonl"
if [ -f "$EV" ] && [ "$(wc -c < "$EV" | tr -d ' ')" -gt 5000000 ]; then
  tail -n 2000 "$EV" > "$EV.tmp" && mv "$EV.tmp" "$EV"
fi
exit 0
