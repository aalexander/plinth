#!/usr/bin/env bash
# Offline smoke for `plinth dash --snapshot`. Fixture matrix covers the cases
# that previously passed an under-specified smoke while failing in targeted
# repros (tilde expansion, detached HEAD, core.abbrev, multi-digit request
# rounds, completed NEEDS-HUMAN, malformed side-files, discovery modes).
# Server/UI is out of scope here (loopback bind is structural + unit-checked
# via --snapshot parity); CI runs this script from the canary scaffold job.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLINTH="${ROOT}/bin/plinth"
[ -x "$PLINTH" ] || { echo "smoke-snapshot: missing $PLINTH" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "smoke-snapshot: jq required" >&2; exit 1; }

FIX="$(mktemp -d "${TMPDIR:-/tmp}/plinth-dash-smoke.XXXXXX")"
cleanup() { rm -rf "$FIX"; }
trap cleanup EXIT

mk_git() {
  local d="$1"
  mkdir -p "$d/.plinth/session"
  printf 'spec_path = SPEC.md\n' > "$d/.plinth/config"
  git -C "$d" init -q
  git -C "$d" config user.email "smoke@plinth.test"
  git -C "$d" config user.name "plinth smoke"
  echo ok > "$d/README"
  git -C "$d" add -A
  git -C "$d" commit -qm "init"
}

# ── Fixture A: active session + verdict + NEEDS-HUMAN open + events ──────────
A="$FIX/alpha"
mk_git "$A"
git -C "$A" checkout -qb feat/dash
echo x > "$A/f.txt"
git -C "$A" add -A
git -C "$A" commit -qm "work"
HEAD="$(git -C "$A" rev-parse --short HEAD)"
FULL="$(git -C "$A" rev-parse HEAD)"

NOW="$(date +%s)"
jq -nc --argjson epoch "$NOW" \
  '{ts:"2026-01-01T00:00:00Z",epoch:$epoch,event:"SessionStart",sid:"sid-smoke",transcript:null,tool:null,detail:null,rc:null}' \
  > "$A/.plinth/session/events.jsonl"
jq -nc --argjson epoch "$((NOW - 10))" \
  '{ts:"2026-01-01T00:00:10Z",epoch:$epoch,event:"UserPromptSubmit",sid:"sid-smoke",transcript:null,tool:null,detail:"smoke dashboard task",rc:null}' \
  >> "$A/.plinth/session/events.jsonl"

mkdir -p "$A/.plinth/session/review/feat-dash"
jq -nc --arg sha "$FULL" \
  '{verdict:"CHANGES_NEEDED",sha:$sha,round:2,mode:"fresh",model:"gpt-test",
    risk:{tier:1,files:1,reasons:["test"]},ts:"2026-01-01T00:00:00Z"}' \
  > "$A/.plinth/session/review/feat-dash/verdict.json"

printf '%s\n' '# Queue' '- [ ] [BLOCKING] need human decision' '- [ ] optional follow-up' \
  > "$A/.plinth/NEEDS-HUMAN.md"

# ── Fixture B: feedless project (config only, no events) ─────────────────────
B="$FIX/beta"
mk_git "$B"

# ── Fixture C: detached HEAD with APPROVED under slug "detached" ─────────────
C="$FIX/gamma-detached"
mk_git "$C"
git -C "$C" checkout -qb feat/tmp
echo y > "$C/y.txt"
git -C "$C" add -A
git -C "$C" commit -qm "work"
CFULL="$(git -C "$C" rev-parse HEAD)"
git -C "$C" checkout -q --detach HEAD
mkdir -p "$C/.plinth/session/review/detached"
jq -nc --arg sha "$CFULL" \
  '{verdict:"APPROVED",sha:$sha,round:1,mode:"fresh",model:"gpt-test",
    risk:{tier:1,files:1,reasons:["test"]},ts:"2026-01-01T00:00:00Z"}' \
  > "$C/.plinth/session/review/detached/verdict.json"

# ── Fixture D: core.abbrev=12 must not false-stale a matching full SHA ───────
D="$FIX/delta-abbrev"
mk_git "$D"
git -C "$D" checkout -qb feat/abbrev
echo z > "$D/z.txt"
git -C "$D" add -A
git -C "$D" commit -qm "work"
git -C "$D" config core.abbrev 12
DFULL="$(git -C "$D" rev-parse HEAD)"
mkdir -p "$D/.plinth/session/review/feat-abbrev"
jq -nc --arg sha "$DFULL" \
  '{verdict:"APPROVED",sha:$sha,round:1,mode:"fresh",model:"gpt-test",
    risk:{tier:1,files:1,reasons:["test"]},ts:"2026-01-01T00:00:00Z"}' \
  > "$D/.plinth/session/review/feat-abbrev/verdict.json"

# ── Fixture E: path with '-' + request-2 + request-10 → newest is round 10 ───
E="$FIX/epsilon-hyphen"
mk_git "$E"
git -C "$E" checkout -qb feat/req
echo e > "$E/e.txt"
git -C "$E" add -A
git -C "$E" commit -qm "work"
EFULL="$(git -C "$E" rev-parse HEAD)"
mkdir -p "$E/.plinth/session/review/feat-req"
jq -nc --arg sha "$EFULL" \
  '{verdict:"CHANGES_NEEDED",sha:$sha,round:1,mode:"fresh",model:"gpt-test",
    risk:{tier:1,files:1,reasons:["test"]},ts:"2026-01-01T00:00:00Z"}' \
  > "$E/.plinth/session/review/feat-req/verdict.json"
jq -nc '{round:2,mode:"resume",model:"gpt-test"}' \
  > "$E/.plinth/session/review/feat-req/request-2.json"
jq -nc '{round:10,mode:"resume",model:"gpt-test"}' \
  > "$E/.plinth/session/review/feat-req/request-10.json"

# ── Fixture F: completed NEEDS-HUMAN (checked only) → open 0 ─────────────────
F="$FIX/zeta-done"
mk_git "$F"
printf '%s\n' '# Queue' '- [x] already done' '- [x] also done' \
  > "$F/.plinth/NEEDS-HUMAN.md"

# ── Fixture G: malformed usage.jsonl must not zero real NEEDS-HUMAN ──────────
G="$FIX/eta-badusage"
mk_git "$G"
git -C "$G" checkout -qb feat/bad
echo g > "$G/g.txt"
git -C "$G" add -A
git -C "$G" commit -qm "work"
GFULL="$(git -C "$G" rev-parse HEAD)"
mkdir -p "$G/.plinth/session/review/feat-bad"
jq -nc --arg sha "$GFULL" \
  '{verdict:"APPROVED",sha:$sha,round:1,mode:"fresh",model:"gpt-test",
    risk:{tier:1,files:1,reasons:["test"]},ts:"2026-01-01T00:00:00Z"}' \
  > "$G/.plinth/session/review/feat-bad/verdict.json"
printf 'not-json{\n' > "$G/.plinth/session/review/feat-bad/usage.jsonl"
printf '%s\n' '- [ ] [BLOCKING] still open after bad usage' \
  > "$G/.plinth/NEEDS-HUMAN.md"

# ── Fixture H: transcript burn (observed tokens) ─────────────────────────────
H="$FIX/theta-burn"
mk_git "$H"
git -C "$H" checkout -qb feat/burn
echo h > "$H/h.txt"
git -C "$H" add -A
git -C "$H" commit -qm "work"
HTR="$H/.plinth/session/transcript.jsonl"
# One assistant usage line within the 5-min window (epoch now).
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
jq -nc --arg ts "$TS" \
  '{type:"assistant",timestamp:$ts,message:{model:"claude-test",usage:{input_tokens:100,output_tokens:50,cache_creation_input_tokens:0}}}' \
  > "$HTR"
jq -nc --argjson epoch "$NOW" --arg tr "$HTR" \
  '{ts:"2026-01-01T00:00:00Z",epoch:$epoch,event:"SessionStart",sid:"sid-burn",transcript:$tr,tool:null,detail:null,rc:null}' \
  > "$H/.plinth/session/events.jsonl"

export PLINTH_DASH_ROOTS="$A:$B:$C:$D:$E:$F:$G:$H"
OUT="$FIX/out.json"
"$PLINTH" dash --snapshot > "$OUT"

echo "smoke-snapshot: snapshot written ($OUT)"
jq -e . "$OUT" >/dev/null

# Top-level shape
jq -e 'has("generated_at") and has("discovery") and has("projects")' "$OUT" >/dev/null
jq -e '.discovery == "env:PLINTH_DASH_ROOTS"' "$OUT" >/dev/null
jq -e '(.projects | length) == 8' "$OUT" >/dev/null

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
  and (.error == null or .error == "")
' "$OUT" >/dev/null

# Beta feedless
jq -e '
  .projects[] | select(.name == "beta")
  | .feedless == true
  and .review == null
  and .activity_secs_ago == null
  and .quota.available == false
' "$OUT" >/dev/null

# Detached HEAD finds verdict under "detached"
jq -e '
  .projects[] | select(.name == "gamma-detached")
  | .branch == "detached"
  and .review != null
  and .review.verdict == "APPROVED"
  and .review.stale == false
' "$OUT" >/dev/null

# core.abbrev=12: matching full SHA is not stale
jq -e '
  .projects[] | select(.name == "delta-abbrev")
  | .review.verdict == "APPROVED"
  and .review.stale == false
' "$OUT" >/dev/null

# Multi-digit request: round 10 wins over round 2 (path has hyphen)
jq -e '
  .projects[] | select(.name == "epsilon-hyphen")
  | .review.running == true
  and .review.round == 10
' "$OUT" >/dev/null

# Completed queue → open 0 (not headings/checked lines)
jq -e '
  .projects[] | select(.name == "zeta-done")
  | .needs_human.open == 0
  and .needs_human.blocking == 0
' "$OUT" >/dev/null

# Malformed usage must not zero NEEDS-HUMAN or drop the project
jq -e '
  .projects[] | select(.name == "eta-badusage")
  | .needs_human.open == 1
  and .needs_human.blocking == 1
  and .review.verdict == "APPROVED"
  and (.error == null or .error == "")
' "$OUT" >/dev/null

# Transcript burn observed
jq -e '
  .projects[] | select(.name == "theta-burn")
  | .tokens_total == 150
  and .burn_per_min != null
  and .model_driver == "claude-test"
' "$OUT" >/dev/null

# Empty roots still valid JSON
export PLINTH_DASH_ROOTS="/nonexistent/path/nope"
EMPTY="$FIX/empty.json"
"$PLINTH" dash --snapshot > "$EMPTY"
jq -e '.projects == [] and has("generated_at")' "$EMPTY" >/dev/null

# ── Config-file discovery + ~/ expansion ─────────────────────────────────────
unset PLINTH_DASH_ROOTS
CFG_HOME="$FIX/home"
mkdir -p "$CFG_HOME/.config/plinth" "$FIX/Dev/tilde-proj"
# Real project under a path we will reference via ~/Dev/tilde-proj
mk_git "$FIX/Dev/tilde-proj"
# Point HOME at our fixture so ~/.config and ~/ expand into FIX.
export HOME="$CFG_HOME"
# Create a symlink so ~/Dev resolves into FIX/Dev
ln -s "$FIX/Dev" "$CFG_HOME/Dev"
printf '%s\n' '# comment' '~/Dev/tilde-proj' > "$CFG_HOME/.config/plinth/dashboard-projects"
CFG_OUT="$FIX/cfg.json"
"$PLINTH" dash --snapshot > "$CFG_OUT"
jq -e '.discovery == "config:~/.config/plinth/dashboard-projects"' "$CFG_OUT" >/dev/null
jq -e '(.projects | length) == 1 and .projects[0].name == "tilde-proj"' "$CFG_OUT" >/dev/null

# Default discovery via PLINTH_DASH_DEV_ROOT
rm -f "$CFG_HOME/.config/plinth/dashboard-projects"
export PLINTH_DASH_DEV_ROOT="$FIX/Dev"
DEF_OUT="$FIX/def.json"
"$PLINTH" dash --snapshot > "$DEF_OUT"
jq -e '.discovery == "default:~/Dev/*/.plinth/config"' "$DEF_OUT" >/dev/null
jq -e '(.projects | length) >= 1 and ([.projects[].name] | index("tilde-proj") != null)' "$DEF_OUT" >/dev/null

# Port range validation (serve path — fails before bind)
rc=0
"$PLINTH" dash --port 0 >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { echo "smoke-snapshot: --port 0 should fail" >&2; exit 1; }
rc=0
"$PLINTH" dash --port 70000 >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { echo "smoke-snapshot: --port 70000 should fail" >&2; exit 1; }

echo "smoke-snapshot: OK"
