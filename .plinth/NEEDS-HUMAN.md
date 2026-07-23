# Blocked on you

- [ ] After tagging **v4.5.0**, bump this repo's own required gates in `.github/workflows/ci.yml`
  (`floor` + `checks`, currently pinned `@259ae5…` / v4.1.9) to the v4.5.0 SHA — the required gate
  intentionally trails the latest tag for immutability, so the new floor checks (lane tooling
  bytes + executable mode) only become the *required* gate once repinned post-tag. The
  `floor-current`/`checks-current` twins already exercise them on every PR.
- [ ] On the FIRST real PR (this repo + anvil/certeus), verify the exact required-check context
  format GitHub emits for the reusable floor/checks jobs — it may be `CI / floor / secrets`
  (workflow-prefixed) or `floor / secrets` (job component only). The preflight now accepts EITHER,
  but confirm the actual strings and use them verbatim in branch protection.
- [ ] Certeus: confirm the Codex cloud CI reviews are now being pulled and their findings addressed
  (they were previously not fetched). Re-run the review loop there if any were missed.
