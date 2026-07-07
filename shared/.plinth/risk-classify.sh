#!/usr/bin/env bash
# Plinth risk classifier (shared, version-pinned). Deterministically assigns a
# change a RISK TIER from the diff alone — no model, no human, not driver-
# writable (it is version-pinned tooling; the driver cannot de-escalate it).
# review.sh routes review depth by the tier. Conservative by construction:
# unknown -> Tier 1; any high-risk signal -> Tier 2; Tier 0 only when EVERY
# changed file is clearly inert.
#
#   Tier 0  docs/text only            -> CI floor handles it; skip model review
#   Tier 1  ordinary project code     -> standard adversarial review
#   Tier 2  high-consequence surface  -> full review (+ cross-vendor/extra, later)
#
# Emits JSON: {tier, reasons:[...], files, base_ref}. Usage: risk-classify.sh <base>
set -euo pipefail
base="${1:-main}"

# Optional per-project extra patterns from .plinth/config (agent-immutable):
#   tier2_extra = <grep -E pattern>   force Tier 2 for matching paths
cfg() { sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" .plinth/config 2>/dev/null | head -1; }
TIER2_EXTRA="$(cfg tier2_extra || true)"
SPEC_PATH="$(cfg spec_path || true)"; [ -n "$SPEC_PATH" ] || SPEC_PATH="SPEC.md"

if git rev-parse --verify --quiet "origin/${base}" >/dev/null 2>&1; then baseref="origin/${base}"
elif git rev-parse --verify --quiet "${base}" >/dev/null 2>&1; then baseref="${base}"
else printf '{"tier":1,"reasons":["base ref not found; defaulting Tier 1"],"files":0,"base_ref":"%s"}\n' "$base"; exit 0; fi

names="$(git diff --name-status "${baseref}...HEAD" 2>/dev/null || true)"
[ -n "$names" ] || { printf '{"tier":0,"reasons":["empty diff"],"files":0,"base_ref":"%s"}\n' "$baseref"; exit 0; }

# High-consequence path signals (Tier 2).
TOOLING='(^|/)\.plinth/|(^|/)\.claude/|(^|/)\.github/|(^|/)AGENTS\.md$'
SECURITY='(auth|crypto|secret|credential|password|passwd|token|login|session|permission|rbac|acl|oauth|jwt|signing|keystore)'
MIGRATION='(migrat|/schema\.|\.sql$|alembic|/prisma/|liquibase|flyway)'
PUBAPI='(openapi|swagger|\.proto$|schema\.(graphql|json)$|(^|/)api/)'
DEPS='(^|/)(package\.json|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|requirements[^/]*\.(txt|in)|requirements[^/]*\.lock|Pipfile|poetry\.lock|pyproject\.toml|Cargo\.(toml|lock)|go\.(mod|sum)|Gemfile(\.lock)?|composer\.(json|lock))$'
TESTS='(^|/)(tests?|specs?|__tests__)/|(_test|\.test|\.spec|_spec)\.'
# Tier-0-eligible (inert) paths: non-spec docs and text.
DOCS='\.(md|markdown|rst|txt|adoc)$|(^|/)(LICENSE|NOTICE|AUTHORS|CHANGELOG)|(^|/)\.gitignore$'

tier=0; reasons=(); nfiles=0
add_reason() { reasons+=("$1"); }
bump() { [ "$1" -gt "$tier" ] && tier="$1" || true; }

while IFS=$'\t' read -r status path rest; do
  [ -n "${status:-}" ] || continue
  # Renames/copies: "R100\told\tnew" — classify the destination.
  case "$status" in R*|C*) path="${rest:-$path}" ;; esac
  [ -n "${path:-}" ] || continue
  nfiles=$((nfiles + 1))

  # Tier 2 — high-consequence surfaces (checked first; tier is the max).
  if printf '%s' "$path" | grep -Eq "$TOOLING"; then bump 2; add_reason "tooling: $path"; continue; fi
  if [ "$path" = "$SPEC_PATH" ] || printf '%s' "$path" | grep -Eq "^${SPEC_PATH}/"; then bump 2; add_reason "spec: $path"; continue; fi
  if printf '%s' "$path" | grep -Eiq "$SECURITY"; then bump 2; add_reason "security-sensitive: $path"; continue; fi
  if printf '%s' "$path" | grep -Eq "$MIGRATION"; then bump 2; add_reason "migration/schema: $path"; continue; fi
  if printf '%s' "$path" | grep -Eq "$PUBAPI"; then bump 2; add_reason "public API/schema: $path"; continue; fi
  if printf '%s' "$path" | grep -Eq "$DEPS"; then bump 2; add_reason "dependency manifest: $path"; continue; fi
  if [ -n "$TIER2_EXTRA" ] && printf '%s' "$path" | grep -Eq "$TIER2_EXTRA"; then bump 2; add_reason "project tier2_extra: $path"; continue; fi

  # Tests: a DELETED test, or one whose diff removes more assertions than it
  # adds, is the classic loosen-hidden-in-the-test-diff vector -> Tier 2.
  if printf '%s' "$path" | grep -Eq "$TESTS"; then
    if [ "$status" = "D" ]; then bump 2; add_reason "deleted test: $path"; continue; fi
    added="$(git diff "${baseref}...HEAD" -- "$path" 2>/dev/null | grep -Ec '^\+.*(assert|expect|should|\.to[A-Z(]|require\()' || true)"
    removed="$(git diff "${baseref}...HEAD" -- "$path" 2>/dev/null | grep -Ec '^-.*(assert|expect|should|\.to[A-Z(]|require\()' || true)"
    if [ "${removed:-0}" -gt "${added:-0}" ]; then bump 2; add_reason "test weakened (−$removed/+$added assertions): $path"; continue; fi
    bump 1; add_reason "test change: $path"; continue
  fi

  # Any file deletion is non-trivial -> at least Tier 1.
  if [ "$status" = "D" ]; then bump 1; add_reason "deletion: $path"; continue; fi

  # Tier 0 — inert docs/text only.
  if printf '%s' "$path" | grep -Eq "$DOCS"; then add_reason "docs: $path"; continue; fi

  # Everything else: ordinary code -> Tier 1.
  bump 1; add_reason "code: $path"
done <<< "$names"

# JSON out (reasons capped for readability).
printf '{"tier":%s,"files":%s,"base_ref":"%s","reasons":[' "$tier" "$nfiles" "$baseref"
for i in "${!reasons[@]}"; do
  [ "$i" -ge 12 ] && { printf '%s"… +%s more"' "$([ "$i" -gt 0 ] && echo ,)" "$(( ${#reasons[@]} - 12 ))"; break; }
  printf '%s%s' "$([ "$i" -gt 0 ] && echo ,)" "$(printf '%s' "${reasons[$i]}" | jq -Rsc 'rtrimstr("\n")')"
done
printf ']}\n'
