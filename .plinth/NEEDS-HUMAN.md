# NEEDS-HUMAN

Items only you can supply (agent-immutable config, credentials, decisions).

- [ ] **Set `tier2_extra` in `.plinth/config`** so the Plinth repo's OWN product
  source gets full (Tier-2) review. The generic classifier can't know this repo's
  scope inversion (here `shared/`, `templates/`, `bin/` ARE the product), and a
  docs-only product change (e.g. `shared/MODELS.md`, `shared/plinth-rules.md`,
  `templates/*.md`) currently matches the `.md` docs rule → Tier 0 → skips model
  review. The config is agent-immutable, so the agent can't set this. Add:
      tier2_extra = (^|/)(shared|templates|bin)/
  (Surfaced by the dogfood reviewer on feat/risk-routing, 2026-07-08.)
