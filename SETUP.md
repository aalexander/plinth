# Plinth — one-time setup

1. Push this repo to GitHub as PUBLIC `OWNER/plinth`; tag it:
       git tag v3 && git push origin v3
   (Public means projects can call plinth-floor.yml with zero access config.)
2. Put the CLI on PATH:
       sudo ln -s "$(pwd)/bin/plinth" /usr/local/bin/plinth
3. Per machine: Claude Code (native installer; sign in with Max), Codex CLI
   (`npm i -g @openai/codex`; sign in with ChatGPT), `brew install jq`,
   and `~/.codex/config.toml`:
       model = "gpt-5.5"
       model_reasoning_effort = "high"
4. Connect Codex Security to your repos once (chatgpt.com -> Codex).
5. Per project: `plinth init ~/Dev/<repo>`; edit SPEC.md; commit (ci.yml is
   zero-edit: owner auto-injected, checks auto-detect the stack); protect `main`
   requiring the `floor` and `checks` status checks.
6. In Claude Code: `/model` -> Fable 5; `/effort` -> ultracode for big tasks.
