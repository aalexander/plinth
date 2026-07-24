# Project-Specific Reviewer Rules
<!-- Rules here EXTEND the shared reviewer contract (.plinth/reviewer.md) and are never overwritten by
     `plinth update`. Put domain-specific blocking criteria here — e.g. for a
     regulated product: "flag any regulatory citation introduced into user- or
     audit-facing output that is not backed by a verified primary source; treat
     as CHANGES_NEEDED." Delete this comment when you add real rules. -->

## Threat model note (adjust per project)
If you delegate implementation to a TRUSTED worker (e.g. an implementer lane),
scope-check tooling that guards the delegation is an ERROR-catcher, not an
adversarial sandbox. Block on real error-catching gaps, fail-opens, unimplemented
enforcement claims, and missing tests — but do NOT block on defeating a trusted
worker's deliberate evasion (exfil via a needed web-search capability, etc.); the
boundary there is the vendor sandbox + human review. Match rigor to your trust model.
