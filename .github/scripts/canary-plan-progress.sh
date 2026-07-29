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

# coding milestones only — drop INV / matrix / human freeze / design noise
cat > "$TMP/a/PLAN.md" <<'P'
# My product
## Acceptance criteria
- [ ] Phase 2 mock exit with Playwright
- [ ] INV-7 — values immutable through learning
- [ ] BUILD-MATRIX.md maps every requirement R1–R60
- [ ] The owner explicitly agrees to feature freeze before plinth harden
- [x] Wire dashboard plan progress meter
## 4. Module-00 design decisions (recorded for review)
- **Event log**: table inside SQLCipher
## 4a. Module-00 build status (this pass — COMPLETE)
- cargo test passes
- INV-3 append-only note
## 3. Build order
- **M00 Foundation** — crates: platform
- zeroize key material scrubbing (INV-6)
P
outc2=$(_plan_progress_json "$TMP/a" '{}')
echo "$outc2" | jq -e '[.outline[].children[]?.title] | map(test("INV-7|BUILD-MATRIX|owner explicitly|Event log|cargo test|zeroize")) | any | not' >/dev/null \
  || fail "non-coding leaked: $(echo "$outc2"|jq '[.outline[].children[]?.title]')"
echo "$outc2" | jq -e '[.outline[].children[]?.title] | map(test("Phase 2|Wire dashboard|Module-00 build status|M00 Foundation")) | any' >/dev/null \
  || fail "coding milestones missing: $(echo "$outc2"|jq '[.outline[].children[]?.title]')"
pass "coding milestones only (no INV/matrix/freeze/design noise)"

# No PLAN.md → spec fallback only (no IMPLEMENTATION-PLAN aliases)
rm -f "$TMP/a/PLAN.md"
# Even if a legacy name exists, ignore it — clients must use PLAN.md
cat > "$TMP/a/IMPLEMENTATION-PLAN.md" <<'I'
# Legacy name — must NOT be used
## Phase 1
- [x] should be ignored
- [ ] also ignored
I
cat > "$TMP/a/SPEC.md" <<'S'
# Spec
## Requirements
The system shall foo when ready.
The system shall bar when done.
S
out2=$(_plan_progress_json "$TMP/a" '{}')
echo "$out2" | jq -e '.primary=="SPEC.md" and .primary_kind=="spec"' >/dev/null \
  || fail "without PLAN.md must use spec not IMPLEMENTATION-PLAN: $(echo "$out2"|jq .primary,.primary_kind)"
echo "$out2" | jq -e '.sources.plan == null' >/dev/null || fail "sources.plan must be null"
pass "no plan-filename aliases; SPEC fallback only"

# PLAN.md wins when both exist
cat > "$TMP/a/PLAN.md" <<'P'
# P
## Acceptance criteria
- [x] real plan item
- [ ] second
P
out3=$(_plan_progress_json "$TMP/a" '{}')
echo "$out3" | jq -e '.primary=="PLAN.md" and .primary_kind=="plan"' >/dev/null \
  || fail "PLAN.md must win: $(echo "$out3"|jq .primary)"
echo "$out3" | jq -e '.done==1 and .total==2' >/dev/null || fail "PLAN counts"
pass "PLAN.md is the only operational plan name"

# Slice N expands to #### subheadings (not one collapsed leaf)
cat > "$TMP/a/PLAN.md" <<'P'
# Product
## 6. Implementation sequence
### Slice 1 — First
#### 1. Scaffold
do stuff
#### 2. Identity
more
### Slice 2 — Second
#### 1. Later work
P
outs=$(_plan_progress_json "$TMP/a" '{}')
echo "$outs" | jq -e '
  ([.outline[] | select(.title|test("Slice 1"))][0].children | length) == 2
  and ([.outline[] | select(.title|test("Slice 1"))][0].children[0].title|test("Scaffold"))
  and (.total == 3)
' >/dev/null || fail "slice subheadings: $(echo "$outs"|jq .)"
pass "Slice N expands to #### subheadings"

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

# openPlan + delegated data-plan click + details collapse (classList guards)
PLINTH_DASH_HTML="$ROOT/shared/dashboard/index.html" node <<'NODE'
const fs = require("fs");
const vm = require("vm");
const html = fs.readFileSync(process.env.PLINTH_DASH_HTML, "utf8");
const m = html.match(/<script>\s*([\s\S]*?)\s*<\/script>\s*<\/body>/i);
if (!m) { console.error("no script"); process.exit(1); }
const elsById = Object.create(null);
const classSets = Object.create(null);
function makeEl(id) {
  const cs = new Set();
  const key = id || ("anon-" + Math.random());
  classSets[key] = cs;
  const o = {
    textContent: "", className: "", innerHTML: "",
    style: { display: "", cssText: "" },
    _listeners: [],
    classList: {
      add(c) { cs.add(c); },
      remove(c) { cs.delete(c); },
      contains(c) { return cs.has(c); },
      toggle(c, force) {
        if (force === true) { cs.add(c); return true; }
        if (force === false) { cs.delete(c); return false; }
        if (cs.has(c)) { cs.delete(c); return false; }
        cs.add(c); return true;
      },
    },
    addEventListener(type, fn) { o._listeners.push({ type, fn }); },
    removeEventListener() {},
    getAttribute() { return null; }, setAttribute() {},
    closest() { return null; },
    querySelector() { return null; },
  };
  if (id) elsById[id] = o;
  return o;
}
["grid", "live-dot", "live-label", "gen-ago", "discovery", "count",
 "quota-bar", "nh-modal", "nh-panel", "nh-title", "nh-sub", "nh-list", "nh-close",
 "filters", "toast"
].forEach((id) => { elsById[id] = makeEl(id); });
const listeners = [];
const sandbox = {
  console, Date, Math, String, Number, JSON, Array, Object, parseInt, isNaN,
  setInterval: () => 0, clearInterval: () => {},
  fetch: async () => ({ ok: true, json: async () => ({ projects: [] }) }),
  document: {
    getElementById: (id) => (Object.prototype.hasOwnProperty.call(elsById, id) ? elsById[id] : null),
    createElement: () => makeEl(),
    addEventListener(type, fn) { listeners.push({ type, fn }); },
    querySelector: () => ({ parentNode: { insertBefore() {} } }),
  },
};
sandbox.globalThis = sandbox;
sandbox.window = sandbox;
vm.createContext(sandbox);
vm.runInContext(m[1], sandbox);
const api = sandbox.__plinthDash;
if (!api || typeof api.openPlan !== "function") {
  console.error("no __plinthDash.openPlan");
  process.exit(1);
}
const proj = {
  name: "demo", path: "/tmp/demo", branch: "feat", head: "abc1234",
  feedless: true,
  lifecycle: {
    phase: "build", plan: true,
    plan_progress: {
      schema: "plinth.plan_progress/v1",
      primary: "PLAN.md", primary_kind: "plan",
      pct_complete: 50, done: 1, total: 2,
      current: { id: "x", title: "Second" },
      outline: [{ title: "AC", status: "active", weight_pct: 100,
        children: [
          { title: "First", status: "done", weight_pct: 50 },
          { title: "Second", status: "active", weight_pct: 50 },
        ] }],
      note: "test",
    },
  },
};
if (typeof api.seedProjects !== "function") {
  console.error("no seedProjects on __plinthDash:", Object.keys(api));
  process.exit(1);
}
api.seedProjects([proj]);
try {
  api.openPlan("/tmp/demo");
} catch (e) {
  console.error("openPlan throw", e);
  process.exit(1);
}
const modal = elsById["nh-modal"];
const panel = elsById["nh-panel"];
const list = elsById["nh-list"];
const title = elsById["nh-title"];
if (!modal.classList.contains("open")) {
  console.error("modal not open after openPlan");
  process.exit(1);
}
if (!panel.classList.contains("plan-wide")) {
  console.error("panel missing plan-wide");
  process.exit(1);
}
if (!list.classList.contains("plan-track")) {
  console.error("list missing plan-track");
  process.exit(1);
}
if (!String(title.textContent).includes("PLAN")) {
  console.error("title not PLAN:", title.textContent);
  process.exit(1);
}
if (!String(list.innerHTML).includes("plan-done-group") && !String(list.innerHTML).includes("completed")) {
  // may still have leaf rows
  if (!String(list.innerHTML).includes("First") && !String(list.innerHTML).includes("Second")) {
    console.error("no stage rows:", list.innerHTML.slice(0, 200));
    process.exit(1);
  }
}
// Delegated click on data-plan via grid listener (production attaches here)
const btn = makeEl();
btn.getAttribute = (k) => (k === "data-plan" ? "/tmp/demo" : null);
btn.closest = (sel) => (sel === "[data-plan]" ? btn : null);
const grid = elsById["grid"];
const gridClick = (grid._listeners || []).find((l) => l.type === "click")
  || listeners.find((l) => l.type === "click");
if (!gridClick) {
  console.error("no grid/document click listener for data-plan");
  process.exit(1);
}
// Reset modal then click
elsById["nh-modal"].classList.remove("open");
gridClick.fn({ target: btn, preventDefault() {} });
if (!elsById["nh-modal"].classList.contains("open")) {
  console.error("data-plan click did not open modal");
  process.exit(1);
}
// completed group: prefer details/summary; require active leaf class
const planHtml = String(list.innerHTML);
if (!/<details[^>]*class="[^"]*plan-done-group/.test(planHtml) && !planHtml.includes('class="plan-done-group"') && !planHtml.includes("plan-done-group")) {
  console.error("expected details.plan-done-group:", planHtml.slice(0, 300));
  process.exit(1);
}
// completed group should start closed (no open attr on plan-done-group details)
if (/<details[^>]*plan-done-group[^>]*\sopen[\s>]/.test(planHtml)) {
  console.error("plan-done-group should be closed by default:", planHtml.slice(0, 300));
  process.exit(1);
}
if (!/class="leaf active"/.test(planHtml) && !/leaf active/.test(planHtml)) {
  console.error("expected .leaf.active:", planHtml.slice(0, 300));
  process.exit(1);
}
// missing classList guard on panel AND list
const savedPanelCL = panel.classList;
const savedListCL = list.classList;
panel.classList = undefined;
list.classList = undefined;
try {
  api.openPlan("/tmp/demo");
} catch (e) {
  console.error("openPlan threw without classList", e);
  process.exit(1);
}
panel.classList = savedPanelCL;
list.classList = savedListCL;
console.log("openPlan+click+details ok");
NODE
pass "openPlan / data-plan click / plan-wide + stage rows"

# --- r3: Phase 0 / Foundation / sign-off coding work / conflict cursor / all-done ---
cat > "$TMP/a/PLAN.md" <<'P'
# Product
## Phase 0
- [ ] Scaffold repo layout
## Foundation
- [x] Core crate
## Acceptance criteria
- [ ] Build the sign-off workflow
- [ ] Implement owner sign-off API
- [ ] The owner explicitly agrees to feature freeze before plinth harden
P
outph=$(_plan_progress_json "$TMP/a" '{}')
echo "$outph" | jq -e '([.outline[].title] | index("Phase 0") != null)
  and ([.outline[].title] | index("Foundation") != null)
  and ([.outline[].title] | map(test("Acceptance")) | any)' >/dev/null \
  || fail "Phase/Foundation majors: $(echo "$outph"|jq '[.outline[].title]')"
echo "$outph" | jq -e '[.outline[].children[]?.title] | map(test("sign-off workflow")) | any' >/dev/null \
  || fail "sign-off workflow missing: $(echo "$outph"|jq '[.outline[].children[]?.title]')"
echo "$outph" | jq -e '[.outline[].children[]?.title] | map(test("sign-off API")) | any' >/dev/null \
  || fail "sign-off API missing: $(echo "$outph"|jq '[.outline[].children[]?.title]')"
echo "$outph" | jq -e '[.outline[].children[]?.title] | map(test("owner explicitly agrees")) | any | not' >/dev/null \
  || fail "human sign-off gate should drop: $(echo "$outph"|jq '[.outline[].children[]?.title]')"
cat > "$TMP/a/PLAN.md" <<'P'
# Product
## Release 2
- [ ] Ship batch API
## Acceptance criteria
- [ ] Keep going
P
outr=$(_plan_progress_json "$TMP/a" '{}')
echo "$outr" | jq -e '([.outline[].title] | index("Release 2") != null)' >/dev/null \
  || fail "Release 2 major: $(echo "$outr"|jq '[.outline[].title]')"
pass "Phase 0 / Foundation / Release 2 / coding sign-off vs human gate"

# conflicting id+title → no invented checkpoint cursor
cat > "$TMP/a/PLAN.md" <<'P'
# P
## Acceptance criteria
- [ ] Alpha first
- [ ] Beta second
- [ ] Gamma third
P
# id matches leaf1, title matches leaf3
rt='{"slice_id":"Alpha first","slice_title":"Gamma third","slice_index":2,"slice_total":3,"status":"implementing"}'
outcf=$(_plan_progress_json "$TMP/a" "$rt")
# should NOT use checkpoint mode from conflict; fall through to first_open
echo "$outcf" | jq -e '.progress_mode != "checkpoint" or (.current.via|test("first_open|checkbox")|not|not)' >/dev/null 2>&1 || true
# Stronger: current via must not be slice_id alone when title also present and conflicts
via=$(echo "$outcf" | jq -r '.current.via // empty')
case "$via" in
  slice_id|slice_title|slice_id+title|slice_index)
    fail "conflict must not invent checkpoint via=$via: $(echo "$outcf"|jq '{mode:.progress_mode,current}')"
    ;;
esac
pass "conflicting id/title refuse checkpoint cursor (via=$via)"

# all-done checkboxes → 100% without stale mid cursor when status=done
rt='{"status":"done","slice_index":1,"slice_total":2}'
cat > "$TMP/a/PLAN.md" <<'P'
# P
## Acceptance criteria
- [x] One
- [x] Two
P
outd=$(_plan_progress_json "$TMP/a" "$rt")
echo "$outd" | jq -e '.pct_complete==100 and .done==2' >/dev/null \
  || fail "status=done all checked: $(echo "$outd"|jq '{pct_complete,done,total,mode:.progress_mode}')"
pass "checkpoint status=done → 100%"

# Spec Requirements + Behavior shall + Features list (mixed ownership)
rm -f "$TMP/a/PLAN.md"
mkdir -p "$TMP/a/spec"
cat > "$TMP/a/spec/REQUIREMENTS.md" <<'S'
# Spec Dir
## Requirements
The system shall authenticate users via OAuth.
## Behavior
The system shall reject expired tokens.
## Features
- Export CSV reports
- Wire dashboard meter
S
# point config at directory
printf 'spec_path = spec\n' > "$TMP/a/.plinth/config"
outs=$(_plan_progress_json "$TMP/a" '{}')
echo "$outs" | jq -e '.primary_kind=="spec"' >/dev/null || fail "spec dir primary: $(echo "$outs"|jq .primary,.primary_kind)"
echo "$outs" | jq -e '
  ([.outline[] | select(.title|test("Requirements"; "i")) | .children[]?.title] | map(test("authenticate"; "i")) | any)
  and ([.outline[] | select(.title|test("Behavior"; "i")) | .children[]?.title] | map(test("reject expired"; "i")) | any)
  and (([.outline[] | select(.title|test("Features"; "i")) | .children[]?.title] | length) >= 2)
' >/dev/null \
  || fail "mixed shall+list ownership: $(echo "$outs"|jq '{primary,outline}')"
# title from H1 preserved
echo "$outs" | jq -e '.title|test("Spec Dir")' >/dev/null \
  || fail "document title: $(echo "$outs"|jq .title)"
pass "spec dir Requirements/Behavior shall + Features list; title preserved"

# OVERVIEW.md / API.md / requirements.md entry names
for ename in OVERVIEW.md API.md requirements.md; do
  mkdir -p "$TMP/ent$ename/.plinth" "$TMP/ent$ename/spec"
  printf 'spec_path = spec\n' > "$TMP/ent$ename/.plinth/config"
  cat > "$TMP/ent$ename/spec/$ename" <<S
# Entry $ename
## Requirements
The system shall resolve $ename entry files.
S
  oute=$(_plan_progress_json "$TMP/ent$ename" '{}')
  echo "$oute" | jq -e '.primary_kind=="spec" and (.total//0) >= 1' >/dev/null \
    || fail "entry $ename: $(echo "$oute"|jq '{primary,kind:.primary_kind,total}')"
done
pass "spec dir OVERVIEW/API/requirements.md entry names"

# restore file spec for later tests if any
printf 'spec_path = SPEC.md\n' > "$TMP/a/.plinth/config"
cat > "$TMP/a/SPEC.md" <<'S'
# Spec
## Requirements
The system shall foo.
S

# Writer seed: all PLAN leaves done → status done (product plinth checkpoint)
mkdir -p "$TMP/seed/.plinth"
cd "$TMP/seed"
git init -q
git config user.email t@t && git config user.name t
echo x > f && git add f && git commit -qm i
cat > PLAN.md <<'P'
# Seed
## Acceptance criteria
- [x] Done A
- [x] Done B
P
# Prior fence with stale mid-plan cursor
cat > CHECKPOINT.md <<'C'
# Checkpoint
## Next
1. old
## Routing
```json
{"schema":"plinth.checkpoint/v1","slice_index":1,"slice_total":2,"slice_title":"Done A","status":"implementing"}
```
C
# unset index env so seeder runs
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_SLICE_TOTAL PLINTH_CHECKPOINT_SLICE_TITLE PLINTH_CHECKPOINT_SLICE_ID PLINTH_CHECKPOINT_STATUS || true
"$PLINTH" checkpoint . >/dev/null 2>&1 || fail "checkpoint seed failed"
# Parse routing fence
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
echo "$cj" | jq -e '.status=="done" and .slice_index==2 and .slice_total==2' >/dev/null \
  || fail "all-done seed: $cj"
pass "checkpoint seeder: all PLAN leaves done → status=done index=total"

# No PLAN.md → do not seed from SPEC with plan_ref PLAN.md
rm -f PLAN.md
cat > SPEC.md <<'S'
# Spec
## Requirements
The system shall never seed as plan.
S
printf 'spec_path = SPEC.md\n' > .plinth/config
cat > CHECKPOINT.md <<'C'
# Checkpoint
## Next
1. x
C
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_STATUS || true
set +e
"$PLINTH" checkpoint . >/dev/null 2>&1
_rc=$?
set -e
[ "$_rc" -eq 0 ] || fail "checkpoint without PLAN must still succeed (rc=$_rc)"
cj2=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
si=$(echo "$cj2" | jq -r '.slice_index // empty')
[ -z "$si" ] || fail "must not seed from SPEC: $cj2"
pr=$(echo "$cj2" | jq -r '.plan_ref // empty')
[ -z "$pr" ] || fail "plan_ref without PLAN.md: $cj2"
st=$(echo "$cj2" | jq -r '.status // empty')
[ "$st" != "done" ] || fail "SPEC must not force status=done: $cj2"
pass "checkpoint seeder: no PLAN.md → no SPEC-fallback seed"

# index without total must NOT invent checkpoint cursor
cat > "$TMP/a/PLAN.md" <<'P'
# P
## Acceptance criteria
- [ ] A
- [ ] B
- [ ] C
P
printf 'spec_path = SPEC.md\n' > "$TMP/a/.plinth/config"
rt='{"slice_index":2,"status":"implementing"}'
outix=$(_plan_progress_json "$TMP/a" "$rt")
via=$(echo "$outix" | jq -r '.current.via // empty')
[ "$via" != "slice_index" ] || fail "index without total must not be checkpoint: $(echo "$outix"|jq '{mode:.progress_mode,current}')"
pass "index without total refuses slice_index cursor"

# first-open seed via real checkpoint (empty fence)
mkdir -p "$TMP/seed2/.plinth"
cd "$TMP/seed2"
git init -q
git config user.email t@t && git config user.name t
echo x > f && git add f && git commit -qm i
cat > PLAN.md <<'P'
# Seed
## Acceptance criteria
- [ ] First open leaf
- [ ] Second leaf
P
rm -f CHECKPOINT.md
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_SLICE_TOTAL \
  PLINTH_CHECKPOINT_SLICE_TITLE PLINTH_CHECKPOINT_SLICE_ID \
  PLINTH_CHECKPOINT_STATUS PLINTH_CHECKPOINT_PLAN_REF 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
echo "$cj" | jq -e '.slice_index==1 and .slice_total==2 and (.slice_title|test("First"))' >/dev/null \
  || fail "first-open seed: $cj"
pass "checkpoint seeder: first-open from PLAN"

# checkbox advance: mark first done, re-checkpoint without env → index 2
cat > PLAN.md <<'P'
# Seed
## Acceptance criteria
- [x] First open leaf
- [ ] Second leaf
P
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_STATUS 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
echo "$cj" | jq -e '.slice_index==2 and (.status != "done")' >/dev/null \
  || fail "checkbox advance seed: $cj"
pass "checkpoint seeder: checkbox advance to next open"

# reopen completed plan: status was done, new unchecked leaf appears
cat > PLAN.md <<'P'
# Seed
## Acceptance criteria
- [x] First open leaf
- [x] Second leaf
- [ ] Third new leaf
P
cat > CHECKPOINT.md <<'C'
# Checkpoint
## Next
1. x
## Routing
```json
{"schema":"plinth.checkpoint/v1","slice_index":2,"slice_total":2,"status":"done","plan_ref":"PLAN.md"}
```
C
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_STATUS 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
echo "$cj" | jq -e '.status=="implementing" and .slice_index==3 and .slice_total==3' >/dev/null \
  || fail "reopen after done: $cj"
outre=$(_plan_progress_json "$TMP/seed2" "$cj")
echo "$outre" | jq -e '.pct_complete != 100 and .pct_complete != null' >/dev/null \
  || fail "reopen dash pct: $(echo "$outre"|jq '{pct_complete,mode:.progress_mode,current}')"
pass "reopen completed PLAN when new leaf appears"

# all-done clears stale id/title
cat > PLAN.md <<'P'
# Seed
## Acceptance criteria
- [x] A
- [x] B
P
cat > CHECKPOINT.md <<'C'
# Checkpoint
## Next
1. x
## Routing
```json
{"schema":"plinth.checkpoint/v1","slice_index":1,"slice_total":2,"slice_id":"stale","slice_title":"stale title","status":"implementing","plan_ref":"PLAN.md"}
```
C
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_SLICE_ID \
  PLINTH_CHECKPOINT_SLICE_TITLE PLINTH_CHECKPOINT_STATUS 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
echo "$cj" | jq -e '.status=="done" and .slice_index==2 and (.slice_id==null or .slice_id=="") and (.slice_title==null or .slice_title=="")' >/dev/null \
  || fail "all-done clear labels: $cj"
pass "all-done clears stale slice_id/title"

# plan_ref must not stick after PLAN.md is deleted
mkdir -p "$TMP/seed3/.plinth"
cd "$TMP/seed3"
git init -q
git config user.email t@t && git config user.name t
echo x > f && git add f && git commit -qm i
cat > PLAN.md <<'P'
# Seed
## Acceptance criteria
- [ ] Open A
P
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_STATUS PLINTH_CHECKPOINT_PLAN_REF 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
echo "$cj" | jq -e '.plan_ref=="PLAN.md"' >/dev/null || fail "expected plan_ref with PLAN: $cj"
rm -f PLAN.md
cat > SPEC.md <<'S'
# Spec
## Requirements
The system shall remain after plan delete.
S
printf 'spec_path = SPEC.md\n' > .plinth/config
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_STATUS PLINTH_CHECKPOINT_PLAN_REF 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
pr=$(echo "$cj" | jq -r '.plan_ref // empty')
[ -z "$pr" ] || fail "stale plan_ref after PLAN delete: $cj"
# also drop inherited index/title/id/total/status=done when PLAN is gone
echo "$cj" | jq -e '
  (.plan_ref==null or .plan_ref=="")
  and (.slice_index==null or .slice_index=="")
  and (.slice_title==null or .slice_title=="")
  and (.slice_id==null or .slice_id=="")
  and (.slice_total==null or .slice_total=="")
  and (.status!="done")
' >/dev/null || fail "stale position after PLAN delete: $cj"
pass "plan_ref cleared when PLAN.md deleted"

# Matching CHECKPOINT Done prose must NOT advance seeder (checkbox-only seed)
mkdir -p "$TMP/seed5/.plinth"
cd "$TMP/seed5"
git init -q
git config user.email t@t && git config user.name t
echo x > f && git add f && git commit -qm i
cat > PLAN.md <<'P'
# Seed
## Acceptance criteria
- [ ] Wire dashboard plan progress meter for clients
- [ ] Second long enough title for matching rules here
P
cat > CHECKPOINT.md <<'C'
# Checkpoint
## Done
- Wire dashboard plan progress meter for clients was completed in a prior session
## Next
1. continue
## Routing
```json
{"schema":"plinth.checkpoint/v1","slice_index":1,"slice_total":2,"status":"implementing","plan_ref":"PLAN.md"}
```
C
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_STATUS 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
# Still on leaf 1 — Done prose must not mark first checkbox done for seeding
echo "$cj" | jq -e '.slice_index==1 and .status!="done"' >/dev/null \
  || fail "Done prose must not advance seed: $cj"
pass "seeder ignores CHECKPOINT Done prose (checkbox-only)"

# Matching HANDOFF Done prose must not advance seeder either
mkdir -p "$TMP/seed5b/.plinth"
cd "$TMP/seed5b"
git init -q
git config user.email t@t && git config user.name t
echo x > f && git add f && git commit -qm i
cat > PLAN.md <<'P'
# Seed
## Acceptance criteria
- [ ] Wire dashboard plan progress meter for clients
- [ ] Second long enough title for matching rules here
P
# No CHECKPOINT yet — first write creates it; seed from empty
rm -f CHECKPOINT.md HANDOFF.md
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_STATUS 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
# Inject matching Done into HANDOFF (legacy) and re-seed
cat > HANDOFF.md <<'H'
# Handoff
## Done
- Wire dashboard plan progress meter for clients was completed in a prior session
## Next
1. continue
H
# Force seeder path: keep CHECKPOINT without index env
# Rebuild CHECKPOINT body without routing index so seeder runs
python3 - <<'PY'
from pathlib import Path
import re
p = Path("CHECKPOINT.md")
raw = p.read_text()
# strip routing fence if present
raw = re.sub(r"\n## Routing\n.*", "\n", raw, flags=re.S)
p.write_text(raw + "\n## Routing\n\n```json\n{\"schema\":\"plinth.checkpoint/v1\",\"status\":\"implementing\"}\n```\n")
PY
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_STATUS 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
echo "$cj" | jq -e '.slice_index==1 and .status!="done"' >/dev/null \
  || fail "HANDOFF Done prose must not advance seed: $cj"
pass "seeder ignores HANDOFF Done prose (checkbox-only)"

# explicit STATUS=blocked must not be overwritten by open-plan seed
mkdir -p "$TMP/seed4/.plinth"
cd "$TMP/seed4"
git init -q
git config user.email t@t && git config user.name t
echo x > f && git add f && git commit -qm i
cat > PLAN.md <<'P'
# Seed
## Acceptance criteria
- [ ] Still open
- [ ] Also open
P
rm -f CHECKPOINT.md
export PLINTH_CHECKPOINT_STATUS=blocked
unset PLINTH_CHECKPOINT_SLICE_INDEX 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
echo "$cj" | jq -e '.status=="blocked" and .slice_index==1' >/dev/null \
  || fail "blocked status must stick with seed position: $cj"
unset PLINTH_CHECKPOINT_STATUS
pass "explicit STATUS=blocked preserved during auto-seed"

# all-checked PLAN + explicit blocked → still status=done (plan complete is factual)
mkdir -p "$TMP/seed6/.plinth"
cd "$TMP/seed6"
git init -q
git config user.email t@t && git config user.name t
echo x > f && git add f && git commit -qm i
cat > PLAN.md <<'P'
# Seed
## Acceptance criteria
- [x] A done
- [x] B done
P
rm -f CHECKPOINT.md
export PLINTH_CHECKPOINT_STATUS=blocked
unset PLINTH_CHECKPOINT_SLICE_INDEX 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
echo "$cj" | jq -e '.status=="done" and .slice_index==2 and .slice_total==2' >/dev/null \
  || fail "all-done must force status=done even if env blocked: $cj"
unset PLINTH_CHECKPOINT_STATUS
# dashboard 100%
out=$(cd "$TMP/seed6" && python3 - "$ROOT/bin/plinth" <<'PY'
import re, subprocess, sys
from pathlib import Path
# extract progress via plinth is heavy; use checkpoint status=done assertion above
print("ok")
PY
)
pass "all-done forces status=done over explicit blocked"

# orphan PLAN with explicit index env still clears stale id/title/done (only keeps env index)
mkdir -p "$TMP/seed7/.plinth"
cd "$TMP/seed7"
git init -q
git config user.email t@t && git config user.name t
echo x > f && git add f && git commit -qm i
cat > PLAN.md <<'P'
# Seed
## Acceptance criteria
- [x] Only
P
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_STATUS 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
rm -f PLAN.md
export PLINTH_CHECKPOINT_SLICE_INDEX=1
unset PLINTH_CHECKPOINT_SLICE_ID PLINTH_CHECKPOINT_SLICE_TITLE PLINTH_CHECKPOINT_STATUS 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
# index may stay from env; id/title/status=done must not remain as ghost plan cursor
echo "$cj" | jq -e '
  .slice_index==1
  and (.slice_id==null or .slice_id=="")
  and (.slice_title==null or .slice_title=="")
  and (.status!="done")
' >/dev/null || fail "orphan PLAN with index env still ghost: $cj"
unset PLINTH_CHECKPOINT_SLICE_INDEX
pass "orphan PLAN clears ghost id/done even with index env"

# Inherited fence status ready/blocked/reviewing preserved when seed advances
mkdir -p "$TMP/seed8/.plinth"
cd "$TMP/seed8"
git init -q
git config user.email t@t && git config user.name t
echo x > f && git add f && git commit -qm i
cat > PLAN.md <<'P'
# Seed
## Acceptance criteria
- [x] First leaf completed now
- [ ] Second still open
P
cat > CHECKPOINT.md <<'C'
# Checkpoint
## Next
1. x
## Routing
```json
{"schema":"plinth.checkpoint/v1","slice_index":1,"slice_total":2,"status":"blocked","plan_ref":"PLAN.md","slice_title":"First leaf completed now"}
```
C
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_STATUS 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
echo "$cj" | jq -e '.status=="blocked" and .slice_index==2' >/dev/null \
  || fail "inherited blocked must stick while advancing: $cj"
pass "inherited fence status blocked preserved on seed advance"

# numeric index cursor: matching total, no title/id
cat > "$TMP/a/PLAN.md" <<'P'
# P
## Acceptance criteria
- [ ] One
- [ ] Two
- [ ] Three
P
printf 'spec_path = SPEC.md\n' > "$TMP/a/.plinth/config"
rt='{"slice_index":2,"slice_total":3,"status":"implementing"}'
outn=$(_plan_progress_json "$TMP/a" "$rt")
echo "$outn" | jq -e '.progress_mode=="checkpoint" and .current.via=="slice_index" and (.current.title|test("Two"))' >/dev/null \
  || fail "numeric cursor: $(echo "$outn"|jq '{mode:.progress_mode,current}')"
# mismatched total refuses numeric
rt='{"slice_index":2,"slice_total":9,"status":"implementing"}'
outm=$(_plan_progress_json "$TMP/a" "$rt")
via=$(echo "$outm" | jq -r '.current.via // empty')
[ "$via" != "slice_index" ] || fail "mismatched total must not use slice_index: $(echo "$outm"|jq .current)"
pass "numeric index cursor + mismatched total refuse"

# Nested docs/PLAN.md must NOT be operational plan (root only)
mkdir -p "$TMP/nest/.plinth" "$TMP/nest/docs"
cd "$TMP/nest"
git init -q
git config user.email t@t && git config user.name t
echo x > f && git add f && git commit -qm i
cat > docs/PLAN.md <<'P'
# Nested
## Acceptance criteria
- [x] Nested A
- [x] Nested B
P
cat > SPEC.md <<'S'
# Spec
## Requirements
The system shall not seed from nested plan.
S
printf 'spec_path = SPEC.md\n' > .plinth/config
# no root PLAN.md
rm -f PLAN.md
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_STATUS 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
si=$(echo "$cj" | jq -r '.slice_index // empty')
[ -z "$si" ] || fail "nested docs/PLAN.md must not seed: $cj"
pr=$(echo "$cj" | jq -r '.plan_ref // empty')
[ -z "$pr" ] || fail "nested must not invent plan_ref: $cj"
# progress prefers SPEC not nested PLAN
outn=$(_plan_progress_json "$TMP/nest" '{}')
echo "$outn" | jq -e '.primary_kind=="spec" or .primary=="SPEC.md"' >/dev/null \
  || fail "nested PLAN must not be primary: $(echo "$outn"|jq '{primary,kind:.primary_kind}')"
pass "nested docs/PLAN.md is not operational plan"

# Legacy nested plan_ref in fence must not leave ghost cursor when root PLAN absent
mkdir -p "$TMP/ghost/.plinth" "$TMP/ghost/docs"
cd "$TMP/ghost"
git init -q
git config user.email t@t && git config user.name t
echo x > f && git add f && git commit -qm i
cat > docs/PLAN.md <<'P'
# Nested
## Acceptance criteria
- [x] Nested A
- [x] Nested B
P
cat > SPEC.md <<'S'
# Spec
## Requirements
The system shall not be forced to 100 percent.
S
printf 'spec_path = SPEC.md\n' > .plinth/config
rm -f PLAN.md
cat > CHECKPOINT.md <<'C'
# Checkpoint
## Next
1. x
## Routing
```json
{"schema":"plinth.checkpoint/v1","plan_ref":"docs/PLAN.md","slice_id":"ghost","slice_title":"Nested B","slice_index":2,"slice_total":2,"status":"done"}
```
C
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_STATUS PLINTH_CHECKPOINT_SLICE_ID PLINTH_CHECKPOINT_SLICE_TITLE PLINTH_CHECKPOINT_PLAN_REF 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
echo "$cj" | jq -e '(.plan_ref==null or .plan_ref=="") and (.slice_index==null or .slice_index=="") and (.status!="done")' >/dev/null \
  || fail "legacy nested plan_ref ghost cursor: $cj"
pass "legacy nested plan_ref ghost cursor cleared"

# spec_path=docs/PLAN.md basename collision must not become operational plan
mkdir -p "$TMP/col/.plinth" "$TMP/col/docs"
cd "$TMP/col"
git init -q
git config user.email t@t && git config user.name t
echo x > f && git add f && git commit -qm i
cat > docs/PLAN.md <<'P'
# Nested as "spec"
## Acceptance criteria
- [x] Should not be plan primary
- [x] Also checked
P
printf 'spec_path = docs/PLAN.md\n' > .plinth/config
rm -f PLAN.md
outc=$(_plan_progress_json "$TMP/col" '{}')
# primary may be nested file as SPEC fallback (primary_kind=spec) but never plan
echo "$outc" | jq -e '.primary_kind=="spec"' >/dev/null \
  || fail "docs/PLAN.md as spec_path must be kind=spec: $(echo "$outc"|jq '{primary,kind:.primary_kind}')"
unset PLINTH_CHECKPOINT_SLICE_INDEX 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
si=$(echo "$cj" | jq -r '.slice_index // empty')
[ -z "$si" ] || fail "docs/PLAN.md spec_path must not seed as plan: $cj"
pass "spec_path=docs/PLAN.md is spec fallback not operational plan"

# ready + reviewing preserved on first-open seed (missing index)
for st in ready reviewing; do
  mkdir -p "$TMP/st$st/.plinth"
  cd "$TMP/st$st"
  git init -q
  git config user.email t@t && git config user.name t
  echo x > f && git add f && git commit -qm i
  cat > PLAN.md <<'P'
# Seed
## Acceptance criteria
- [ ] Open A
- [ ] Open B
P
  cat > CHECKPOINT.md <<C
# Checkpoint
## Next
1. x
## Routing
\`\`\`json
{"schema":"plinth.checkpoint/v1","status":"$st","plan_ref":"PLAN.md"}
\`\`\`
C
  unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_STATUS 2>/dev/null || true
  "$PLINTH" checkpoint . >/dev/null
  cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
  echo "$cj" | jq -e --arg s "$st" '.status==$s and .slice_index==1' >/dev/null \
    || fail "preserve status=$st on first-open: $cj"
done
pass "inherited ready/reviewing preserved on first-open seed"

# ready/reviewing preserved during advance; blocked on first-open
for st in ready reviewing; do
  mkdir -p "$TMP/adv$st/.plinth"
  cd "$TMP/adv$st"
  git init -q
  git config user.email t@t && git config user.name t
  echo x > f && git add f && git commit -qm i
  cat > PLAN.md <<'P'
# Seed
## Acceptance criteria
- [x] First leaf completed now
- [ ] Second still open
P
  cat > CHECKPOINT.md <<C
# Checkpoint
## Next
1. x
## Routing
\`\`\`json
{"schema":"plinth.checkpoint/v1","slice_index":1,"slice_total":2,"status":"$st","plan_ref":"PLAN.md"}
\`\`\`
C
  unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_STATUS 2>/dev/null || true
  "$PLINTH" checkpoint . >/dev/null
  cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
  echo "$cj" | jq -e --arg s "$st" '.status==$s and .slice_index==2' >/dev/null \
    || fail "preserve status=$st on advance: $cj"
done
# blocked first-open (no index in fence)
mkdir -p "$TMP/blk0/.plinth"
cd "$TMP/blk0"
git init -q
git config user.email t@t && git config user.name t
echo x > f && git add f && git commit -qm i
cat > PLAN.md <<'P'
# Seed
## Acceptance criteria
- [ ] Open A
P
cat > CHECKPOINT.md <<'C'
# Checkpoint
## Next
1. x
## Routing
```json
{"schema":"plinth.checkpoint/v1","status":"blocked","plan_ref":"PLAN.md"}
```
C
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_STATUS 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
echo "$cj" | jq -e '.status=="blocked" and .slice_index==1' >/dev/null \
  || fail "blocked first-open: $cj"
pass "ready/reviewing advance + blocked first-open preserved"

# Huge PLAN: early checked + late open beyond 120k must NOT seed all-done
mkdir -p "$TMP/huge/.plinth"
cd "$TMP/huge"
git init -q
git config user.email t@t && git config user.name t
echo x > f && git add f && git commit -qm i
{
  echo "# Huge"
  echo "## Acceptance criteria"
  echo "- [x] Early checked leaf only in first window"
  # pad >120k of non-leaf noise
  python3 -c 'print("\n".join(["note padding line %d" % i for i in range(8000)]))'
  echo "- [ ] Late open leaf after truncation window"
} > PLAN.md
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_STATUS 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
echo "$cj" | jq -e '.status != "done"' >/dev/null \
  || fail "truncated must not all-done: $cj"
# Dashboard path may truncate; seed path must see the late leaf (full file).
outh=$(_plan_progress_json "$TMP/huge" '{}')
outh2=$(PLINTH_PLAN_SEED=1 _plan_progress_json "$TMP/huge" '{}')
echo "$outh2" | jq -e '.total==2 and .done==1 and .truncated!=true' >/dev/null \
  || fail "seed must see late open leaf without trunc: $(echo "$outh2"|jq '{truncated,done,total}')"
# dash may truncate but seed checkpoint already asserted status != done
pass "truncation refuse all-done seed (full-file seed parse)"

# No PLAN.md + prior status=done (no plan_ref) must not leave 100% SPEC
mkdir -p "$TMP/nopref/.plinth"
cd "$TMP/nopref"
git init -q
git config user.email t@t && git config user.name t
echo x > f && git add f && git commit -qm i
rm -f PLAN.md
cat > SPEC.md <<'S'
# Spec
## Requirements
The system shall not complete from ghost done.
S
printf 'spec_path = SPEC.md\n' > .plinth/config
cat > CHECKPOINT.md <<'C'
# Checkpoint
## Next
1. x
## Routing
```json
{"schema":"plinth.checkpoint/v1","slice_index":2,"slice_total":2,"status":"done"}
```
C
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_STATUS 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
echo "$cj" | jq -e '(.status!="done") and (.slice_index==null or .slice_index=="")' >/dev/null \
  || fail "no plan_ref done ghost: $cj"
pass "no plan_ref done ghost cleared without root PLAN"

# truncated + prior done fence reopens
mkdir -p "$TMP/hugedone/.plinth"
cd "$TMP/hugedone"
git init -q
git config user.email t@t && git config user.name t
echo x > f && git add f && git commit -qm i
{
  echo "# Huge"
  echo "## Acceptance criteria"
  echo "- [x] Early"
  python3 -c 'print("\n".join(["pad %d" % i for i in range(8000)]))'
  echo "- [ ] Late open"
} > PLAN.md
cat > CHECKPOINT.md <<'C'
# Checkpoint
## Next
1. x
## Routing
```json
{"schema":"plinth.checkpoint/v1","slice_index":1,"slice_total":1,"status":"done","plan_ref":"PLAN.md"}
```
C
unset PLINTH_CHECKPOINT_SLICE_INDEX PLINTH_CHECKPOINT_STATUS 2>/dev/null || true
"$PLINTH" checkpoint . >/dev/null
cj=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
echo "$cj" | jq -e '.status != "done"' >/dev/null \
  || fail "truncated + prior done must reopen: $cj"
pass "truncated reopens prior done fence"

echo "canary-plan-progress: ALL PASS"
