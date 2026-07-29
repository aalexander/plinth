#!/usr/bin/env bash
# Plan progress derivation + dashboard card surface (v5.0.8+)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLINTH="${PLINTH:-$ROOT/bin/plinth}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

# Extract production helper (same style as residual canaries).
python3 - "$ROOT/bin/plinth" "$TMP/pp_extract.sh" <<'PY'
from pathlib import Path
import sys
lines = Path(sys.argv[1]).read_text().splitlines(True)
start = next(i for i, l in enumerate(lines) if l.startswith("_plan_progress_json()"))
end = next(i for i in range(start + 1, len(lines)) if lines[i].startswith("# Classify snapshot kind"))
Path(sys.argv[2]).write_text("".join(lines[start:end]))
PY
# shellcheck disable=SC1090
. "$TMP/pp_extract.sh"

mkdir -p "$TMP/a/.plinth"
printf 'spec_path = SPEC.md\n' > "$TMP/a/.plinth/config"
cat > "$TMP/a/PLAN.md" <<'P'
# My product
## Acceptance criteria
- [x] First thing done
- [ ] Second thing open
- [ ] Third thing open
## Problem
Ignore this empty-ish section body.
P
cat > "$TMP/a/SPEC.md" <<'S'
# Spec
## Requirements
The system shall foo when ready.
S

out=$(_plan_progress_json "$TMP/a" '{}')
[ -n "$out" ] || fail "empty plan_progress"
echo "$out" | jq -e '.schema=="plinth.plan_progress/v1"' >/dev/null || fail "schema"
echo "$out" | jq -e '.primary=="PLAN.md" and .primary_kind=="plan"' >/dev/null || fail "primary"
echo "$out" | jq -e '.sources.spec=="SPEC.md"' >/dev/null || fail "spec coordinated in sources"
echo "$out" | jq -e '.done==1 and .total==3 and .pct_complete==33' >/dev/null \
  || fail "checkbox %: $(echo "$out" | jq '{done,total,pct_complete}')"
echo "$out" | jq -e '.current.title|test("Second")' >/dev/null || fail "current first open"
echo "$out" | jq -e '.progress_mode=="checkbox"' >/dev/null || fail "mode checkbox"
# cumulative end-% on leaves: 33,66,100 (approx; 3-way equal may be 34/67/100)
cums=$(echo "$out" | jq -c '[.outline[].children[]?.cum_pct_end]')
echo "$out" | jq -e '([.outline[].children[]?.cum_pct_end] | last) == 100' >/dev/null \
  || fail "cumulative last != 100: $cums"
echo "$out" | jq -e '
  ([.outline[].children[]?.cum_pct_end]) as $c
  | ($c|length) >= 2 and $c[0] < $c[1] and ($c|last)==100
' >/dev/null || fail "cumulative not increasing: $cums"
sum=$(echo "$out" | jq '[.outline[].children[]?.weight_pct // empty] | add')
[ "$sum" = "100" ] || fail "weights sum=$sum want 100"
# empty Problem section should not appear (no children)
echo "$out" | jq -e '[.outline[].title] | index("Problem") == null' >/dev/null \
  || fail "empty Problem section should be pruned"
pass "checkbox plan progress + source coordination + cumulative %"

# checkpoint cursor is authoritative (even when checkboxes still unchecked)
cat > "$TMP/a/PLAN.md" <<'P'
# My product
## Acceptance criteria
- [ ] Alpha first
- [ ] Beta second
- [ ] Gamma third
- [ ] Delta fourth
P
rt='{"slice_index":3,"slice_total":4,"slice_title":"Gamma third","status":"implementing"}'
outc=$(_plan_progress_json "$TMP/a" "$rt")
echo "$outc" | jq -e '.progress_mode=="checkpoint"' >/dev/null || fail "checkpoint mode: $(echo "$outc"|jq .progress_mode)"
echo "$outc" | jq -e '.pct_complete==50' >/dev/null || fail "checkpoint pct 50: $(echo "$outc"|jq .pct_complete)"
echo "$outc" | jq -e '.done==2 and (.current.title|test("Gamma"))' >/dev/null || fail "checkpoint current: $(echo "$outc"|jq '{done,current}')"
# prior items done + active shaded status
echo "$outc" | jq -e '[.outline[0].children[].status] == ["done","done","active","open"]' >/dev/null \
  || fail "status cascade: $(echo "$outc"|jq '[.outline[0].children[].status]')"
pass "checkpoint cursor authoritative over unchecked boxes"

# HANDOFF Done prose must NOT invent plan completion (certeus-class false positive)
cat > "$TMP/a/HANDOFF.md" <<'H'
# Handoff
## Done
- Branch renamed so its degraded review lineage cannot be mistaken for feature-freeze evidence.
## Next
1. keep going
H
# no routing — all AC still open
outfp=$(_plan_progress_json "$TMP/a" '{}')
echo "$outfp" | jq -e '.done==0' >/dev/null || fail "Done prose false positive: $(echo "$outfp"|jq '{done,outline}')"
pass "HANDOFF Done prose does not invent checkbox completion"

# notes / risks / tradeoffs are not stage points
cat > "$TMP/a/PLAN.md" <<'P'
# My product
## Acceptance criteria
- [ ] Real work A
- [ ] Real work B
## Risks / trust boundaries
- auth note should not appear as a stage
## Open tradeoffs
- tradeoff note should not appear
P
outw=$(_plan_progress_json "$TMP/a" '{}')
echo "$outw" | jq -e '[.outline[].title] == ["Acceptance criteria"]' >/dev/null \
  || fail "work-only titles: $(echo "$outw"|jq '[.outline[].title]')"
echo "$outw" | jq -e '.total==2' >/dev/null || fail "work-only total"
pass "notes/risks/tradeoffs omitted from stage track"

# implementation plan when no PLAN.md
rm -f "$TMP/a/PLAN.md"
cat > "$TMP/a/IMPLEMENTATION.md" <<'I'
# Impl
## Phase 1
- [ ] wire UI
- [x] data model
I
out2=$(_plan_progress_json "$TMP/a" '{}')
echo "$out2" | jq -e '.primary_kind=="implementation" and .primary=="IMPLEMENTATION.md"' >/dev/null \
  || fail "impl primary"
echo "$out2" | jq -e '.done==1 and .total==2' >/dev/null || fail "impl counts"
pass "implementation plan fallback"

# spec-only
rm -f "$TMP/a/IMPLEMENTATION.md"
out3=$(_plan_progress_json "$TMP/a" '{}')
echo "$out3" | jq -e '.primary_kind=="spec"' >/dev/null || fail "spec fallback"
pass "spec fallback"

# dash snapshot attaches field
mkdir -p "$TMP/b/.plinth/session"
cd "$TMP/b"
git init -q
git config user.email t@t
git config user.name t
echo x > f && git add f && git commit -qm i
git checkout -qb feat/p
printf 'spec_path = SPEC.md\n' > .plinth/config
cat > PLAN.md <<'P'
# P
## Acceptance criteria
- [x] a
- [ ] b
P
export PLINTH_DASH_ROOTS="$TMP/b"
snap=$("$PLINTH" dash --snapshot 2>/dev/null)
echo "$snap" | jq -e '.projects[0].lifecycle.plan_progress.primary=="PLAN.md"' >/dev/null \
  || fail "snapshot missing plan_progress"
pass "dash snapshot attaches plan_progress"

# cardHTML meter + chip (vm sandbox — same stubs as smoke-snapshot pure UI unit)
PLINTH_DASH_HTML="$ROOT/shared/dashboard/index.html" node <<'NODE'
const fs = require("fs");
const vm = require("vm");
const html = fs.readFileSync(process.env.PLINTH_DASH_HTML, "utf8");
const m = html.match(/<script>\s*([\s\S]*?)\s*<\/script>\s*<\/body>/i);
if (!m) { console.error("no script"); process.exit(1); }
const elsById = Object.create(null);
const el = (id) => {
  const o = {
    textContent: "", className: "", innerHTML: "",
    style: { display: "", cssText: "" },
    classList: { add() {}, remove() {}, contains() { return false; } },
    addEventListener() {}, removeEventListener() {},
    getAttribute() { return null; }, setAttribute() {},
    closest() { return null; },
    querySelector() { return null; },
  };
  if (id) elsById[id] = o;
  return o;
};
["grid", "live-dot", "live-label", "gen-ago", "discovery", "count",
 "quota-bar", "nh-modal", "nh-panel", "nh-title", "nh-sub", "nh-list", "nh-close",
 "filters", "toast"
].forEach((id) => { elsById[id] = el(id); });
const sandbox = {
  console, Date, Math, String, Number, JSON, Array, Object, parseInt, isNaN,
  setInterval: () => 0, clearInterval: () => {},
  fetch: async () => ({ ok: true, json: async () => ({ projects: [] }) }),
  document: {
    getElementById: (id) => (Object.prototype.hasOwnProperty.call(elsById, id) ? elsById[id] : null),
    createElement: () => el(),
    addEventListener() {},
    querySelector: () => ({ parentNode: { insertBefore() {} } }),
  },
};
sandbox.globalThis = sandbox;
sandbox.window = sandbox;
vm.createContext(sandbox);
vm.runInContext(m[1], sandbox);
const api = sandbox.__plinthDash;
if (!api || typeof api.cardHTML !== "function") {
  console.error("no __plinthDash.cardHTML");
  process.exit(1);
}
const h = api.cardHTML({
  name: "demo", path: "/tmp/demo", branch: "feat", head: "abc1234",
  feedless: true,
  lifecycle: {
    phase: "build", plan: true,
    plan_progress: {
      schema: "plinth.plan_progress/v1",
      primary: "PLAN.md", primary_kind: "plan",
      pct_complete: 33, done: 1, total: 3,
      current: { id: "x", title: "Second thing open" },
      outline: [{ title: "Acceptance criteria", status: "active", weight_pct: 100,
        children: [
          { title: "First", status: "done", weight_pct: 33 },
          { title: "Second thing open", status: "active", weight_pct: 34 },
          { title: "Third", status: "open", weight_pct: 33 },
        ] }],
      note: "test",
    },
  },
});
if (!h.includes("plan-meter")) { console.error("missing plan-meter"); process.exit(1); }
if (!h.includes("PLAN 33%")) { console.error("missing PLAN chip"); process.exit(1); }
if (!h.includes("data-plan=")) { console.error("missing data-plan"); process.exit(1); }
if (!h.includes("Second thing open")) { console.error("missing current"); process.exit(1); }
console.log("cardHTML ok");
NODE
pass "cardHTML plan meter + chip"

echo "canary-plan-progress: ALL PASS"
