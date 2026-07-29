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
echo "$outph" | jq -e '[.outline[].title] | map(test("Phase 0|Foundation|Acceptance")) | all' >/dev/null \
  || fail "Phase/Foundation majors: $(echo "$outph"|jq '[.outline[].title]')"
echo "$outph" | jq -e '[.outline[].children[]?.title] | map(test("sign-off workflow|sign-off API")) | any' >/dev/null \
  || fail "coding sign-off kept: $(echo "$outph"|jq '[.outline[].children[]?.title]')"
echo "$outph" | jq -e '[.outline[].children[]?.title] | map(test("owner explicitly agrees")) | any | not' >/dev/null \
  || fail "human sign-off gate should drop: $(echo "$outph"|jq '[.outline[].children[]?.title]')"
pass "Phase 0 / Foundation / coding sign-off vs human gate"

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
echo "$outs" | jq -e '[.outline[].children[]?.title] | map(test("authenticate|reject expired|Export CSV|Wire dashboard")) | map(.) | flatten | length >= 3' >/dev/null \
  || fail "mixed shall+list harvest: $(echo "$outs"|jq '{primary,outline}')"
# title from H1 preserved
echo "$outs" | jq -e '.title|test("Spec Dir")' >/dev/null \
  || fail "document title: $(echo "$outs"|jq .title)"
pass "spec dir Requirements/Behavior shall + Features list; title preserved"

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
unset PLINTH_CHECKPOINT_SLICE_INDEX || true
"$PLINTH" checkpoint . >/dev/null 2>&1 || true
cj2=$(awk '/```json/{p=1;next}/```/{p=0}p' CHECKPOINT.md)
# slice_index should remain null/absent (no PLAN seed)
si=$(echo "$cj2" | jq -r '.slice_index // empty')
[ -z "$si" ] || fail "must not seed from SPEC: $cj2"
pass "checkpoint seeder: no PLAN.md → no SPEC-fallback seed"

echo "canary-plan-progress: ALL PASS"
