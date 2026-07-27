#!/usr/bin/env bash
# Extracted Plinth canary: fail-closed UPSTREAM package probes (#11/#13/#15/#17/#49).
# Invoked from plinth-canary.yml with GITHUB_WORKSPACE set to the repo root.
set -euo pipefail
cd "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE required}"

# ── plinth#11/#13/#15 failure-injection (mutation-sensitive) ───────────
# Absence is covered above; these prove INFRA failures fail closed and that
# the tooling floor cannot be skipped by a working-tree classifier rewrite.
REAL_GIT="$(command -v git)"
# #11 risk-classify: ls-tree infra failure → Tier 2 (not WT fallback / not silent absence)
RC_SHIM="$(mktemp -d)"
cat > "$RC_SHIM/git" <<GSH
#!/usr/bin/env bash
if [ "\$1" = ls-tree ] && [[ "\$*" == *.plinth/config* ]]; then
  echo "fatal: Not a valid object name (injected)" >&2; exit 128
fi
exec "$REAL_GIT" "\$@"
GSH
chmod +x "$RC_SHIM/git"
RC1="$(mktemp -d)"; ( cd "$RC1"; git init -qb main . >/dev/null; mkdir -p .plinth
  printf 'spec_path = SPEC.md\n' > .plinth/config; echo hi > README.md; git add -A; git commit -qm b >/dev/null
  git checkout -qb feat >/dev/null 2>&1; echo code > app.py; git add -A; git commit -qm w >/dev/null
  out="$(PATH="$RC_SHIM:$PATH" bash "$GITHUB_WORKSPACE/shared/.plinth/risk-classify.sh" main 2>/dev/null)"
  [ "$(printf '%s' "$out" | jq -r .tier)" = "2" ] || { echo "::error::#11 risk-classify did not fail closed to Tier 2 when ls-tree config failed (out=$out)"; exit 1; }
  printf '%s' "$out" | grep -qi 'ls-tree' || { echo "::error::#11 risk-classify Tier-2 reason did not name ls-tree failure"; exit 1; } )
# #11 risk-classify: ls-tree present but git show fails → Tier 2
RC_SHOW="$(mktemp -d)"
cat > "$RC_SHOW/git" <<GSH
#!/usr/bin/env bash
while [ "\$1" = -c ]; do shift 2; done
if [ "\$1" = show ] && [[ "\$2" == *:.plinth/config ]]; then
  echo "fatal: unable to read tree (injected)" >&2; exit 128
fi
exec "$REAL_GIT" "\$@"
GSH
chmod +x "$RC_SHOW/git"
RC2="$(mktemp -d)"; ( cd "$RC2"; git init -qb main . >/dev/null; mkdir -p .plinth
  printf 'spec_path = SPEC.md\n' > .plinth/config; echo hi > README.md; git add -A; git commit -qm b >/dev/null
  git checkout -qb feat >/dev/null 2>&1; echo code > app.py; git add -A; git commit -qm w >/dev/null
  out="$(PATH="$RC_SHOW:$PATH" bash "$GITHUB_WORKSPACE/shared/.plinth/risk-classify.sh" main 2>/dev/null)"
  [ "$(printf '%s' "$out" | jq -r .tier)" = "2" ] || { echo "::error::#11 risk-classify did not fail closed when git show base config failed (out=$out)"; exit 1; } )
# #11 risk-classify: git diff --raw failure → Tier 2
RC_RAW="$(mktemp -d)"
cat > "$RC_RAW/git" <<GSH
#!/usr/bin/env bash
while [ "\$1" = -c ]; do shift 2; done
if [ "\$1" = diff ] && [ "\$2" = --raw ]; then
  echo "fatal: diff --raw failed (injected)" >&2; exit 128
fi
exec "$REAL_GIT" "\$@"
GSH
chmod +x "$RC_RAW/git"
RC3="$(mktemp -d)"; ( cd "$RC3"; git init -qb main . >/dev/null; mkdir -p .plinth
  printf 'spec_path = SPEC.md\n' > .plinth/config; echo hi > README.md; git add -A; git commit -qm b >/dev/null
  git checkout -qb feat >/dev/null 2>&1; echo code > app.py; git add -A; git commit -qm w >/dev/null
  out="$(PATH="$RC_RAW:$PATH" bash "$GITHUB_WORKSPACE/shared/.plinth/risk-classify.sh" main 2>/dev/null)"
  [ "$(printf '%s' "$out" | jq -r .tier)" = "2" ] || { echo "::error::#11 risk-classify did not fail closed when git diff --raw failed (out=$out)"; exit 1; }
  printf '%s' "$out" | grep -qi 'diff --raw' || { echo "::error::#11 risk-classify reason did not name diff --raw failure"; exit 1; } )
# #11/#15 risk-classify: per-test `git diff baseref...HEAD -- path` failure → Tier 2
# (must not under-classify a new test as Tier 1 when skip-marker scan cannot run)
RC_PT="$(mktemp -d)"
cat > "$RC_PT/git" <<GSH
#!/usr/bin/env bash
while [ "\$1" = -c ]; do shift 2; done
# Fail path-scoped diffs only — leave --raw intact so the loop runs.
if [ "\$1" = diff ] && [ "\$2" != --raw ]; then
  for a in "\$@"; do [ "\$a" = -- ] && { echo "fatal: per-path diff failed (injected)" >&2; exit 128; }; done
fi
exec "$REAL_GIT" "\$@"
GSH
chmod +x "$RC_PT/git"
RC4="$(mktemp -d)"; ( cd "$RC4"; git init -qb main . >/dev/null; mkdir -p .plinth tests
  printf 'spec_path = SPEC.md\n' > .plinth/config; echo hi > README.md; git add -A; git commit -qm b >/dev/null
  git checkout -qb feat >/dev/null 2>&1; printf 'def test_x():\n  assert 1\n' > tests/test_x.py; git add -A; git commit -qm w >/dev/null
  out="$(PATH="$RC_PT:$PATH" bash "$GITHUB_WORKSPACE/shared/.plinth/risk-classify.sh" main 2>/dev/null)"
  [ "$(printf '%s' "$out" | jq -r .tier)" = "2" ] || { echo "::error::#11 risk-classify did not fail closed when per-test git diff failed (out=$out)"; exit 1; }
  printf '%s' "$out" | grep -qi 'cannot diff new test' || { echo "::error::#11 risk-classify reason did not name per-test diff failure (out=$out)"; exit 1; } )
# #15 review.sh: base-config ls-tree infra → die_infra (extracted probe block)
RV_CFG="$(mktemp -d)"
cat > "$RV_CFG/git" <<GSH
#!/usr/bin/env bash
while [ "\$1" = -c ]; do shift 2; done
if [ "\$1" = ls-tree ] && [[ "\$*" == *.plinth/config* ]]; then
  echo "fatal: bad object (injected)" >&2; exit 128
fi
exec "$REAL_GIT" "\$@"
GSH
chmod +x "$RV_CFG/git"
BCFG_BLK="$(mktemp)"
awk '/^basecfg=""/ {p=1} p{print} /^bcfg\(\)/ {if(p)exit}' \
  "$GITHUB_WORKSPACE/shared/.plinth/review.sh" > "$BCFG_BLK"
grep -q 'ls-tree' "$BCFG_BLK" || { echo "::error::could not extract basecfg probe from review.sh"; exit 1; }
RV1="$(mktemp -d)"; ( cd "$RV1"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  mkdir -p .plinth; printf 'spec_path = SPEC.md\n' > .plinth/config
  echo a > app.py; git add -A; git commit -qm b >/dev/null
  base_tip="$(git rev-parse HEAD)"
  set +e
  err="$(base_tip="$base_tip" PATH="$RV_CFG:$PATH" bash -c '
    set -euo pipefail
    die_infra() { echo "die_infra: $*" >&2; exit 9; }
    source '"$BCFG_BLK"'
  ' 2>&1)"; erc=$?
  set -e
  [ "$erc" -ne 0 ] || { echo "::error::#15 review.sh basecfg probe did not die_infra on ls-tree failure (rc=0)"; exit 1; }
  printf '%s' "$err" | grep -qiE 'ls-tree|unverified knobs|die_infra' || { echo "::error::#15 basecfg probe message missing (err=$err)"; exit 1; } )
# #15 review.sh: tooling-name diff failure → floor to Tier 2 (message), not silent Tier-0
RV_DIFF="$(mktemp -d)"
cat > "$RV_DIFF/git" <<GSH
#!/usr/bin/env bash
while [ "\$1" = -c ]; do shift 2; done
# Fail ONLY the tooling-floor name-only probe (base_tip..HEAD form used by review.sh)
if [ "\$1" = diff ] && [ "\$2" = --name-only ]; then
  echo "fatal: name-only failed (injected)" >&2; exit 128
fi
exec "$REAL_GIT" "\$@"
GSH
chmod +x "$RV_DIFF/git"
# Floor block without the trailing status-echo (that line pollutes stdout JSON).
FLB="$(mktemp)"
awk '/^RISK=2; RISK_JSON=/ {p=1} p && /^echo "Plinth review: risk Tier/ {exit} p{print}' \
  "$GITHUB_WORKSPACE/shared/.plinth/review.sh" > "$FLB"
grep -q 'tool_names' "$FLB" && grep -q 'HARNESS_RE' "$FLB" || { echo "::error::could not extract tooling-floor block from review.sh"; exit 1; }
RV2="$(mktemp -d)"; ( cd "$RV2"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  mkdir -p .plinth; echo a > app.py; git add -A; git commit -qm b >/dev/null
  git checkout -qb feat >/dev/null 2>&1; echo b >> app.py; git add -A; git commit -qm w >/dev/null
  base_tip="$(git rev-parse main)"
  HARNESS_RE='(^|/)\.plinth/|(^|/)\.claude/|(^|/)\.github/'
  PATH="$RV_DIFF:$PATH" bash -c '
    set -euo pipefail
    base_tip="$1"; HARNESS_RE="$2"; die_infra() { echo "die_infra: $*" >&2; exit 9; }
    source "$3"
    printf "%s\n" "$RISK_JSON"
  ' _ "$base_tip" "$HARNESS_RE" "$FLB" > "$RV2/out.json" 2>"$RV2/err"
  [ "$(jq -r .tier "$RV2/out.json")" = "2" ] || { echo "::error::#15 tooling-floor did not fail closed when git diff --name-only failed (out=$(cat "$RV2/out.json") err=$(cat "$RV2/err"))"; exit 1; }
  grep -qi 'name-only' "$RV2/out.json" || { echo "::error::#15 tooling-floor reason did not name the name-only failure"; exit 1; } )
# #15 large-input: tooling floor must still match when name list is huge
# (grep -q early-exit under pipefail used to SIGPIPE-skip the floor).
T_BIG="$(mktemp -d)"; ( cd "$T_BIG"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  mkdir -p .plinth; echo a > app.py; git add -A; git commit -qm b >/dev/null
  git checkout -qb feat >/dev/null 2>&1
  i=0; while [ $i -lt 8000 ]; do printf 'f%05d.py\n' "$i"; i=$((i+1)); done > names.txt
  { cat names.txt; echo '.plinth/review.sh'; } > tool_names.txt
  HARNESS_RE="$(awk -F"'" '/^HARNESS_RE=/ {print $2; exit}' "$GITHUB_WORKSPACE/shared/.plinth/review.sh")"
  tool_names="$(cat tool_names.txt)"
  set -o pipefail
  _hrc=0; printf '%s\n' "$tool_names" | grep -E "$HARNESS_RE" >/dev/null || _hrc=$?
  [ "$_hrc" = 0 ] || { echo "::error::#15 large tool_names list missed harness path under full-read floor match (rc=$_hrc)"; exit 1; }
  # Product must not use grep -q or here-string for the floor (both fail-open classes):
  ! grep -nE 'tool_names.*grep -Eq|grep -Eq.*HARNESS_RE.*<<<|<<<.*HARNESS' "$GITHUB_WORKSPACE/shared/.plinth/review.sh" \
    || { echo "::error::#15 review.sh tooling floor still uses grep -q or here-string (fail-open)"; exit 1; }
)
# #15 large-input PRODUCT probes (extract/source real blocks — not reimplemented greps).
# 1) tooling floor with huge name list: PATH git shim emits 8k files + harness path
BIG_GIT="$(mktemp -d)"
cat > "$BIG_GIT/git" <<GSH
#!/usr/bin/env bash
while [ "\$1" = -c ]; do shift 2; done
if [ "\$1" = diff ] && [ "\$2" = --name-only ]; then
  i=0; while [ \$i -lt 8000 ]; do printf 'f%05d.py\n' "\$i"; i=\$((i+1)); done
  echo '.plinth/review.sh'; exit 0
fi
exec "$REAL_GIT" "\$@"
GSH
chmod +x "$BIG_GIT/git"
FLB_BIG="$(mktemp)"
awk '/^RISK=2; RISK_JSON=/ {p=1} p && /^echo "Plinth review: risk Tier/ {exit} p{print}' \
  "$GITHUB_WORKSPACE/shared/.plinth/review.sh" > "$FLB_BIG"
T_BIG2="$(mktemp -d)"; ( cd "$T_BIG2"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  mkdir -p .plinth; echo a > app.py; git add -A; git commit -qm b >/dev/null
  git checkout -qb feat >/dev/null 2>&1; echo b >> app.py; git add -A; git commit -qm w >/dev/null
  base_tip="$(git rev-parse main)"
  HARNESS_RE="$(awk -F"'" '/^HARNESS_RE=/ {print $2; exit}' "$GITHUB_WORKSPACE/shared/.plinth/review.sh")"
  out="$(base_tip="$base_tip" HARNESS_RE="$HARNESS_RE" PATH="$BIG_GIT:$PATH" bash -c '
    set -euo pipefail
    die_infra() { echo "die_infra: $*" >&2; exit 9; }
    source '"$FLB_BIG"'
    printf "%s\n" "$RISK_JSON"
  ')"
  [ "$(printf '%s' "$out" | jq -r .tier)" = "2" ] || { echo "::error::#15 product floor missed harness path in 8k name list (out=$out)"; exit 1; }
  printf '%s' "$out" | grep -qiE 'floored|tooling|version-pinned' || { echo "::error::#15 product floor reason missing for large list"; exit 1; }
)
# 2) round_cap: extract the real _rc_hit block by line range from review.sh
RCAP_BLK="$(mktemp)"
# Capture from _rc_hit=0 through the fi that closes the ROUND_CAP if
awk '/^_rc_hit=0/ {p=1} p{print; if(/^fi$/ && seen){exit} if(/ROUND_CAP=/) seen=1}' \
  "$GITHUB_WORKSPACE/shared/.plinth/review.sh" > "$RCAP_BLK"
grep -q '_rc_hit' "$RCAP_BLK" && grep -q 'ROUND_CAP=' "$RCAP_BLK" \
  || { echo "::error::could not extract round_cap block (got $(wc -l <"$RCAP_BLK") lines)"; exit 1; }
# File-backed large basecfg (env would hit ARG_MAX/E2BIG on Linux ~128KB+)
BCFG_FILE="$(mktemp)"
python3 -c 'import sys; sys.stdout.write("round_cap = 7\n"+"x=1\n"*40000)' > "$BCFG_FILE"
out="$(bash -c '
  set -euo pipefail
  die_infra() { echo "die_infra: $*" >&2; exit 9; }
  basecfg="$(cat "$1")"
  bcfg() { printf "%s" "$basecfg" | sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" | head -1; }
  source "$2"
  printf "cap=%s\n" "$ROUND_CAP"
' _ "$BCFG_FILE" "$RCAP_BLK")"
printf '%s' "$out" | grep -q 'cap=7' || { echo "::error::#15 product round_cap miss on large basecfg (out=$out)"; exit 1; }
rm -f "$BCFG_FILE"
# 3) risk-classify product: new pre-skipped test must be Tier 2 (SKIPADD path)
T_SK="$(mktemp -d)"; ( cd "$T_SK"; git init -qb main . >/dev/null
  mkdir -p tests .plinth; printf 'spec_path = SPEC.md\n' > .plinth/config
  echo hi > README.md; git add -A; git commit -qm b >/dev/null
  git checkout -qb feat >/dev/null 2>&1
  # Large new test file with skip marker near the top
  { echo 'import pytest'; echo '@pytest.mark.skip'; python3 -c 'print("x=1\n"*20000)'; } > tests/test_big.py
  git add -A; git commit -qm w >/dev/null
  out="$(bash "$GITHUB_WORKSPACE/shared/.plinth/risk-classify.sh" main 2>/dev/null)"
  [ "$(printf '%s' "$out" | jq -r .tier)" = "2" ] || { echo "::error::#15 product risk-classify missed pre-skipped large new test (out=$out)"; exit 1; }
  printf '%s' "$out" | grep -qiE 'skip|pre-skipped|weakening' || { echo "::error::#15 product SKIPADD reason missing (out=$out)"; exit 1; }
)
# 4) guard product: long merge clause with metachar must parse_error (block)
GD_MC="$(mktemp -d)"; mkdir -p "$GD_MC/.plinth/session/review/feat-x"
( cd "$GD_MC"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  echo a>f; git add -A; git commit -qm b >/dev/null; git checkout -qb feat/x >/dev/null 2>&1
  echo c>f; git add -A; git commit -qm w >/dev/null )
GH4mc="$(git -C "$GD_MC" rev-parse HEAD)"
printf '{"verdict":"APPROVED","sha":"%s"}' "$GH4mc" > "$GD_MC/.plinth/session/review/feat-x/verdict.json"
git -C "$GD_MC" remote add origin "https://github.com/example/plinth.git"
# Body with $ metachar + long padding — must block (parse fail-closed)
longpad="$(python3 -c 'print("x"*20000)')"
mc_cmd="gh pr merge 42 --squash -R github.com/example/plinth --match-head-commit $GH4mc --body=\$BODY$longpad"
mc_rc="$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(jq -Rn --arg c "$mc_cmd" '$c')" | CLAUDE_PROJECT_DIR="$GD_MC" bash "$GITHUB_WORKSPACE/shared/.claude/hooks/guard.sh" >/dev/null 2>&1; echo $?)"
[ "$mc_rc" = 2 ] || { echo "::error::#15 product guard did not fail-closed on long metachar merge clause (rc=$mc_rc)"; exit 1; }
# 5) product source hygiene: no quiet greps remain on fail-closed paths
if grep -nE 'grep -Eiq|grep -Eq' "$GITHUB_WORKSPACE/shared/.claude/hooks/guard.sh" >/dev/null; then
  echo "::error::#15 guard.sh still has grep -Eq (quiet)"; exit 1
fi
if grep -nE 'grep -Eq' "$GITHUB_WORKSPACE/shared/.plinth/risk-classify.sh" | grep -q SKIPADD; then
  echo "::error::#15 risk-classify still quiet-greps SKIPADD"; exit 1
fi
# Behavioral: directory/file-equivalent and root-form spec_path → Tier 2
for _spv in 'blueprints' 'blueprints/' './blueprints' './blueprints/' 'blueprints/.' 'blueprints//' './blueprints//' 'blueprints/./sub' 'blueprints/././sub' '././blueprints'; do
  T_DSP="$(mktemp -d)"; ( cd "$T_DSP"; git init -qb main . >/dev/null
    mkdir -p .plinth blueprints/sub
    printf 'spec_path = %s\n' "$_spv" > .plinth/config
    echo hi > README.md; git add -A; git commit -qm b >/dev/null
    git checkout -qb feat >/dev/null 2>&1
    case "$_spv" in *sub*) echo ch > blueprints/sub/chapter.md ;; *) echo ch > blueprints/chapter.md ;; esac
    git add -A; git commit -qm w >/dev/null
    out="$(bash "$GITHUB_WORKSPACE/shared/.plinth/risk-classify.sh" main 2>/dev/null)"
    [ "$(printf '%s' "$out" | jq -r .tier)" = "2" ] \
      || { echo "::error::#15 risk-classify missed directory spec_path='$_spv' (out=$out)"; exit 1; }
  )
done
# Repo-root directory forms: every path is under the canonical tree
for _spv in '.' './'; do
  T_ROOT="$(mktemp -d)"; ( cd "$T_ROOT"; git init -qb main . >/dev/null
    mkdir -p .plinth
    printf 'spec_path = %s\n' "$_spv" > .plinth/config
    echo hi > README.md; git add -A; git commit -qm b >/dev/null
    git checkout -qb feat >/dev/null 2>&1
    echo code > app.py; git add -A; git commit -qm w >/dev/null
    out="$(bash "$GITHUB_WORKSPACE/shared/.plinth/risk-classify.sh" main 2>/dev/null)"
    [ "$(printf '%s' "$out" | jq -r .tier)" = "2" ] \
      || { echo "::error::#15 risk-classify root spec_path='$_spv' not Tier 2 (out=$out)"; exit 1; }
  )
done
# Behavioral: rename-away of file SPEC.md still surfaces as delete with --no-renames
T_RN="$(mktemp -d)"; ( cd "$T_RN"; git init -qb main . >/dev/null
  mkdir -p .plinth; printf 'spec_path = SPEC.md\n' > .plinth/config
  echo REQ > SPEC.md; git add -A; git commit -qm b >/dev/null
  git checkout -qb feat >/dev/null 2>&1
  git mv SPEC.md OTHER.md; git commit -qm ren >/dev/null
  # Product loop uses --no-renames so SPEC.md appears deleted
  names="$(git -c core.quotePath=false diff --name-only --no-renames main...HEAD)"
  printf '%s\n' "$names" | grep -qxF 'SPEC.md' \
    || { echo "::error::#15 rename-away fixture: --no-renames did not list SPEC.md (got $names)"; exit 1; }
)
# Behavioral: non-ASCII custom spec_path is Tier 2 (core.quotePath=false)
T_NA="$(mktemp -d)"; ( cd "$T_NA"; git init -qb main . >/dev/null
  mkdir -p .plinth specs
  printf 'spec_path = specs/é\n' > .plinth/config
  printf 'req\n' > "specs/é"; echo hi > README.md; git add -A; git commit -qm b >/dev/null
  git checkout -qb feat >/dev/null 2>&1
  echo ch >> "specs/é"; git add -A; git commit -qm w >/dev/null
  out="$(bash "$GITHUB_WORKSPACE/shared/.plinth/risk-classify.sh" main 2>/dev/null)"
  [ "$(printf '%s' "$out" | jq -r .tier)" = "2" ] \
    || { echo "::error::#15 risk-classify non-ASCII spec_path not Tier 2 (out=$out)"; exit 1; }
  printf '%s' "$out" | grep -q 'specs/' \
    || { echo "::error::#15 risk-classify non-ASCII reason missing path (out=$out)"; exit 1; }
)
# #13: non-tooling PR rewrite of risk-classify must NOT classify itself —
# base classifier (honest Tier 1 for app.py) wins over an evil WT that claims Tier 0.
RV3="$(mktemp -d)"; BORG3="$(mktemp -d)"; git init -q --bare "$BORG3"
( cd "$RV3"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  mkdir -p .plinth
  cp "$GITHUB_WORKSPACE/shared/.plinth/risk-classify.sh" .plinth/risk-classify.sh
  cp "$GITHUB_WORKSPACE/shared/.plinth/review.sh" .plinth/review.sh
  printf 'spec_path = SPEC.md\n' > .plinth/config
  echo REQ > SPEC.md; echo a > app.py; git add -A; git commit -qm b >/dev/null
  git remote add origin "$BORG3"; git push -q origin main
  git checkout -qb feat >/dev/null 2>&1
  # Evil working-tree classifier always claims Tier 0 (would under-review if used)
  printf '%s\n' '#!/usr/bin/env bash' 'printf "{\"tier\":0,\"files\":0,\"reasons\":[\"EVIL_WT\"]}\n"' > .plinth/risk-classify.sh
  chmod +x .plinth/risk-classify.sh
  echo b >> app.py; git add -A; git commit -qm 'rewrite classifier + app' >/dev/null
  # Extract and run the floor+classifier block with real HARNESS_RE from review.sh
  HARNESS_RE="$(awk -F"'" '/^HARNESS_RE=/ {print $2; exit}' .plinth/review.sh)"
  [ -n "$HARNESS_RE" ] || HARNESS_RE='(^|/)\.plinth/'
  base_tip="$(git rev-parse origin/main)"; sha="$(git rev-parse HEAD)"
  # risk-classify.sh is under .plinth/ — tooling floor should catch it BEFORE classifier
  tool_names="$(git diff --name-only "${base_tip}..HEAD")"
  printf '%s\n' "$tool_names" | grep -Eq "$HARNESS_RE" || { echo "::error::test setup: classifier rewrite not seen as tooling path"; exit 1; }
  # Prove the product message: floor reason, and that EVIL_WT never appears
  FLB2="$(mktemp)"
  awk '/^RISK=2; RISK_JSON=/ {p=1} p && /^echo "Plinth review: risk Tier/ {exit} p{print}' \
    .plinth/review.sh > "$FLB2"
  out="$(base_tip="$base_tip" HARNESS_RE="$HARNESS_RE" bash -c '
    set -euo pipefail
    die_infra() { echo "die_infra: $*" >&2; exit 9; }
    source '"$FLB2"'
    printf "%s\n" "$RISK_JSON"
  ')"
  [ "$(printf '%s' "$out" | jq -r .tier)" = "2" ] || { echo "::error::#13 tooling floor did not force Tier 2 for classifier rewrite (out=$out)"; exit 1; }
  printf '%s' "$out" | grep -qiE 'floored|tooling|version-pinned' || { echo "::error::#13 floor reason missing (out=$out)"; exit 1; }
  printf '%s' "$out" | grep -q 'EVIL_WT' && { echo "::error::#13 evil working-tree classifier ran despite tooling floor"; exit 1; } || true )
# #13 sibling: NON-tooling diff uses base classifier blob, not WT rewrite alone.
# Base has honest classifier; WT has evil Tier-0; app.py-only commit (no .plinth touch).
RV4="$(mktemp -d)"; BORG4="$(mktemp -d)"; git init -q --bare "$BORG4"
( cd "$RV4"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  mkdir -p .plinth
  cp "$GITHUB_WORKSPACE/shared/.plinth/risk-classify.sh" .plinth/risk-classify.sh
  cp "$GITHUB_WORKSPACE/shared/.plinth/review.sh" .plinth/review.sh
  printf 'spec_path = SPEC.md\n' > .plinth/config
  echo REQ > SPEC.md; echo a > app.py; git add -A; git commit -qm b >/dev/null
  git remote add origin "$BORG4"; git push -q origin main
  git checkout -qb feat >/dev/null 2>&1
  # Dirty WT classifier only (not committed — review.sh extracts base blob via git show)
  printf '%s\n' '#!/usr/bin/env bash' 'printf "{\"tier\":0,\"files\":0,\"reasons\":[\"EVIL_WT_UNCOmmitted\"]}\n"' > .plinth/risk-classify.sh
  chmod +x .plinth/risk-classify.sh
  echo b >> app.py; git add app.py; git commit -qm 'app only' >/dev/null
  HARNESS_RE="$(awk -F"'" '/^HARNESS_RE=/ {print $2; exit}' .plinth/review.sh)"
  [ -n "$HARNESS_RE" ] || HARNESS_RE='(^|/)\.plinth/'
  base_tip="$(git rev-parse origin/main)"
  FLB3="$(mktemp)"
  awk '/^RISK=2; RISK_JSON=/ {p=1} p && /^echo "Plinth review: risk Tier/ {exit} p{print}' \
    .plinth/review.sh > "$FLB3"
  out="$(base_tip="$base_tip" HARNESS_RE="$HARNESS_RE" bash -c '
    set -euo pipefail
    die_infra() { echo "die_infra: $*" >&2; exit 9; }
    source '"$FLB3"'
    printf "%s\n" "$RISK_JSON"
  ')"
  # Honest base classifier on app.py edit → Tier 1, NOT evil Tier 0
  [ "$(printf '%s' "$out" | jq -r .tier)" = "1" ] || { echo "::error::#13 non-tooling PR did not use base classifier (want Tier 1 for app.py, got out=$out)"; exit 1; }
  printf '%s' "$out" | grep -q 'EVIL_WT' && { echo "::error::#13 uncommitted evil WT classifier was executed for non-tooling diff"; exit 1; } || true )
# #15 review.sh: base classifier ls-tree infra (non-tooling path) → die_infra
RV_CLF="$(mktemp -d)"
cat > "$RV_CLF/git" <<GSH
#!/usr/bin/env bash
while [ "\$1" = -c ]; do shift 2; done
if [ "\$1" = ls-tree ] && [[ "\$*" == *risk-classify.sh* ]]; then
  echo "fatal: bad object classifier (injected)" >&2; exit 128
fi
exec "$REAL_GIT" "\$@"
GSH
chmod +x "$RV_CLF/git"
RV5="$(mktemp -d)"; ( cd "$RV5"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  mkdir -p .plinth
  cp "$GITHUB_WORKSPACE/shared/.plinth/risk-classify.sh" .plinth/risk-classify.sh
  cp "$GITHUB_WORKSPACE/shared/.plinth/review.sh" .plinth/review.sh
  printf 'spec_path = SPEC.md\n' > .plinth/config
  echo REQ > SPEC.md; echo a > app.py; git add -A; git commit -qm b >/dev/null
  git checkout -qb feat >/dev/null 2>&1; echo b >> app.py; git add -A; git commit -qm w >/dev/null
  HARNESS_RE="$(awk -F"'" '/^HARNESS_RE=/ {print $2; exit}' .plinth/review.sh)"
  base_tip="$(git rev-parse main)"
  FLB4="$(mktemp)"
  awk '/^RISK=2; RISK_JSON=/ {p=1} p && /^echo "Plinth review: risk Tier/ {exit} p{print}' \
    .plinth/review.sh > "$FLB4"
  set +e
  err="$(base_tip="$base_tip" HARNESS_RE="$HARNESS_RE" PATH="$RV_CLF:$PATH" bash -c '
    set -euo pipefail
    die_infra() { echo "die_infra: $*" >&2; exit 9; }
    source '"$FLB4"'
    printf "%s\n" "$RISK_JSON"
  ' 2>&1)"; erc=$?
  set -e
  [ "$erc" -ne 0 ] || { echo "::error::#15 base-classifier ls-tree infra failure did not die_infra (out=$err)"; exit 1; }
  printf '%s' "$err" | grep -qiE 'risk-classify|ls-tree|die_infra' || { echo "::error::#15 classifier probe failure message missing (err=$err)"; exit 1; } )
# #15 review.sh: reviewer-contract ls-tree infra → die_infra
RC_MAT="$(mktemp)"
awk '/^RC_FILE=/ {p=1} p{print} /^\[ -s "\$RC_FILE" \]/ {if(p){print; exit}}' \
  "$GITHUB_WORKSPACE/shared/.plinth/review.sh" > "$RC_MAT"
grep -q 'ls-tree' "$RC_MAT" || { echo "::error::could not extract reviewer-contract materialization from review.sh"; exit 1; }
RV_RC="$(mktemp -d)"
cat > "$RV_RC/git" <<GSH
#!/usr/bin/env bash
while [ "\$1" = -c ]; do shift 2; done
if [ "\$1" = ls-tree ] && [[ "\$*" == *reviewer.md* ]]; then
  echo "fatal: bad object reviewer (injected)" >&2; exit 128
fi
exec "$REAL_GIT" "\$@"
GSH
chmod +x "$RV_RC/git"
RV6="$(mktemp -d)"; ( cd "$RV6"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  mkdir -p .plinth; echo a > f; git add -A; git commit -qm b >/dev/null
  base_tip="$(git rev-parse HEAD)"; SDIR="$(mktemp -d)"; RC_FILE="$SDIR/reviewer-contract.md"
  set +e
  err="$(base_tip="$base_tip" SDIR="$SDIR" RC_FILE="$RC_FILE" PATH="$RV_RC:$PATH" bash -c '
    set -euo pipefail
    die_infra() { echo "die_infra: $*" >&2; exit 9; }
    source '"$RC_MAT"'
  ' 2>&1)"; erc=$?
  set -e
  [ "$erc" -ne 0 ] || { echo "::error::#15 reviewer.md ls-tree infra failure did not die_infra"; exit 1; }
  printf '%s' "$err" | grep -qiE 'reviewer|ls-tree|die_infra' || { echo "::error::#15 reviewer contract probe message missing (err=$err)"; exit 1; } )
# #15 post-probe git show failures (ls-tree present, show fails → die_infra / fail closed)
for _site in config:'.plinth/config' clf:'.plinth/risk-classify.sh' rev:'.plinth/reviewer.md'; do
  _lab="${_site%%:*}"; _path="${_site#*:}"
  SHIM="$(mktemp -d)"
  cat > "$SHIM/git" <<GSH
#!/usr/bin/env bash
while [ "\$1" = -c ]; do shift 2; done
if [ "\$1" = show ] && [[ "\$2" == *:$_path ]]; then
  echo "fatal: show $_path failed (injected)" >&2; exit 128
fi
exec "$REAL_GIT" "\$@"
GSH
  chmod +x "$SHIM/git"
  case "$_lab" in
    config)
      BLK="$(mktemp)"; awk '/^basecfg=""/ {p=1} p{print} /^bcfg\(\)/ {if(p)exit}' \
        "$GITHUB_WORKSPACE/shared/.plinth/review.sh" > "$BLK"
      T="$(mktemp -d)"; ( cd "$T"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
        mkdir -p .plinth; printf 'spec_path = SPEC.md\n' > .plinth/config; echo a > f; git add -A; git commit -qm b >/dev/null
        base_tip="$(git rev-parse HEAD)"
        set +e; err="$(base_tip="$base_tip" PATH="$SHIM:$PATH" bash -c 'set -euo pipefail; die_infra(){ echo "die_infra: $*" >&2; exit 9; }; source '"$BLK"'' 2>&1)"; erc=$?; set -e
        [ "$erc" -ne 0 ] || { echo "::error::#15 git show base config failure did not die_infra"; exit 1; }
        printf '%s' "$err" | grep -qiE 'config|die_infra|cannot read' || { echo "::error::#15 base config show fail message missing (err=$err)"; exit 1; } ) ;;
    clf)
      FLB="$(mktemp)"; awk '/^RISK=2; RISK_JSON=/ {p=1} p && /^echo "Plinth review: risk Tier/ {exit} p{print}' \
        "$GITHUB_WORKSPACE/shared/.plinth/review.sh" > "$FLB"
      T="$(mktemp -d)"; ( cd "$T"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
        mkdir -p .plinth; cp "$GITHUB_WORKSPACE/shared/.plinth/risk-classify.sh" .plinth/risk-classify.sh
        cp "$GITHUB_WORKSPACE/shared/.plinth/review.sh" .plinth/review.sh
        printf 'spec_path = SPEC.md\n' > .plinth/config; echo REQ > SPEC.md; echo a > app.py; git add -A; git commit -qm b >/dev/null
        git checkout -qb feat >/dev/null 2>&1; echo b >> app.py; git add -A; git commit -qm w >/dev/null
        HARNESS_RE="$(awk -F"'" '/^HARNESS_RE=/ {print $2; exit}' .plinth/review.sh)"
        base_tip="$(git rev-parse main)"
        set +e; err="$(base_tip="$base_tip" HARNESS_RE="$HARNESS_RE" PATH="$SHIM:$PATH" bash -c 'set -euo pipefail; die_infra(){ echo "die_infra: $*" >&2; exit 9; }; source '"$FLB"'; printf "%s\n" "$RISK_JSON"' 2>&1)"; erc=$?; set -e
        [ "$erc" -ne 0 ] || { echo "::error::#15 git show base risk-classify.sh failure did not die_infra (out=$err)"; exit 1; }
        printf '%s' "$err" | grep -qiE 'risk-classify|die_infra|cannot extract' || { echo "::error::#15 classifier show fail message missing (err=$err)"; exit 1; } ) ;;
    rev)
      BLK="$(mktemp)"; awk '/^RC_FILE=/ {p=1} p{print} /^\[ -s "\$RC_FILE" \]/ {if(p){print; exit}}' \
        "$GITHUB_WORKSPACE/shared/.plinth/review.sh" > "$BLK"
      T="$(mktemp -d)"; ( cd "$T"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
        mkdir -p .plinth; cp "$GITHUB_WORKSPACE/shared/.plinth/reviewer.md" .plinth/reviewer.md 2>/dev/null || printf '# Plinth — Reviewer\n' > .plinth/reviewer.md
        echo a > f; git add -A; git commit -qm b >/dev/null
        base_tip="$(git rev-parse HEAD)"; SDIR="$(mktemp -d)"; RC_FILE="$SDIR/reviewer-contract.md"
        set +e; err="$(base_tip="$base_tip" SDIR="$SDIR" RC_FILE="$RC_FILE" PATH="$SHIM:$PATH" bash -c 'set -euo pipefail; die_infra(){ echo "die_infra: $*" >&2; exit 9; }; source '"$BLK"'' 2>&1)"; erc=$?; set -e
        [ "$erc" -ne 0 ] || { echo "::error::#15 git show base reviewer.md failure did not die_infra"; exit 1; }
        printf '%s' "$err" | grep -qiE 'reviewer|die_infra|cannot read' || { echo "::error::#15 reviewer.md show fail message missing (err=$err)"; exit 1; } ) ;;
  esac
done
# #15 AGENTS.md legacy path: reviewer absent (empty ls-tree), AGENTS show fails → die_infra
SHIM_AG="$(mktemp -d)"
cat > "$SHIM_AG/git" <<GSH
#!/usr/bin/env bash
while [ "\$1" = -c ]; do shift 2; done
if [ "\$1" = show ] && [[ "\$2" == *:AGENTS.md ]]; then
  echo "fatal: show AGENTS.md failed (injected)" >&2; exit 128
fi
# Pretend reviewer.md is absent so the legacy AGENTS.md branch is taken
if [ "\$1" = ls-tree ] && [[ "\$*" == *reviewer.md* ]]; then
  exit 0
fi
exec "$REAL_GIT" "\$@"
GSH
chmod +x "$SHIM_AG/git"
BLK_AG="$(mktemp)"; awk '/^RC_FILE=/ {p=1} p{print} /^\[ -s "\$RC_FILE" \]/ {if(p){print; exit}}' \
  "$GITHUB_WORKSPACE/shared/.plinth/review.sh" > "$BLK_AG"
T_AG="$(mktemp -d)"; ( cd "$T_AG"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  # Base has legacy AGENTS.md reviewer contract, no .plinth/reviewer.md
  printf '# Plinth — Reviewer\npolicy\n' > AGENTS.md; echo a > f; git add -A; git commit -qm b >/dev/null
  base_tip="$(git rev-parse HEAD)"; SDIR="$(mktemp -d)"; RC_FILE="$SDIR/reviewer-contract.md"
  set +e; err="$(base_tip="$base_tip" SDIR="$SDIR" RC_FILE="$RC_FILE" PATH="$SHIM_AG:$PATH" bash -c 'set -euo pipefail; die_infra(){ echo "die_infra: $*" >&2; exit 9; }; source '"$BLK_AG"'' 2>&1)"; erc=$?; set -e
  [ "$erc" -ne 0 ] || { echo "::error::#15 git show base AGENTS.md failure did not die_infra"; exit 1; }
  printf '%s' "$err" | grep -qiE 'AGENTS|die_infra|cannot read' || { echo "::error::#15 AGENTS.md show fail message missing (err=$err)"; exit 1; } )
# #15 AGENTS.md ls-tree infra (reviewer absent) → die_infra — sibling of show-failure above
SHIM_AGLS="$(mktemp -d)"
cat > "$SHIM_AGLS/git" <<GSH
#!/usr/bin/env bash
while [ "\$1" = -c ]; do shift 2; done
if [ "\$1" = ls-tree ] && [[ "\$*" == *reviewer.md* ]]; then
  exit 0
fi
if [ "\$1" = ls-tree ] && [[ "\$*" == *AGENTS.md* ]]; then
  echo "fatal: ls-tree AGENTS.md failed (injected)" >&2; exit 128
fi
exec "$REAL_GIT" "\$@"
GSH
chmod +x "$SHIM_AGLS/git"
T_AGLS="$(mktemp -d)"; ( cd "$T_AGLS"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  printf '# Plinth — Reviewer\npolicy\n' > AGENTS.md; echo a > f; git add -A; git commit -qm b >/dev/null
  base_tip="$(git rev-parse HEAD)"; SDIR="$(mktemp -d)"; RC_FILE="$SDIR/reviewer-contract.md"
  set +e; err="$(base_tip="$base_tip" SDIR="$SDIR" RC_FILE="$RC_FILE" PATH="$SHIM_AGLS:$PATH" bash -c 'set -euo pipefail; die_infra(){ echo "die_infra: $*" >&2; exit 9; }; source '"$BLK_AG"'' 2>&1)"; erc=$?; set -e
  [ "$erc" -ne 0 ] || { echo "::error::#15 git ls-tree base AGENTS.md failure did not die_infra"; exit 1; }
  printf '%s' "$err" | grep -qiE 'AGENTS|ls-tree|die_infra' || { echo "::error::#15 AGENTS.md ls-tree fail message missing (err=$err)"; exit 1; } )
# #15 AGENTS-project.md ls-tree infra inside inline_contract → return 1 → die_infra
SHIM_AP="$(mktemp -d)"
cat > "$SHIM_AP/git" <<GSH
#!/usr/bin/env bash
while [ "\$1" = -c ]; do shift 2; done
if [ "\$1" = ls-tree ] && [[ "\$*" == *AGENTS-project.md* ]]; then
  echo "fatal: bad object AGENTS-project (injected)" >&2; exit 128
fi
exec "$REAL_GIT" "\$@"
GSH
chmod +x "$SHIM_AP/git"
# Extract inline_contract function (from def through the closing brace before next top-level)
IC_FN="$(mktemp)"
awk '/^inline_contract\(\)/ {p=1} p{print} p && /^}$/ {exit}' \
  "$GITHUB_WORKSPACE/shared/.plinth/review.sh" > "$IC_FN"
grep -q 'AGENTS-project' "$IC_FN" || { echo "::error::could not extract inline_contract from review.sh"; exit 1; }
T_AP="$(mktemp -d)"; ( cd "$T_AP"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  mkdir -p .plinth; printf '# Plinth — Reviewer\n' > .plinth/reviewer.md
  echo a > f; git add -A; git commit -qm b >/dev/null
  base_tip="$(git rev-parse HEAD)"; RC_FILE=".plinth/reviewer.md"; RC_SRC=".plinth/reviewer.md (base)"
  set +e
  err="$(base_tip="$base_tip" baseref="main" RC_FILE="$RC_FILE" RC_SRC="$RC_SRC" PATH="$SHIM_AP:$PATH" bash -c '
    set -euo pipefail
    source '"$IC_FN"'
    inline_contract >/dev/null
  ' 2>&1)"; erc=$?
  set -e
  [ "$erc" -ne 0 ] || { echo "::error::#15 inline_contract did not fail on AGENTS-project ls-tree infra error"; exit 1; }
  printf '%s' "$err" | grep -qiE 'AGENTS-project|ls-tree|inline_contract' || { echo "::error::#15 AGENTS-project probe message missing (err=$err)"; exit 1; } )
# #15 inline_contract: cat "$RC_FILE" failure → return 1
T_CATRC="$(mktemp -d)"; ( cd "$T_CATRC"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  mkdir -p .plinth; printf '# Plinth — Reviewer\n' > .plinth/reviewer.md
  echo a > f; git add -A; git commit -qm b >/dev/null
  base_tip="$(git rev-parse HEAD)"; RC_FILE=".plinth/reviewer.md"; RC_SRC="base"
  chmod a-r "$RC_FILE"
  set +e
  err="$(base_tip="$base_tip" baseref="main" RC_FILE="$RC_FILE" RC_SRC="$RC_SRC" bash -c '
    set -euo pipefail
    source '"$IC_FN"'
    inline_contract >/dev/null
  ' 2>&1)"; erc=$?
  set -e
  chmod u+r "$RC_FILE" 2>/dev/null || true
  [ "$erc" -ne 0 ] || { echo "::error::#15 inline_contract did not fail when cat RC_FILE failed (unreadable)"; exit 1; }
  printf '%s' "$err" | grep -qiE 'cannot read|inline_contract|Permission|RC_FILE|reviewer' || { echo "::error::#15 cat RC_FILE fail message missing (err=$err)"; exit 1; } )
# #15 inline_contract: ls-tree present for AGENTS-project, git show fails → return 1
SHIM_APSHOW="$(mktemp -d)"
cat > "$SHIM_APSHOW/git" <<GSH
#!/usr/bin/env bash
while [ "\$1" = -c ]; do shift 2; done
if [ "\$1" = show ] && [[ "\$2" == *AGENTS-project.md ]]; then
  echo "fatal: show AGENTS-project failed (injected)" >&2; exit 128
fi
exec "$REAL_GIT" "\$@"
GSH
chmod +x "$SHIM_APSHOW/git"
T_APS="$(mktemp -d)"; ( cd "$T_APS"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  mkdir -p .plinth; printf '# Plinth — Reviewer\n' > .plinth/reviewer.md
  printf 'rule\n' > .plinth/AGENTS-project.md
  echo a > f; git add -A; git commit -qm b >/dev/null
  base_tip="$(git rev-parse HEAD)"; RC_FILE=".plinth/reviewer.md"; RC_SRC="base"
  set +e
  err="$(base_tip="$base_tip" baseref="main" RC_FILE="$RC_FILE" RC_SRC="$RC_SRC" PATH="$SHIM_APSHOW:$PATH" bash -c '
    set -euo pipefail
    source '"$IC_FN"'
    inline_contract >/dev/null
  ' 2>&1)"; erc=$?
  set -e
  [ "$erc" -ne 0 ] || { echo "::error::#15 inline_contract did not fail when git show AGENTS-project.md failed"; exit 1; }
  printf '%s' "$err" | grep -qiE 'AGENTS-project|cannot read|inline_contract' || { echo "::error::#15 AGENTS-project show fail message missing (err=$err)"; exit 1; } )
# #15 inline_contract: base AGENTS-project ABSENT (empty ls-tree), working-tree cat fails → return 1
SHIM_APABS="$(mktemp -d)"
cat > "$SHIM_APABS/git" <<GSH
#!/usr/bin/env bash
while [ "\$1" = -c ]; do shift 2; done
if [ "\$1" = ls-tree ] && [[ "\$*" == *AGENTS-project.md* ]]; then
  exit 0
fi
exec "$REAL_GIT" "\$@"
GSH
chmod +x "$SHIM_APABS/git"
T_APWT="$(mktemp -d)"; ( cd "$T_APWT"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  mkdir -p .plinth; printf '# Plinth — Reviewer\n' > .plinth/reviewer.md
  echo a > f; git add -A; git commit -qm b >/dev/null
  printf 'wt-rule\n' > .plinth/AGENTS-project.md; chmod a-r .plinth/AGENTS-project.md
  base_tip="$(git rev-parse HEAD)"; RC_FILE=".plinth/reviewer.md"; RC_SRC="base"
  set +e
  err="$(base_tip="$base_tip" baseref="main" RC_FILE="$RC_FILE" RC_SRC="$RC_SRC" PATH="$SHIM_APABS:$PATH" bash -c '
    set -euo pipefail
    source '"$IC_FN"'
    inline_contract >/dev/null
  ' 2>&1)"; erc=$?
  set -e
  chmod u+r .plinth/AGENTS-project.md 2>/dev/null || true
  [ "$erc" -ne 0 ] || { echo "::error::#15 inline_contract did not fail when WT AGENTS-project.md cat failed"; exit 1; }
  printf '%s' "$err" | grep -qiE 'AGENTS-project|cannot read|inline_contract|Permission' || { echo "::error::#15 WT AGENTS-project cat fail message missing (err=$err)"; exit 1; } )
# #15 outer CONTRACT_TEXT gate: inline_contract failure propagates to die_infra
# Extract the materialize-assignment lines from review.sh
CT_BLK="$(mktemp)"
awk '/^if ! CONTRACT_TEXT=/ {p=1} p{print} p && /produced empty policy/ {print; exit}' \
  "$GITHUB_WORKSPACE/shared/.plinth/review.sh" > "$CT_BLK"
grep -q 'inline_contract' "$CT_BLK" || { echo "::error::could not extract CONTRACT_TEXT gate from review.sh"; exit 1; }
T_CT="$(mktemp -d)"; ( cd "$T_CT"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  mkdir -p .plinth; printf '# Plinth — Reviewer\n' > .plinth/reviewer.md
  echo a > f; git add -A; git commit -qm b >/dev/null
  base_tip="$(git rev-parse HEAD)"; RC_FILE=".plinth/reviewer.md"; RC_SRC="base"
  # Force inline_contract to fail via AGENTS-project ls-tree inject
  set +e
  err="$(base_tip="$base_tip" baseref="main" RC_FILE="$RC_FILE" RC_SRC="$RC_SRC" PATH="$SHIM_AP:$PATH" bash -c '
    set -euo pipefail
    die_infra() { echo "die_infra: $*" >&2; exit 9; }
    source '"$IC_FN"'
    source '"$CT_BLK"'
  ' 2>&1)"; erc=$?
  set -e
  [ "$erc" -ne 0 ] || { echo "::error::#15 CONTRACT_TEXT gate did not die_infra when inline_contract failed"; exit 1; }
  printf '%s' "$err" | grep -qiE 'inline_contract|die_infra|AGENTS-project' || { echo "::error::#15 CONTRACT_TEXT propagation message missing (err=$err)"; exit 1; } )
# #15 locale-independence: product sources must not decide absence via English
# stderr phrases (the pre-fix defect under localized Git). Presence is ls-tree.
! grep -nE "does not exist" "$GITHUB_WORKSPACE/shared/.plinth/review.sh" \
  "$GITHUB_WORKSPACE/shared/.plinth/risk-classify.sh" \
  || { echo "::error::#15 product still matches English 'does not exist' for absence — locale-dependent"; exit 1; }
grep -q 'ls-tree' "$GITHUB_WORKSPACE/shared/.plinth/review.sh" \
  && grep -q 'ls-tree' "$GITHUB_WORKSPACE/shared/.plinth/risk-classify.sh" \
  || { echo "::error::#15 product missing ls-tree presence probes"; exit 1; }
# First-adoption absence still works (no base config → Tier 1 for app.py-only;
# do NOT commit .plinth/config on the PR — that is tooling Tier 2).
T_LOC="$(mktemp -d)"; ( cd "$T_LOC"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  echo hi > README.md; git add -A; git commit -qm b >/dev/null
  git checkout -qb feat >/dev/null 2>&1; echo code > app.py; git add app.py; git commit -qm w >/dev/null
  out="$(bash "$GITHUB_WORKSPACE/shared/.plinth/risk-classify.sh" main 2>/dev/null || true)"
  [ "$(printf '%s' "$out" | jq -r .tier 2>/dev/null)" = "1" ] || { echo "::error::#15 risk-classify first-adoption absence failed (out=$out)"; exit 1; }
  BCFG_L="$(mktemp)"; awk '/^basecfg=""/ {p=1} p{print} /^bcfg\(\)/ {if(p)exit}' \
    "$GITHUB_WORKSPACE/shared/.plinth/review.sh" > "$BCFG_L"
  base_tip="$(git rev-parse main)"
  set +e
  err="$(base_tip="$base_tip" bash -c '
    set -euo pipefail
    die_infra() { echo "die_infra: $*" >&2; exit 9; }
    source '"$BCFG_L"'
    printf "has=%s\n" "$base_has_config"
  ' 2>&1)"; erc=$?
  set -e
  [ "$erc" = 0 ] && printf '%s' "$err" | grep -q 'has=0' || { echo "::error::#15 review.sh basecfg treated absence as infra (erc=$erc err=$err)"; exit 1; } )
# Deterministic localized-Git shim: even if Git printed French "n'existe pas",
# product no longer reads stderr for absence — ls-tree empty still means absence.
SHIM_FR="$(mktemp -d)"
cat > "$SHIM_FR/git" <<GSH
#!/usr/bin/env bash
while [ "\$1" = -c ]; do shift 2; done
# Pass through real git; only rewrite cat-file -e stderr to French (legacy trap).
if [ "\$1" = cat-file ] && [ "\$2" = -e ]; then
  out="\$("$REAL_GIT" "\$@" 2>&1)"; rc=\$?
  if [ "\$rc" -ne 0 ]; then
    echo "fatal: le chemin n'existe pas dans 'HEAD' (injected fr)" >&2
    exit "\$rc"
  fi
  printf '%s' "\$out"; exit 0
fi
exec "$REAL_GIT" "\$@"
GSH
chmod +x "$SHIM_FR/git"
T_FR="$(mktemp -d)"; ( cd "$T_FR"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  echo hi > README.md; git add -A; git commit -qm b >/dev/null
  git checkout -qb feat >/dev/null 2>&1; echo code > app.py; git add -A; git commit -qm w >/dev/null
  out="$(PATH="$SHIM_FR:$PATH" bash "$GITHUB_WORKSPACE/shared/.plinth/risk-classify.sh" main 2>/dev/null || true)"
  [ "$(printf '%s' "$out" | jq -r .tier 2>/dev/null)" = "1" ] || { echo "::error::#15 risk-classify under French cat-file stderr shim failed absence (out=$out)"; exit 1; } )
# #15 inline_contract empty policy: RC_FILE empty after materialization → die_infra at empty check
# (status-checked empty-contract gate)
T_EMPTY="$(mktemp -d)"; ( cd "$T_EMPTY"; git init -qb main . >/dev/null; git config user.email x@x; git config user.name x
  mkdir -p .plinth; : > .plinth/reviewer.md; echo a > f; git add -A; git commit -qm b >/dev/null
  base_tip="$(git rev-parse HEAD)"; SDIR="$(mktemp -d)"; RC_FILE="$SDIR/reviewer-contract.md"
  # Materialize empty base reviewer.md
  BLK_E="$(mktemp)"; awk '/^RC_FILE=/ {p=1} p{print} /^\[ -s "\$RC_FILE" \]/ {if(p){print; exit}}' \
    "$GITHUB_WORKSPACE/shared/.plinth/review.sh" > "$BLK_E"
  set +e
  err="$(base_tip="$base_tip" SDIR="$SDIR" RC_FILE="$RC_FILE" bash -c '
    set -euo pipefail
    die_infra() { echo "die_infra: $*" >&2; exit 9; }
    source '"$BLK_E"'
  ' 2>&1)"; erc=$?
  set -e
  [ "$erc" -ne 0 ] || { echo "::error::#15 empty reviewer contract did not die_infra"; exit 1; }
  printf '%s' "$err" | grep -qiE 'empty|die_infra' || { echo "::error::#15 empty contract message missing (err=$err)"; exit 1; } )
