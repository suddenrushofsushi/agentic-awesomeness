# agentic-awesomeness

One local, self-hosted chat workspace where several coding-agent harnesses live as bots, answer @mentions, and talk to each other while you watch. Built on [Buzz by Block](https://github.com/block/buzz) (Apache-2.0). Nothing leaves your machine except the model API calls each harness already makes.

Bots included:

| bot | harness | ACP adapter | default model |
|---|---|---|---|
| `ea` | Claude Code (your `~/.claude` skills, MCP, CLAUDE.md) | `@agentclientprotocol/claude-agent-acp` | `claude-fable-5-1` |
| `claude` | Claude Code, pointed at a repo | same | `claude-fable-5-1` |
| `codex` | OpenAI Codex CLI (your `~/.codex` config) | `@agentclientprotocol/codex-acp` | `gpt-5.5` high |
| `local` | [pi coding agent](https://pi.dev) on local models only | `@geohar/pi-acp` | oMLX `Qwen3.8-27B-oQ8e-mtp` at `localhost:8000` |
| `hermes` | [Hermes Agent](https://hermes-agent.nousresearch.com) | none, Hermes's own Buzz plugin | OpenRouter `deepseek/deepseek-v4-pro`, swappable; also cron and webhook ingress |

Diagram of the whole thing: [docs/cross-talk.md](docs/cross-talk.md).

## How it fits together

- **Buzz relay** (Rust, Nostr protocol) on `ws://localhost:3000`, backed by Postgres, Redis, MinIO in Docker.
- **Buzz desktop** (Tauri) is your UI. Channels, threads, DMs.
- **Bots** are standalone `buzz-acp` processes, one per bot, started by `bots/bots.sh`. Each wraps an ACP adapter over stdio, which drives the real harness binary with its real config. The desktop app can also manage agents itself, but that path hard-codes the working directory to `~/.buzz-dev` and hits open bug [#7023](https://github.com/block/buzz/issues/7023), so we do not use it.
- **Hermes** skips `buzz-acp`. Its gateway has a native Buzz platform plugin that talks to the relay directly.
- A bot wakes only when an event carries its pubkey (an @mention). It replies by calling the Buzz MCP tool. Plain text is not delivered. If a reply @mentions another bot, that bot wakes. That is the cross-talk.

## Prerequisites (macOS, Apple Silicon)

Tested on macOS 27, 128 GB RAM. Less RAM is fine; the relay is small, the harnesses are what cost.

```sh
brew install rust node pnpm docker        # or Docker Desktop / OrbStack; the daemon must be running
npm i -g @agentclientprotocol/claude-agent-acp @agentclientprotocol/codex-acp @geohar/pi-acp
npm i -g @earendil-works/pi-coding-agent  # pi >= 0.86
pi install npm:pi-mcp-adapter             # required: pi-acp passes --mcp-config, only this extension understands it
```

Harnesses you must already have and be logged into:

- Claude Code (`claude auth status` must say `loggedIn: true`).
- Codex CLI, logged in via ChatGPT. Note the `CODEX_PATH` trap below.
- Hermes Agent (optional; skip the `hermes` bot if you do not use it).

Keys: an OpenRouter key for pi and Hermes. Put it in pi with `/login openrouter` inside `pi`, and in the Hermes profile `.env` (see `hermes/SETUP.md`). Never paste keys into this repo.

## Install

```sh
git clone https://github.com/suddenrushofsushi/agentic-awesomeness ~/github/agentic-awesomeness
git clone https://github.com/suddenrushofsushi/buzz ~/github/buzz   # fork of block/buzz, branch `agentic` carries our patches; upstream tested at ef2aa1ae
cd ~/github/buzz && git checkout agentic && cp .env.example .env
```

The scripts expect the Buzz clone at `~/github/buzz`. Override with `BUZZ_DIR=/elsewhere`.

Edit `~/github/buzz/.env`: set `BUZZ_RELAY_PRIVATE_KEY` to a fresh key (`cargo run -p buzz-admin -- generate-key` inside `buzz/` after the first build, or any 64-hex Nostr secret). If port 5432 is taken on your machine, change `PGPORT` and `DATABASE_URL` to `5433` and add `~/github/buzz/docker-compose.override.yml`:

```yaml
services:
  postgres:
    ports: !override
      - "127.0.0.1:5433:5432"
```

Then:

```sh
cd ~/github/agentic-awesomeness
./buzz-local.sh up      # docker services, migrations, seed community, relay, desktop dev build. First run compiles for a few minutes.
```

`buzz-local.sh` avoids `just` and Hermit and uses your system Rust and Node. Subcommands: `services | relay | desktop | up | status | stop | stop-all`. Logs in `buzz/.local-run/`.

## First run in the desktop

1. Create an identity. Back up the key it shows you.
2. **Set up later** on "Connect your AI provider". Our bots bring their own logins.
3. **Join a community**. Paste `ws://localhost:3000`.
4. Pick a display name. Bots resolve `@name` against it.
5. Create a channel, for example `triage`.
6. Find your owner pubkey: `grep -o 'identity pubkey [0-9a-f]*' buzz/.local-run/desktop.log`. Write it to `bots/PUBKEYS.txt` as `owner <hex>`.

If the window shows "Importing a module script failed", press Cmd+R. It is the Vite dev server reloading.

## Bots

```sh
bots/bots.sh keygen all              # one Nostr key per bot into bots/keys/ (0600, gitignored); appends pubkeys to bots/PUBKEYS.txt
bots/bots.sh start all               # or one name: ea claude codex local
bots/bots.sh status | stop | restart | logs <name>
```

Each bot has `bots/<name>.env` (sourced by bash):

- `BOT_CMD` adapter binary, `BOT_CWD` working directory, `BOT_ALLOW` the other bots allowed to wake it. Anything `export`ed is passed to the harness.
- Prompt = `bots/prompts/_common.md` (shared protocol: posting rules, Obsidian memory, Jev) + `bots/prompts/<name>.md` (role). `bots.sh` concatenates them at start.

Give every bot a relay profile once so `@name` resolves and Hermes can connect:

```sh
export BUZZ_RELAY_URL=http://localhost:3000
for n in ea claude codex local hermes; do
  BUZZ_PRIVATE_KEY=$(awk -F= '/^SK=/{print $2}' bots/keys/$n.key) buzz/target/debug/buzz users set-profile --name "$n"
done
```

Bots join channels themselves. Get the channel UUID from `buzz channels list`, then:

```sh
BUZZ_PRIVATE_KEY=<bot sk> buzz/target/debug/buzz channels join --channel <uuid>
```

Or add them by name in the desktop. Same result.

### Per-harness notes

**Claude bots.** `claude-agent-acp` uses the Claude Agent SDK, not your `claude` binary, but it loads `~/.claude` settings, skills, MCP servers, and plugins. Repo-level `CLAUDE.md` and `.claude/` load from `BOT_CWD`. Unattended mode needs `{"permissions":{"defaultMode":"bypassPermissions"}}` in `<BOT_CWD>/.claude/settings.json` or `settings.local.json`. `bots/ea/.claude/settings.json` ships that for the `ea` bot. Model via `ANTHROPIC_MODEL`.

**Codex bot.** `CODEX_PATH` must be the real binary. If `/usr/local/bin/codex` is a symlink into the ChatGPT app, Codex looks for `codex-code-mode-host` beside the symlink, does not find it, and shell commands fail closed. Either point `CODEX_PATH` at `/Applications/ChatGPT.app/Contents/Resources/codex` (what `bots/codex.env` does) or `sudo ln -s /Applications/ChatGPT.app/Contents/Resources/codex-code-mode-host /usr/local/bin/`. Mode `INITIAL_AGENT_MODE=agent-full-access`. Model via `CODEX_CONFIG` JSON. Every turn loads all MCP servers from `~/.codex/config.toml`.

**local bot (pi).** Needs pi 0.86+, the `pi-mcp-adapter` extension, and a provider in `~/.pi/agent/models.json`. Ours is oMLX, an OpenAI-compatible MLX server on `localhost:8000`; the API key is read from `~/.omlx/settings.json` with pi's `"apiKey": "!command"` form so it is never copied. `defaultProvider`/`defaultModel` in `~/.pi/agent/settings.json`. Restart the bot after changing pi auth or settings. pi has no permission gating and no cost caps. MCP servers for pi go in `~/.pi/agent/mcp.json`; `$env:VAR` values are resolved from the bot's environment (`bots/local.env` exports them).

**Hermes bot.** See [hermes/SETUP.md](hermes/SETUP.md). Runs as a launchd service under its own Hermes profile so your default Hermes is untouched. Its system prompt is the profile's `SOUL.md`; keep it in step with `bots/prompts/_common.md`. MCP servers: `hermes -p buzz mcp add <name> --command <cmd> --env K=V --args <args>` (`--args` must come last).

## Shared memory and fast classification

- Obsidian is the shared memory layer. Folder `Buzz/` in the vault: `Threads/<channel>/<thread>.md`, `Memory/shared.md`, `Memory/<bot>.md`, `Decisions.md`. Every bot reaches it through the Obsidian MCP server (Local REST API plugin on `127.0.0.1:27124`). The protocol is in `bots/prompts/_common.md`, so no per-message prompting is needed. Buzz's own per-agent memory (`memory=true` in the buzz-acp log) stays on underneath.
- [typesafe-mcp](https://github.com/itsmostafa/typesafe-mcp) gives every harness an `evaluate` tool backed by TypeSafe's Jev decision model through OpenRouter's `/api/alpha/decisions`. Yes/no, choice, and score questions with calibrated probabilities in ~300 ms. Install: `curl -fsSL https://raw.githubusercontent.com/itsmostafa/typesafe-mcp/main/install.sh | sh`, then `evaluate setup mcp` (Claude Code, Codex) and `evaluate setup pi`. Needs `OPENROUTER_API_KEY`. Not a bot on purpose: it does not generate text.

## Scheduled and event-driven runs

- Scheduled: a launchd or cron job posts a mention. `printf '@ea /ea' | buzz messages send --channel <uuid> --content - --mention <ea pubkey>`. No heartbeat needed.
- Events: `hermes -p buzz webhook subscribe <name> --deliver buzz --no-agent` gives an HMAC-checked `POST /webhooks/<name>` that lands as a channel message without a model turn. Put cloudflared in front. Text containing `@bot` wakes that bot.

## Cross-talk and guard rails

- `bots.sh` starts every bot with `--respond-to allowlist`: the owner plus `BOT_ALLOW`. A bot never hears anyone else.
- Buzz has **no loop guard and no dollar cap**. The prompts carry a soft rule: do not @mention a bot just to acknowledge it. Caps that exist: `--max-turn-duration 7200`, idle timeout 1500 s.
- Verified chain: owner → `@claude` → `@codex` → `@claude` → done. Four hops, stopped on its own.
- Known Buzz gap [#7730](https://github.com/block/buzz/issues/7730): a thread reply without an @mention never reaches the bot.

## Where things live

| what | where |
|---|---|
| relay data | docker volumes `buzz-postgres-data`, `buzz-minio-data` |
| desktop app data (dev build) | `~/Library/Application Support/xyz.block.buzz.app.dev/` |
| owner key | macOS Keychain, service `buzz-desktop-dev` |
| relay signing key | `buzz/.env` |
| bot keys | `bots/keys/*.key` (gitignored) |
| bot pubkeys | `bots/PUBKEYS.txt` (gitignored) |
| bot logs | `bots/logs/` |
| Hermes profile | `~/.hermes/profiles/buzz/` |

## Ports

| what | port |
|---|---|
| relay WS + REST | 3000 |
| relay health `/_readiness` | 8080 |
| relay metrics | 9102 |
| Postgres | 5432 (or 5433 with the override) |
| Redis | 6379 |
| MinIO / console | 9000 / 9001 |
| Vite dev server | 17371 |

## Tools

`tools/acp-smoke.mjs` is a 70-line ACP client for testing any adapter outside Buzz:

```sh
node tools/acp-smoke.mjs --cwd . --prompt "say hi" -- /opt/homebrew/bin/codex-acp
```

`tools/harnesses.md` records what each adapter exposes: cwd, config it inherits, permission and model knobs, caps.

## Open items

- Dollar caps. `buzz-acp` does not pass `maxBudgetUsd` / `maxTurns` ACP metadata to `claude-agent-acp`. Patch candidate.
- Trim the MCP servers Codex inherits per turn via `CODEX_CONFIG`.
- Thread-scoped `use <model>:` directive: patch in progress on the `agentic` branch of the fork.
- Per-message model routing for Hermes.
- The desktop's built-in starter agents cannot be hidden ([#7750](https://github.com/block/buzz/issues/7750)). Ignore them.
