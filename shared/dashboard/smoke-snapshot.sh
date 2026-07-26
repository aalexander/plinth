#!/usr/bin/env bash
# Offline smoke for `plinth dash --snapshot`. Builds a fixture project with a
# fake .plinth/session and asserts the JSON shape — no long-lived server.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLINTH="${ROOT}/bin/plinth"
[ -x "$PLINTH" ] || { echo "smoke-snapshot: missing $PLINTH" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "smoke-snapshot: jq required" >&2; exit 1; }

FIX="$(mktemp -d "${TMPDIR:-/tmp}/plinth-dash-smoke.XXXXXX")"
cleanup() { rm -rf "$FIX"; }
trap cleanup EXIT

# Fixture A: active session + verdict + NEEDS-HUMAN + events
A="$FIX/alpha"
mkdir -p "$A/.plinth/session/review/feat-dash" "$A/.git"
printf 'spec_path = SPEC.md\n' > "$A/.plinth/config"
# Minimal git identity so rev-parse works
git -C "$A" init -q
git -C "$A" config user.email "smoke@plinth.test"
git -C "$A" config user.name "plinth smoke"
echo ok > "$A/README"
git -C "$A" add -A
git -C "$A" commit -qm "init"
git -C "$A" checkout -qb feat/dash
echo x > "$A/f.txt"
git -C "$A" add -A
git -C "$A" commit -qm "work"
HEAD="$(git -C "$A" rev-parse --short HEAD)"
FULL="$(git -C "$A" rev-parse HEAD)"

NOW="$(date +%s)"
# events.jsonl — one session with a prompt
jq -nc --argjson epoch "$NOW" \
  '{ts:"2026-01-01T00:00:00Z",epoch:$epoch,event:"SessionStart",sid:"sid-smoke",transcript:null,tool:null,detail:null,rc:null}' \
  > "$A/.plinth/session/events.jsonl"
jq -nc --argjson epoch "$((NOW - 10))" \
  '{ts:"2026-01-01T00:00:10Z",epoch:$epoch,event:"UserPromptSubmit",sid:"sid-smoke",transcript:null,tool:null,detail:"smoke dashboard task",rc:null}' \
  >> "$A/.plinth/session/events.jsonl"

jq -nc --arg sha "$FULL" \
  '{verdict:"CHANGES_NEEDED",sha:$sha,round:2,mode:"fresh",model:"gpt-test",
    risk:{tier:1,files:1,reasons:["test"]},ts:"2026-01-01T00:00:00Z"}' \
  > "$A/.plinth/session/review/feat-dash/verdict.json"

printf '%s\n' '# Queue' '- [ ] [BLOCKING] need human decision' '- [ ] optional follow-up' \
  > "$A/.plinth/NEEDS-HUMAN.md"

# Fixture B: feedless project (config only, no events)
B="$FIX/beta"
mkdir -p "$B/.plinth/session"
printf 'spec_path = SPEC.md\n' > "$B/.plinth/config"
git -C "$B" init -q
git -C "$B" config user.email "smoke@plinth.test"
git -C "$B" config user.name "plinth smoke"
echo ok > "$B/README"
git -C "$B" add -A
git -C "$B" commit -qm "init"

export PLINTH_DASH_ROOTS="$A:$B"
OUT="$FIX/out.json"
"$PLINTH" dash --snapshot > "$OUT"

echo "smoke-snapshot: snapshot written ($OUT)"
jq -e . "$OUT" >/dev/null

# Top-level shape
jq -e 'has("generated_at") and has("discovery") and has("projects")' "$OUT" >/dev/null
jq -e '.discovery == "env:PLINTH_DASH_ROOTS"' "$OUT" >/dev/null
jq -e '(.projects | length) == 2' "$OUT" >/dev/null

# Alpha assertions
jq -e --arg head "$HEAD" '
  .projects[] | select(.name == "alpha")
  | .branch == "feat/dash"
  and .head == $head
  and .feedless == false
  and .needs_human.open == 2
  and .needs_human.blocking == 1
  and .review.verdict == "CHANGES_NEEDED"
  and .review.round == 2
  and .review.stale == false
  and .review.running == false
  and .task == "smoke dashboard task"
  and .quota.available == false
  and (.quota.note | type == "string")
  and (.activity_secs_ago != null)
' "$OUT" >/dev/null

# Beta feedless
jq -e '
  .projects[] | select(.name == "beta")
  | .feedless == true
  and .review == null
  and .activity_secs_ago == null
  and .quota.available == false
' "$OUT" >/dev/null

# Empty roots still valid JSON
export PLINTH_DASH_ROOTS="/nonexistent/path/nope"
EMPTY="$FIX/empty.json"
"$PLINTH" dash --snapshot > "$EMPTY"
jq -e '.projects == [] and has("generated_at")' "$EMPTY" >/dev/null

echo "smoke-snapshot: OK"
