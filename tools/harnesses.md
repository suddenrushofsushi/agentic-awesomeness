# ACP harness notes

What each adapter exposes when driven over ACP v1 on stdio. Verified 2026-09-20 with `acp-smoke.mjs`.

| harness | package | wraps |
|---|---|---|
| claude | `@agentclientprotocol/claude-agent-acp` 0.79 | Claude Agent SDK (bundles its own CLI; `CLAUDE_CODE_EXECUTABLE` pins yours) |
| codex | `@agentclientprotocol/codex-acp` 1.12 | bundled `codex app-server`, or `CODEX_PATH` |
| pi | `@geohar/pi-acp` 0.3.1 (fork of `pi-acp`, more active) | `pi --mode rpc --no-themes [--mcp-config <tmp>]` |

Smoke client: `node acp-smoke.mjs --cwd DIR --prompt "..." [--meta '{}'] [--mode M] [--set id=value] -- <cmd>`. Auto-allows `session/request_permission`, stubs `fs/*`, prints the `session/update` stream.

## claude-agent-acp

- **cwd**: `session/new.cwd` goes straight to the SDK. No CLI flag.
- **Config inherited**: `settingSources: ["user","project","local"]` is hardcoded. User skills, MCP servers, plugins, and `<cwd>/.claude/*` all load. `CLAUDE_CONFIG_DIR` relocates the user dir. Verified: user-level skills appear regardless of cwd.
- **Permission mode**: starts in `permissions.defaultMode` from settings. `_meta.claudeCode.options.permissionMode` is silently ignored. Force bypass with `session/set_mode {modeId:"bypassPermissions"}` after `session/new`, or `<cwd>/.claude/settings.json` `{"permissions":{"defaultMode":"bypassPermissions"}}`. Buzz does not send `set_mode`, so use the settings file.
- **Model**: `ANTHROPIC_MODEL` env wins, then `settings.model`, then `_meta.claudeCode.options.model`. Aliases `fable|opus|sonnet` or full ids.
- **Caps**: `_meta.claudeCode.options.{maxTurns, maxBudgetUsd}` work and surface as `error_max_turns` / `error_max_budget_usd`. Buzz does not send them.
- **Auth**: the CLI's OAuth. If `claude auth status` says `loggedIn: false`, every prompt fails with `OAuth session expired`.

## codex-acp

- **cwd**: `session/new.cwd` becomes the Codex thread cwd.
- **Config inherited**: `~/.codex/config.toml` fully, including every MCP server and `AGENTS.md`.
- **Approval**: `INITIAL_AGENT_MODE=read-only|agent|agent-full-access`. Full access = `approval_policy: never` + `sandbox: dangerFullAccess`.
- **Model**: `CODEX_CONFIG='{"model":"gpt-5.5","model_reasoning_effort":"high"}'` merges into the session config.
- **Caps**: none. Token usage per turn in `session/prompt.usage`.
- **Trap**: Codex 0.155+ runs shell through `codex-code-mode-host`, looked up beside the launched path. Through a symlink with no helper beside it, shell fails closed and the model reports "shell runner unavailable". Use the real binary path.
- **Trap**: "Selected model is at capacity" is an OpenAI-side error. Switch models in `CODEX_CONFIG`.

## pi-acp

- **cwd**: `session/new.cwd` is the spawn cwd.
- **Config inherited**: `~/.pi/agent/settings.json`, `auth.json`, `~/.agents/skills/*`, `~/.pi/agent/extensions/`. Adapter settings in `~/.pi/agent/extensions/pi-acp.json`.
- **Provider/model**: no CLI knob. `defaultProvider` / `defaultModel` in settings, or `session/set_config_option {configId:"model"}` per session.
- **Permissions**: none. pi executes tools locally. Modes are thinking levels.
- **Caps**: none. No usage in the prompt result.
- **Trap**: the adapter passes `--mcp-config` whenever the client sends `mcpServers`. pi only accepts that flag with the `pi-mcp-adapter` extension installed. Without it pi exits and the adapter returns `Internal error: Cannot call write after a stream was destroyed`.
- **Trap**: pinning a model the provider rejects returns `end_turn` with empty text. Check with `pi -p` directly.
