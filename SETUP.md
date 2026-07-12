# Plinth — one-time setup

1. Push this repo to GitHub as PUBLIC `OWNER/plinth`; tag it:
       git tag v3 && git push origin v3
   (Public means projects can call plinth-floor.yml with zero access config.)
2. Put the CLI on PATH:
       sudo ln -s "$(pwd)/bin/plinth" /usr/local/bin/plinth
3. Per machine (one CLI per v4 seat — see `.plinth/MODELS.md`): the grok CLI
   ([x.ai/cli](https://x.ai/cli); sign in — the DRIVER seat), Claude Code
   (native installer; sign in with Max — the advisor + audit seats), Codex CLI
   (`npm i -g @openai/codex`; sign in with ChatGPT — the reviewer seat),
   `brew install jq`, and `~/.codex/config.toml`:
       model = "gpt-5.5"        # vendor default; move to "gpt-5.6" at GA
       model_reasoning_effort = "high"
4. Connect Codex cloud code review once (chatgpt.com -> Codex): install the
   GitHub App with repo access and enable review-on-PR-open. Note: this is the
   GENERALIST reviewer — its security coverage comes from the standing
   "Security review (always)" section of AGENTS.md, which it reads and applies;
   no separate "Codex Security" product is assumed to exist.
5. Per project: `plinth init ~/Dev/<repo>`; edit SPEC.md; commit (ci.yml is
   zero-edit: owner auto-injected, checks auto-detect the stack); protect `main`
   requiring the `floor` and `checks` status checks.
6. Daily driving happens in the grok CLI (the v4 driver). When you drive with
   Claude Code instead: `/model` -> Opus 4.8 (Fable 5 by exception, credits);
   `/effort` -> ultracode for big tasks.
