# Blocked on you

- [ ] After tagging **v4.5.0**, bump this repo's own required gates in `.github/workflows/ci.yml`
  (`floor` + `checks`, now pinned `@5a39ab…` / v4.4.0) to the v4.5.0 SHA — the required gate
  intentionally trails the latest tag by one release for immutability, so v4.5.0's own floor
  changes only become the *required* gate once repinned post-tag. The `floor-current`/`checks-current`
  twins already exercise them on every PR. (The pin was moved v4.1.9 -> v4.4.0 in-branch so the
  required gate carries the v4.2–v4.4 floor/review hardening now, not only after v4.5.0 tags.)
- [ ] Set branch protection to require the exact job-name contexts (GitHub does NOT prefix with
  the workflow name): `floor / secrets`, `floor / sast`, `floor / dependencies / osv-scan`,
  `floor / harness`, and `checks / checks` (or `checks` if you use a direct checks job). The
  preflight matches these; confirm against the first PR's checks list and adjust only if your
  ci.yml renamed the `floor`/`checks` caller jobs.
- [ ] Certeus: confirm the Codex cloud CI reviews are now being pulled and their findings addressed
  (they were previously not fetched). Re-run the review loop there if any were missed.
