#!/usr/bin/env bash
# Plinth risk classifier (shared, version-pinned). Deterministically assigns a
# change a RISK TIER from the diff alone — no model, no human, not driver-
# writable (version-pinned tooling; the driver cannot de-escalate it).
# Conservative by construction: unknown -> Tier 1; any high-risk signal -> Tier 2;
# Tier 0 only when EVERY changed object is a plain, inert doc blob.
#
#   Tier 0  inert docs (regular blobs)  -> CI floor handles it; skip model review
#   Tier 1  ordinary project code       -> standard adversarial review
#   Tier 2  high-consequence surface    -> full review (+ cross-vendor)
#
# Hardened per cross-vendor red-team (GPT/Grok/Gemini, all "critical"): uses
# `git diff --raw` for modes + BOTH rename paths; no global .txt in Tier 0;
# metadata names anchored; any modification of an existing test -> Tier 2.
# Emits JSON: {tier, reasons:[...], files, base_ref}. Usage: risk-classify.sh <base>
set -euo pipefail
base="${1:-main}"

cfg() { sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" .plinth/config 2>/dev/null | head -1; }
TIER2_EXTRA="$(cfg tier2_extra || true)"   # working-tree ok: can only ADD Tier 2

if git rev-parse --verify --quiet "origin/${base}" >/dev/null 2>&1; then baseref="origin/${base}"
elif git rev-parse --verify --quiet "${base}" >/dev/null 2>&1; then baseref="${base}"
else printf '{"tier":1,"reasons":["base ref not found; defaulting Tier 1"],"files":0,"base_ref":"%s"}\n' "$base"; exit 0; fi

# An invalid tier2_extra regex (a typo in this agent-immutable routing knob) must
# fail CLOSED, not silently disable the Tier-2 surface: grep exits 2 on a bad
# pattern, which the per-file `if ... grep -Eq "$TIER2_EXTRA"` below reads as a
# plain "no match", letting intended Tier-2 paths slip to Tier 0/1. Validate the
# pattern ONCE against empty input (valid -> exit 0/1; invalid -> >=2).
if [ -n "$TIER2_EXTRA" ]; then
  t2rc=0; printf '' | grep -Eq "$TIER2_EXTRA" 2>/dev/null || t2rc=$?
  if [ "$t2rc" -ge 2 ]; then
    printf '{"tier":2,"files":0,"base_ref":"%s","reasons":["invalid tier2_extra regex in .plinth/config — failing closed to Tier 2"]}\n' "$baseref"
    exit 0
  fi
fi

# spec_path is read from the BASE config, not the working tree: repointing
# spec_path in the same PR must not downgrade that PR's own spec edits. The
# canonical spec paths are ALWAYS Tier 2 regardless of config (defense in depth).
SPEC_PATH="$(git show "${baseref}:.plinth/config" 2>/dev/null | sed -n 's/^spec_path[[:space:]]*=[[:space:]]*//p' | head -1)"
[ -n "$SPEC_PATH" ] || SPEC_PATH="$(cfg spec_path || true)"
[ -n "$SPEC_PATH" ] || SPEC_PATH="SPEC.md"
SPECRE='(^|/)SPEC(\.md)?$|(^|/)spec/|(^|/)SPEC/'
is_spec() { [ "$1" = "$SPEC_PATH" ] || [ "${1#"$SPEC_PATH"/}" != "$1" ] || printf '%s' "$1" | grep -Eq "$SPECRE"; }

raw="$(git diff --raw -M -C "${baseref}...HEAD" 2>/dev/null || true)"
[ -n "$raw" ] || { printf '{"tier":0,"reasons":["empty diff"],"files":0,"base_ref":"%s"}\n' "$baseref"; exit 0; }

# High-consequence path signals (Tier 2). Case-insensitive matching below.
TOOLING='(^|/)\.plinth/|(^|/)\.claude/|(^|/)\.github/|(^|/)\.gitlab-ci|(^|/)\.circleci/|(^|/)\.buildkite/|(^|/)Jenkinsfile|(^|/)azure-pipelines|(^|/)AGENTS\.md$|(^|/)CLAUDE\.md$|(^|/)PLANNING-PROMPT\.md$|(^|/)\.gitattributes$|(^|/)\.gitmodules$'
BUILD='(^|/)(Makefile|CMakeLists\.txt|Dockerfile|docker-compose[^/]*\.ya?ml|setup\.py|setup\.cfg|MANIFEST\.in|tox\.ini|build\.gradle|settings\.gradle|pom\.xml|WORKSPACE|MODULE\.bazel|BUILD\.bazel|flake\.nix)$|\.cmake$|(^|/)scripts/(release|deploy|publish)'
SECURITY='(auth|crypto|secret|credential|password|passwd|token|login|session|permission|rbac|acl|oauth|jwt|signing|keystore|access|policy|identity|sso|saml|mfa|totp|webauthn|csrf|cors|cookie|cert|tls|x509|guard|roles?|cipher|encrypt|decrypt|hash|nonce)'
MIGRATION='(migrat|/schema\.|\.sql$|alembic|/prisma/|liquibase|flyway|db_.*update|alter_.*table|/models?\.py$|/entities/)'
PUBAPI='(openapi|swagger|asyncapi|\.proto$|\.graphql$|\.gql$|schema\.(graphql|json)$|(^|/)api/|(^|/)(routes?|controllers?|handlers?|endpoints?)[./])'
DEPS='(^|/)(requirements[^/]*\.(txt|in|lock)|.*requirements[^/]*\.txt|constraints[^/]*\.txt|package\.json|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Pipfile(\.lock)?|uv\.lock|poetry\.lock|pyproject\.toml|Cargo\.(toml|lock)|go\.(mod|sum|work)|Gemfile(\.lock)?|composer\.(json|lock)|environment\.yml|conda-lock\.yml|mix\.(exs|lock)|Podfile(\.lock)?|Package\.resolved|vcpkg\.json|conanfile\.(txt|py)|gradle\.lockfile|bun\.lockb?)$'
TESTS='(^|/)(tests?|specs?|__tests__|testdata|fixtures?|golden|baselines?|snapshots?|__snapshots__|test_helpers?|testing|support)/|(_test|\.test|\.spec|_spec)\.|(^|/)test_'
# Test-RUNNER CONFIG (pytest.ini/conftest.py/jest.config.*/…). Unlike a test FILE,
# ADDING one is NOT additive: a new config can disable or narrow existing test
# discovery (empty testMatch, addopts=--ignore, an autouse skip fixture). So ANY
# change — add, modify, or delete — is high-consequence Tier 2, handled below as
# its own surface rather than through the test-FILE add=Tier-1 path. (tox.ini,
# setup.cfg, pyproject.toml are already Tier 2 via BUILD/DEPS.)
TEST_CONFIG='(^|/)(conftest\.py|pytest\.ini)$|(^|/)(jest|vitest|playwright|cypress|karma|wdio|mocha|ava|jasmine)\.(config|conf)\.[^/]+$|(^|/)\.(mocharc|nycrc)'
SKIPADD='(@[a-zA-Z.]*[Ss]kip|\.skip\(|\bxit\(|\bxdescribe\(|t\.Skip|@Ignore|@Disabled|pytest\.mark\.skip|#\[ignore\])'
# Tier-0-eligible (inert) docs. NOTE: no bare \.txt$ (CMakeLists.txt/constraints
# .txt are code); .txt only for anchored metadata names or under docs/.
DOCS='\.(md|markdown|rst|adoc)$|(^|/)(README|LICENSE|NOTICE|AUTHORS|CHANGELOG|CONTRIBUTING|CODE_OF_CONDUCT)(\.(md|markdown|rst|txt|adoc))?$|(^|/)docs/.*\.txt$'

tier=0; reasons=(); nfiles=0
add_reason() { reasons+=("$1"); }
bump() { [ "$1" -gt "$tier" ] && tier="$1" || true; }
is_test() { printf '%s' "$1" | grep -Eq "$TESTS"; }

while IFS=$'\t' read -r meta p2 p3; do
  [ -n "${meta:-}" ] || continue
  # meta: ":oldmode newmode oldsha newsha status"
  # shellcheck disable=SC2086
  set -- $meta; newmode="${2:-}"; status="${5:-}"
  case "$status" in
    R*|C*) oldpath="$p2"; path="${p3:-$p2}" ;;
    *)     oldpath=""; path="$p2" ;;
  esac
  [ -n "${path:-}" ] || continue
  nfiles=$((nfiles + 1))

  # Object type/mode: name-status hides these. A symlink, submodule, executable,
  # or type-change can never be Tier 0 (a "docs" name can be a symlink to code).
  case "$newmode" in
    120000) bump 2; add_reason "symlink: $path"; continue ;;
    160000) bump 2; add_reason "submodule: $path"; continue ;;
  esac
  # Any execute bit (owner/group/other) disqualifies Tier 0 — a "docs" name with
  # an exec bit is not inert. Last 3 mode digits are the perms; odd = exec bit.
  case "${newmode: -3}" in *[1357]*) bump 1; add_reason "executable: $path" ;; esac
  [ "$status" = "T" ] && { bump 1; add_reason "type change: $path"; }

  # Renames/copies: the OLD path matters too — moving a test or sensitive file
  # out of its tree must not launder it into an inert destination.
  if [ -n "$oldpath" ]; then
    if is_test "$oldpath" && ! is_test "$path"; then bump 2; add_reason "test moved out of test tree: $oldpath -> $path"; continue; fi
    if is_spec "$oldpath"; then bump 2; add_reason "spec moved: $oldpath -> $path"; continue; fi
    if printf '%s' "$oldpath" | grep -Eiq "$SECURITY|$MIGRATION|$TOOLING|$BUILD"; then bump 2; add_reason "sensitive/tooling source moved: $oldpath -> $path"; continue; fi
    # Renaming real content (non-doc source) into an inert destination is the
    # "relabel code as docs" bypass — it can never be Tier 0. Floor to Tier 1,
    # then let the destination-path rules escalate further if they match.
    if ! printf '%s' "$oldpath" | grep -Eq "$DOCS"; then bump 1; add_reason "renamed from non-doc source: $oldpath -> $path"; fi
  fi

  # Tier 2 — high-consequence surfaces (case-insensitive; tier is the max).
  if printf '%s' "$path" | grep -Eiq "$TOOLING"; then bump 2; add_reason "tooling: $path"; continue; fi
  if printf '%s' "$path" | grep -Eiq "$BUILD"; then bump 2; add_reason "build system: $path"; continue; fi
  if is_spec "$path"; then bump 2; add_reason "spec: $path"; continue; fi
  if printf '%s' "$path" | grep -Eiq "$SECURITY"; then bump 2; add_reason "security-sensitive: $path"; continue; fi
  if printf '%s' "$path" | grep -Eiq "$MIGRATION"; then bump 2; add_reason "migration/schema: $path"; continue; fi
  if printf '%s' "$path" | grep -Eiq "$PUBAPI"; then bump 2; add_reason "public API/schema: $path"; continue; fi
  if printf '%s' "$path" | grep -Eiq "$DEPS"; then bump 2; add_reason "dependency manifest: $path"; continue; fi
  if [ -n "$TIER2_EXTRA" ] && printf '%s' "$path" | grep -Eq "$TIER2_EXTRA"; then bump 2; add_reason "project tier2_extra: $path"; continue; fi
  if printf '%s' "$path" | grep -Eq "$TEST_CONFIG"; then bump 2; add_reason "test-runner config (can disable/narrow the suite): $path"; continue; fi

  # Tests: deletion, ANY modification of an existing test (removed content), or a
  # skip/ignore added -> Tier 2. Net assertion counting is gameable by padding,
  # so we escalate on any touch of existing test content. Pure NEW test files or
  # addition-only changes stay Tier 1.
  if is_test "$path"; then
    if [ "$status" = "D" ]; then bump 2; add_reason "deleted test: $path"; continue; fi
    # ANY modification of an EXISTING test is a potential weakening — removed or
    # loosened assertions, an early return/skip inserted (addition-only, no '-'
    # line!), or a swapped binary baseline. Static diff analysis can't tell a
    # weakening from a genuine addition (net assertion counting is gameable by
    # padding), so escalate on ANY touch of existing test content. Only a brand-NEW
    # test file (status A) stays Tier 1.
    if [ "$status" != "A" ]; then bump 2; add_reason "existing test modified (possible weakening): $path"; continue; fi
    # New test file: additive — but suspicious if it lands pre-skipped/ignored.
    tdiff="$(git diff "${baseref}...HEAD" -- "$path" 2>/dev/null || true)"
    if printf '%s' "$tdiff" | grep -Eq "^\+.*$SKIPADD"; then bump 2; add_reason "new test added pre-skipped/ignored: $path"; continue; fi
    bump 1; add_reason "test added: $path"; continue
  fi

  # Any file deletion is non-trivial -> at least Tier 1.
  if [ "$status" = "D" ]; then bump 1; add_reason "deletion: $path"; continue; fi

  # Tier 0 — inert docs only (regular blob; symlink/submodule handled above).
  if printf '%s' "$path" | grep -Eq "$DOCS"; then add_reason "docs: $path"; continue; fi

  # Everything else: ordinary code -> Tier 1.
  bump 1; add_reason "code: $path"
done < <(printf '%s\n' "$raw")

# Fail CLOSED, never open: raw was already checked non-empty above, so if the
# loop processed zero files the input mechanism failed (e.g. the old here-string
# could emit "cannot create temp file" and leave tier=0). A non-empty diff must
# never emit Tier 0 — default to Tier 2 (full review) so a classifier failure
# can only ever OVER-review, never skip review.
if [ "$nfiles" -eq 0 ]; then
  printf '{"tier":2,"files":0,"base_ref":"%s","reasons":["classifier processed 0 files from a non-empty diff — failing closed to Tier 2"]}\n' "$baseref"
  exit 0
fi

printf '{"tier":%s,"files":%s,"base_ref":"%s","reasons":[' "$tier" "$nfiles" "$baseref"
for i in "${!reasons[@]}"; do
  [ "$i" -ge 12 ] && { printf '%s"… +%s more"' "$([ "$i" -gt 0 ] && echo ,)" "$(( ${#reasons[@]} - 12 ))"; break; }
  printf '%s%s' "$([ "$i" -gt 0 ] && echo ,)" "$(printf '%s' "${reasons[$i]}" | jq -Rsc 'rtrimstr("\n")')"
done
printf ']}\n'
