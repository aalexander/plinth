# SPEC — Plinth

Plinth's canonical spec is split across two living documents:

- **MANUAL.md** — the operator contract: what the system promises and how it
  is used. (`spec_path` in `.plinth/config` points here.)
- **CHANGELOG.md** — the behavioral record: every enforced mechanism, the
  failure that motivated it, and its stated limits.

A diff conforms if MANUAL.md still tells the truth after it lands, and if any
behavior change carries a CHANGELOG entry and a VERSION bump.
