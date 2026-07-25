# Changelog fragments

Parallel branches that each edit `VERSION` and the top of `CHANGELOG.md` collide:
they pick the same next number from the same base, and they both insert text at the
same place in the file. Fragments fix that — a branch declares *intent* (the bump
level and the prose); `plinth changelog-collate` computes the *number* at release
time. Unique filenames mean no two branches touch the same file.

This is the towncrier / changesets / reno pattern.

## Fragment format

Create one file per change: `changelog.d/<slug>.md`, where `<slug>` matches
`[a-z0-9][a-z0-9._-]*`.

```
bump: patch|minor|major
---
- **Headline.** Free-form markdown body, one or more bullet lines.
```

- The `bump:` line MUST be the first line. Allowed values: `patch`, `minor`, `major`.
- `---` on its own line separates the header from the body.
- The body MUST contain one or more bullet lines (lines starting with `- `).
- The `<slug>` in the filename must match `[a-z0-9][a-z0-9._-]*`.
- Record each change **exactly once**: either a fragment (this file) **or** a
  hand-written CHANGELOG/VERSION dual-write, never both for the same change
  (collate would double-record). Until review/CI switches to fragment-only
  (a separate change), ordinary product PRs keep dual-write; use fragments when
  the same ship runs `plinth changelog-collate` so VERSION/CHANGELOG are produced
  from pending intent without every branch racing the same two files.

## Release

From the Plinth checkout (or pass a target repo):

```
plinth changelog-collate
```

That command:

1. Reads every `changelog.d/*.md` except this `README.md`.
2. Takes the **highest** bump across fragments (major > minor > patch).
3. Writes a new section at the top of `CHANGELOG.md`, updates `VERSION`, and
   deletes the collated fragment files (this README and `.gitkeep` stay).

If there are no fragments, collate is a no-op (exit 0). An invalid or missing
`bump:` is a hard error that names the file and leaves `VERSION` / `CHANGELOG.md`
unchanged.
