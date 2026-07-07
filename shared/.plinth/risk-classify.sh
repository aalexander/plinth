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
TIER2_EXTRA="$(cfg tier2_extra || true)"
SPEC_PATH="$(cfg spec_path || true)"; [ -n "$SPEC_PATH" ] || SPEC_PATH="SPEC.md"

if git rev-parse --verify --quiet "origin/${base}" >/dev/null 2>&1; then baseref="origin/${base}"
elif git rev-parse --verify --quiet "${base}" >/dev/null 2>&1; then baseref="${base}"
else printf '{"tier":1,"reasons":["base ref not found; defaulting Tier 1"],"files":0,"base_ref":"%s"}\n' "$base"; exit 0; fi

raw="$(git diff --raw -M -C "${baseref}...HEAD" 2>/dev/null || true)"
[ -n "$raw" ] || { printf '{"tier":0,"reasons":["empty diff"],"files":0,"base_ref":"%s"}\n' "$baseref"; exit 0; }

# High-consequence path signals (Tier 2). Case-insensitive matching below.
TOOLING='(^|/)\.plinth/|(^|/)\.claude/|(^|/)\.github/|(^|/)\.gitlab-ci|(^|/)\.circleci/|(^|/)\.buildkite/|(^|/)Jenkinsfile|(^|/)azure-pipelines|(^|/)AGENTS\.md$|(^|/)\.gitattributes$|(^|/)\.gitmodules$'
BUILD='(^|/)(Makefile|CMakeLists\.txt|Dockerfile|docker-compose[^/]*\.ya?ml|setup\.py|setup\.cfg|MANIFEST\.in|tox\.ini|build\.gradle|settings\.gradle|pom\.xml|WORKSPACE|MODULE\.bazel|BUILD\.bazel|flake\.nix)$|\.cmake$|(^|/)scripts/(release|deploy|publish)'
SECURITY='(auth|crypto|secret|credential|password|passwd|token|login|session|permission|rbac|acl|oauth|jwt|signing|keystore|access|policy|identity|sso|saml|mfa|totp|webauthn|csrf|cors|cookie|cert|tls|x509|guard|roles?|cipher|encrypt|decrypt|hash|nonce)'
MIGRATION='(migrat|/schema\.|\.sql$|alembic|/prisma/|liquibase|flyway|db_.*update|alter_.*table|/models?\.py$|/entities/)'
PUBAPI='(openapi|swagger|asyncapi|\.proto$|\.graphql$|\.gql$|schema\.(graphql|json)$|(^|/)api/|(^|/)(routes?|controllers?|handlers?|endpoints?)[./])'
DEPS='(^|/)(requirements[^/]*\.(txt|in|lock)|.*requirements[^/]*\.txt|constraints[^/]*\.txt|package\.json|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Pipfile(\.lock)?|uv\.lock|poetry\.lock|pyproject\.toml|Cargo\.(toml|lock)|go\.(mod|sum|work)|Gemfile(\.lock)?|composer\.(json|lock)|environment\.yml|conda-lock\.yml|mix\.(exs|lock)|Podfile(\.lock)?|Package\.resolved|vcpkg\.json|conanfile\.(txt|py)|gradle\.lockfile|bun\.lockb?)$'
TESTS='(^|/)(tests?|specs?|__tests__|testdata|fixtures?|golden|baselines?|snapshots?|__snapshots__|test_helpers?|testing|support)/|(_test|\.test|\.spec|_spec)\.'
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
  # The review receipt is the classifier's OWN artifact, not a reviewable change
  # — skip it, or committing it would (wrongly) self-classify as a tooling edit.
  case "$path" in .plinth/review-receipt.json) continue ;; esac
  nfiles=$((nfiles + 1))

  # Object type/mode: name-status hides these. A symlink, submodule, executable,
  # or type-change can never be Tier 0 (a "docs" name can be a symlink to code).
  case "$newmode" in
    120000) bump 2; add_reason "symlink: $path"; continue ;;
    160000) bump 2; add_reason "submodule: $path"; continue ;;
    100755) bump 1; add_reason "executable: $path" ;;   # not continue: still check path
  esac
  [ "$status" = "T" ] && { bump 1; add_reason "type change: $path"; }

  # Renames/copies: the OLD path matters too — moving a test or sensitive file
  # out of its tree must not launder it into an inert destination.
  if [ -n "$oldpath" ]; then
    if is_test "$oldpath" && ! is_test "$path"; then bump 2; add_reason "test moved out of test tree: $oldpath -> $path"; continue; fi
    if printf '%s' "$oldpath" | grep -Eiq "$SECURITY|$MIGRATION"; then bump 2; add_reason "sensitive source moved: $oldpath -> $path"; continue; fi
    # Renaming real content (non-doc source) into an inert destination is the
    # "relabel code as docs" bypass — it can never be Tier 0. Floor to Tier 1,
    # then let the destination-path rules escalate further if they match.
    if ! printf '%s' "$oldpath" | grep -Eq "$DOCS"; then bump 1; add_reason "renamed from non-doc source: $oldpath -> $path"; fi
  fi

  # Tier 2 — high-consequence surfaces (case-insensitive; tier is the max).
  if printf '%s' "$path" | grep -Eq "$TOOLING"; then bump 2; add_reason "tooling: $path"; continue; fi
  if printf '%s' "$path" | grep -Eq "$BUILD"; then bump 2; add_reason "build system: $path"; continue; fi
  if [ "$path" = "$SPEC_PATH" ] || [ "${path#"$SPEC_PATH"/}" != "$path" ]; then bump 2; add_reason "spec: $path"; continue; fi
  if printf '%s' "$path" | grep -Eiq "$SECURITY"; then bump 2; add_reason "security-sensitive: $path"; continue; fi
  if printf '%s' "$path" | grep -Eiq "$MIGRATION"; then bump 2; add_reason "migration/schema: $path"; continue; fi
  if printf '%s' "$path" | grep -Eiq "$PUBAPI"; then bump 2; add_reason "public API/schema: $path"; continue; fi
  if printf '%s' "$path" | grep -Eiq "$DEPS"; then bump 2; add_reason "dependency manifest: $path"; continue; fi
  if [ -n "$TIER2_EXTRA" ] && printf '%s' "$path" | grep -Eq "$TIER2_EXTRA"; then bump 2; add_reason "project tier2_extra: $path"; continue; fi

  # Tests: deletion, ANY modification of an existing test (removed content), or a
  # skip/ignore added -> Tier 2. Net assertion counting is gameable by padding,
  # so we escalate on any touch of existing test content. Pure NEW test files or
  # addition-only changes stay Tier 1.
  if is_test "$path"; then
    if [ "$status" = "D" ]; then bump 2; add_reason "deleted test: $path"; continue; fi
    tdiff="$(git diff "${baseref}...HEAD" -- "$path" 2>/dev/null || true)"
    if [ "$status" != "A" ] && printf '%s' "$tdiff" | grep -Eq '^-[^-]'; then
      bump 2; add_reason "existing test modified (possible weakening): $path"; continue
    fi
    if printf '%s' "$tdiff" | grep -Eq "^\+.*$SKIPADD"; then bump 2; add_reason "test skip/ignore added: $path"; continue; fi
    bump 1; add_reason "test added: $path"; continue
  fi

  # Any file deletion is non-trivial -> at least Tier 1.
  if [ "$status" = "D" ]; then bump 1; add_reason "deletion: $path"; continue; fi

  # Tier 0 — inert docs only (regular blob; symlink/submodule handled above).
  if printf '%s' "$path" | grep -Eq "$DOCS"; then add_reason "docs: $path"; continue; fi

  # Everything else: ordinary code -> Tier 1.
  bump 1; add_reason "code: $path"
done <<< "$raw"

printf '{"tier":%s,"files":%s,"base_ref":"%s","reasons":[' "$tier" "$nfiles" "$baseref"
for i in "${!reasons[@]}"; do
  [ "$i" -ge 12 ] && { printf '%s"… +%s more"' "$([ "$i" -gt 0 ] && echo ,)" "$(( ${#reasons[@]} - 12 ))"; break; }
  printf '%s%s' "$([ "$i" -gt 0 ] && echo ,)" "$(printf '%s' "${reasons[$i]}" | jq -Rsc 'rtrimstr("\n")')"
done
printf ']}\n'
