#!/usr/bin/env bash
# Dashboard smoke for `plinth dash` (canary CI). Covers:
#   1. Offline --snapshot fixture matrix (tilde, detached, core.abbrev,
#      multi-digit request rounds, completed NEEDS-HUMAN, render failure,
#      discovery modes, burn, port validation).
#   2. Pure UI card render via node + globalThis.__plinthDash (error tone,
#      no-review suppression).
#   3. Short-lived loopback HTTP server (/, /api/snapshot, POST 405, 404),
#      with process-group cleanup so the python child cannot leak.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLINTH="${ROOT}/bin/plinth"
[ -x "$PLINTH" ] || { echo "smoke-snapshot: missing $PLINTH" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "smoke-snapshot: jq required" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "smoke-snapshot: node required for UI card unit test" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "smoke-snapshot: curl required for server check" >&2; exit 1; }

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

# ── Fixture G: unused/malformed usage.jsonl is ignored (not read) ────────────
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

# ── Fixture I: malformed verdict → real snapshot_render_failed, NH preserved ─
I="$FIX/iota-badverdict"
mk_git "$I"
git -C "$I" checkout -qb feat/badv
echo i > "$I/i.txt"
git -C "$I" add -A
git -C "$I" commit -qm "work"
mkdir -p "$I/.plinth/session/review/feat-badv"
printf 'not-json{\n' > "$I/.plinth/session/review/feat-badv/verdict.json"
printf '%s\n' '- [ ] [BLOCKING] keep me through render failure' \
  > "$I/.plinth/NEEDS-HUMAN.md"

export PLINTH_DASH_ROOTS="$A:$B:$C:$D:$E:$F:$G:$H:$I"
OUT="$FIX/out.json"
"$PLINTH" dash --snapshot > "$OUT"

echo "smoke-snapshot: snapshot written ($OUT)"
jq -e . "$OUT" >/dev/null

# Top-level shape
jq -e 'has("generated_at") and has("discovery") and has("projects")' "$OUT" >/dev/null
jq -e '.discovery == "env:PLINTH_DASH_ROOTS"' "$OUT" >/dev/null
jq -e '(.projects | length) == 9' "$OUT" >/dev/null

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

# Malformed unused usage must not break a healthy card
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

# Real render failure: error field set, NH counts preserved, project not dropped
jq -e '
  .projects[] | select(.name == "iota-badverdict")
  | .error == "snapshot_render_failed"
  and .needs_human.open == 1
  and .needs_human.blocking == 1
  and .review == null
' "$OUT" >/dev/null

# ── Pure UI card render (node + __plinthDash seam) ───────────────────────────
# Fails if error tone or no-review suppression is broken — not just source greps.
PLINTH_DASH_HTML="$ROOT/shared/dashboard/index.html" node <<'NODE'
const fs = require("fs");
const vm = require("vm");
const path = process.env.PLINTH_DASH_HTML;
const html = fs.readFileSync(path, "utf8");
const m = html.match(/<script>\s*([\s\S]*?)\s*<\/script>\s*<\/body>/i);
if (!m) { console.error("no script block"); process.exit(2); }
const el = () => {
  const o = { textContent: "", className: "", innerHTML: "" };
  o.querySelector = () => null;
  return o;
};
const sandbox = {
  console,
  Date, Math, String, Number, JSON, Array, Object, parseInt, isNaN,
  setInterval: () => 0,
  clearInterval: () => {},
  // Hang forever so poll never mutates state under test.
  fetch: () => new Promise(() => {}),
  document: { getElementById: () => el() },
};
sandbox.globalThis = sandbox;
sandbox.window = sandbox;
vm.createContext(sandbox);
vm.runInContext(m[1], sandbox);
const api = sandbox.__plinthDash;
if (!api || typeof api.cardHTML !== "function" || typeof api.cardTone !== "function") {
  console.error("missing __plinthDash.cardHTML/cardTone");
  process.exit(2);
}
const errProj = {
  error: "snapshot_render_failed",
  name: "iota", path: "/tmp/iota", branch: "feat/badv", head: "abc1234",
  needs_human: { open: 1, blocking: 1 },
  feedless: false, review: null,
};
if (api.cardTone(errProj) !== "bad") {
  console.error("cardTone(error) expected bad, got", api.cardTone(errProj));
  process.exit(1);
}
const htmlCard = api.cardHTML(errProj);
if (!htmlCard.includes('class="card bad"')) {
  console.error("error card missing tone class bad");
  process.exit(1);
}
if (!htmlCard.includes("error: snapshot_render_failed")) {
  console.error("error chip missing from cardHTML");
  process.exit(1);
}
if (htmlCard.includes("no review")) {
  console.error("error card must not show 'no review'");
  process.exit(1);
}
if (!htmlCard.includes("NEEDS-HUMAN ×1")) {
  console.error("error card must still show NEEDS-HUMAN");
  process.exit(1);
}
// Healthy idle: no review chip present, tone idle
const idle = {
  name: "beta", path: "/tmp/beta", branch: "main", head: "deadbee",
  feedless: true, review: null, needs_human: { open: 0, blocking: 0 },
};
if (api.cardTone(idle) !== "idle") {
  console.error("cardTone(idle) expected idle");
  process.exit(1);
}
const idleHtml = api.cardHTML(idle);
if (!idleHtml.includes("no review")) {
  console.error("idle card should show no review");
  process.exit(1);
}
// XSS escape
const xss = api.esc('<script>"x"');
if (xss.includes("<") || xss.includes('"')) {
  console.error("esc failed:", xss);
  process.exit(1);
}
console.log("ui-card-unit: OK");
NODE

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
ln -sfn "$FIX/Dev" "$CFG_HOME/Dev"
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
rc=0
"$PLINTH" dash --port 99999999999999999999999 >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { echo "smoke-snapshot: oversized --port should fail cleanly" >&2; exit 1; }
rc=0
PLINTH_DASH_PORT=0 "$PLINTH" dash >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { echo "smoke-snapshot: PLINTH_DASH_PORT=0 should fail" >&2; exit 1; }
rc=0
PLINTH_DASH_PORT=notaport "$PLINTH" dash >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { echo "smoke-snapshot: PLINTH_DASH_PORT=notaport should fail" >&2; exit 1; }
rc=0
PLINTH_DASH_PORT=99999999999999999999999 "$PLINTH" dash >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || { echo "smoke-snapshot: oversized PLINTH_DASH_PORT should fail" >&2; exit 1; }

# ── Short-lived server: loopback HTTP surface ────────────────────────────────
# Process group + child kill so the python ThreadingHTTPServer cannot leak.
export PLINTH_DASH_ROOTS="$A:$I"
export HOME="$CFG_HOME"
SRV_PORT=18734
for try in 18734 18735 18736 18737 18738 18739 18740; do
  SRV_PORT="$try"
  if command -v lsof >/dev/null 2>&1; then
    if lsof -nP -iTCP:"$SRV_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
      continue
    fi
  fi
  break
done
# setsid when available → kill the whole group; else pkill children + lsof port.
if command -v setsid >/dev/null 2>&1; then
  setsid "$PLINTH" dash --port "$SRV_PORT" >"$FIX/srv.out" 2>"$FIX/srv.err" &
  SRV_PID=$!
  srv_cleanup() {
    kill -TERM -"$SRV_PID" 2>/dev/null || true
    kill -TERM "$SRV_PID" 2>/dev/null || true
    wait "$SRV_PID" 2>/dev/null || true
    if command -v lsof >/dev/null 2>&1; then
      local p; p="$(lsof -tiTCP:"$SRV_PORT" -sTCP:LISTEN 2>/dev/null || true)"
      [ -n "$p" ] && kill -TERM $p 2>/dev/null || true
    fi
  }
else
  "$PLINTH" dash --port "$SRV_PORT" >"$FIX/srv.out" 2>"$FIX/srv.err" &
  SRV_PID=$!
  srv_cleanup() {
    local kids
    kids="$(pgrep -P "$SRV_PID" 2>/dev/null || true)"
    [ -n "$kids" ] && kill -TERM $kids 2>/dev/null || true
    kill -TERM "$SRV_PID" 2>/dev/null || true
    wait "$SRV_PID" 2>/dev/null || true
    if command -v lsof >/dev/null 2>&1; then
      local p; p="$(lsof -tiTCP:"$SRV_PORT" -sTCP:LISTEN 2>/dev/null || true)"
      [ -n "$p" ] && kill -TERM $p 2>/dev/null || true
    fi
  }
fi
trap 'srv_cleanup; cleanup' EXIT
ready=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if curl -sf "http://127.0.0.1:${SRV_PORT}/api/snapshot" >/dev/null 2>&1; then
    ready=1; break
  fi
  if ! kill -0 "$SRV_PID" 2>/dev/null; then
    echo "smoke-snapshot: server exited early:" >&2
    cat "$FIX/srv.err" >&2 || true
    exit 1
  fi
  sleep 0.15
done
[ "$ready" = 1 ] || { echo "smoke-snapshot: server did not become ready on :$SRV_PORT" >&2; cat "$FIX/srv.err" >&2; exit 1; }
# Static UI
curl -sf "http://127.0.0.1:${SRV_PORT}/" | grep -q 'Plinth dashboard' \
  || { echo "smoke-snapshot: / did not serve the UI" >&2; exit 1; }
# Snapshot API includes the render-failed project with NH preserved
curl -sf "http://127.0.0.1:${SRV_PORT}/api/snapshot" > "$FIX/api.json"
jq -e '
  (.projects | length) == 2
  and ([.projects[] | select(.name == "iota-badverdict")
        | .error == "snapshot_render_failed"
        and .needs_human.open == 1] | any)
' "$FIX/api.json" >/dev/null
# Read-only
post_code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:${SRV_PORT}/" || true)"
[ "$post_code" = "405" ] || { echo "smoke-snapshot: POST should be 405, got $post_code" >&2; exit 1; }
# Unknown path
nf_code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${SRV_PORT}/nope" || true)"
[ "$nf_code" = "404" ] || { echo "smoke-snapshot: unknown path should be 404, got $nf_code" >&2; exit 1; }
# Banner claims loopback
grep -q '127.0.0.1' "$FIX/srv.out" \
  || { echo "smoke-snapshot: server banner missing 127.0.0.1" >&2; exit 1; }
srv_cleanup
# Assert nothing is still listening on the port
if command -v lsof >/dev/null 2>&1; then
  if lsof -nP -iTCP:"$SRV_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "smoke-snapshot: server still listening on :$SRV_PORT after cleanup" >&2
    exit 1
  fi
fi
trap cleanup EXIT

echo "smoke-snapshot: OK"
