# agentic-awesomeness

Claude Code (in the Claude Desktop Code tab) is the one place you work. From there it drives OpenAI Codex CLI and the [pi coding agent](https://pi.dev) as headless workers. It can hand them tasks, run the same prompt across many models, get a blind second opinion on a design, and send every Claude-written change through a Codex review before any push. Everything runs on your Mac. Only the model API calls leave it.

## Pieces

| path | what it does |
|---|---|
| `bin/agent` | One wrapper: `agent codex`, `agent pi`, `agent review`, `agent stamp`. Read-only unless `--write`. Prints only the final answer; saves prompt, raw events, answer, and metadata under `~/.agent-runs/`. |
| `hooks/push-gate.py` | Claude Code `PreToolUse` hook. Blocks Claude's `git push` unless HEAD has a review stamp. |
| `skills/delegate` | Hand a task to Codex or pi in a folder Claude controls, review the result, land it. |
| `skills/bakeoff` | Same prompt to many models, results side by side. |
| `skills/blind-draft` | Codex drafts a design from the same brief without seeing Claude's; Claude compares the two. |
| `skills/luna-review` | Codex reviews Claude's branch before push; fix-or-dispute loop, max 3 rounds. |
| `tests/smoke.sh` | Offline checks for the gate and stamps, one live prompt per agent, `--review` for one real review. |

```
agent codex  [-m MODEL] [-e EFFORT] [-C DIR] [--write] [--resume ID] PROMPT|-
agent pi     [-m PROVIDER/ID] [-e THINKING] [-C DIR] [--write] [--resume ID] PROMPT|-
agent review [-m MODEL] [-e EFFORT] [-C DIR] [--base REF | --uncommitted] [PROMPT]
agent stamp  [-C DIR] --by claude --note TEXT
```

## Why CLIs and not MCP servers

Codex CLI 0.155 no longer ships `codex mcp-server`. Hermes Agent's MCP mode exposes messaging conversations, not task runs. pi has no MCP server. Claude Code already runs CLIs in the background and gets a notice when each one ends, so a thin wrapper is less code than three servers and has no tool-call timeout.

## Models

| job | harness | default model |
|---|---|---|
| delegated code work | `agent codex` | `gpt-6-sol` |
| design back-and-forth, blind drafts | `agent codex` | `gpt-6-astra` high, `gpt-6-sol` as backup |
| pre-push review | `agent review` (`codex review`) | `gpt-6-luna` high |
| local models | `agent pi` | oMLX `Qwen3.8-27B-oQ8e-mtp` |
| open-weight models | `agent pi -m openrouter/<id>` | any OpenRouter model |
| Claude models | Claude Code subagents | per call |

## Rules the setup enforces

- **Claude owns git.** Claude creates worktrees and branches, commits, and pushes. Workers only read and edit inside the folder they get. `agent` prepends these rules to every task.
- **Codex** runs in its sandbox: `read-only`, or `workspace-write` with network on for `--write`.
- **pi** read-only mode is a tool allowlist (`read,grep,find,ls,evaluate,mcp,mcpScript`). With `--write` pi has no path sandbox, so Claude checks the main tree for stray edits after each pi job.
- **Cross-family review.** Claude-written code goes to Codex `gpt-6-luna`. Code written only by Codex or pi goes to Claude, who then runs `agent stamp --by claude`.
- **Review stamps** live in `<git-common-dir>/agent-review/<sha>`. A new commit needs a new stamp. The gate only stops Claude Code; pushes from your own terminal are not touched. `AGENT_REVIEW_SKIP=1 git push` bypasses it.

## Install

Needs: Claude Code, Codex CLI (logged in), pi 0.86+ with the `pi-mcp-adapter` extension, python3. oMLX is optional, for local models.

```bash
git clone git@github.com:suddenrushofsushi/agentic-awesomeness.git ~/github/agentic-awesomeness
ln -s ~/github/agentic-awesomeness/bin/agent ~/.local/bin/agent
for s in delegate bakeoff blind-draft luna-review; do ln -s ~/github/agentic-awesomeness/skills/$s ~/.claude/skills/$s; done
```

Add the gate to `hooks.PreToolUse` in `~/.claude/settings.json`:

```json
{ "matcher": "Bash", "hooks": [ { "type": "command", "command": "~/github/agentic-awesomeness/hooks/push-gate.py", "timeout": 10 } ] }
```

Then run `tests/smoke.sh` (add `--review` for one real Codex review).

Environment overrides: `CODEX_BIN` (default: the binary inside `ChatGPT.app`), `AGENT_RUNS` (default `~/.agent-runs`).

pi on oMLX, in `~/.pi/agent/models.json`:

```json
{ "providers": { "omlx": {
  "baseUrl": "http://localhost:11800/v1",
  "api": "openai-completions",
  "apiKey": "!python3 -c 'import json;print(json.load(open(\"<home>/.omlx/settings.json\"))[\"auth\"][\"api_key\"])'",
  "models": [ { "id": "Qwen3.8-27B-oQ8e-mtp", "reasoning": true } ] } } }
```

The OpenRouter key goes in `~/.pi/agent/auth.json`. The skills write run notes to an Obsidian vault through an Obsidian MCP server (`Agents/Runs/`). Without one, the reports stay in chat and `~/.agent-runs/`.

## Scheduled runs

Use Claude Desktop scheduled tasks. They run on your Mac with your local MCP servers and files. The app must be open; a run that was missed fires at the next launch. Cloud Routines run on Anthropic machines and cannot reach local MCP servers or files.

## Traps

- `pi -p` waits for stdin when stdin is open. `agent` closes it.
- `codex exec resume` takes no `-s` or `-C`. `agent` uses `-c sandbox_mode=...` and the working folder.
- `codex review` writes findings to stdout and its transcript to stderr. `agent review` keeps them apart.
- `/usr/local/bin/codex` from the ChatGPT app is a symlink. Codex looks for `codex-code-mode-host` next to the path it was started from, so shell tools fail closed unless you call the real binary or link the host too.
- "Selected model is at capacity" is an OpenAI `server_overloaded` error. It is transient: retry, or use the backup model.
- oMLX defaults to port 8000, which docker compose web stacks also like. Move it (`server.port` in `~/.omlx/settings.json`).

## Legacy

`legacy/buzz/` holds the first version: a local [Buzz](https://github.com/block/buzz) chat workspace with the harnesses as bots that talk to each other. Retired 2026-09-23 because the local Buzz stack was unstable. Its README still documents that setup.

## License

MIT
