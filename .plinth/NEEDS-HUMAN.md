# Blocked on you

- [ ] After tagging **v4.5.0**, bump this repo's own required gates in `.github/workflows/ci.yml`
  (`floor` + `checks`, currently pinned `@259ae5…` / v4.1.9) to the v4.5.0 SHA — the required gate
  intentionally trails the latest tag for immutability, so the new floor checks (lane tooling
  bytes + executable mode) only become the *required* gate once repinned post-tag. The
  `floor-current`/`checks-current` twins already exercise them on every PR.
