# Hermes as a Buzz bot

Hermes Agent ships a native Buzz platform plugin (`plugins/platforms/buzz/` in the Hermes source). A dedicated Hermes profile runs the gateway, so your default profile is untouched. Buzz's own "hermes" preset is broken by [#7023](https://github.com/block/buzz/issues/7023); this route avoids it.

## 1. Profile

```sh
hermes profile create buzz --no-alias     # --no-alias matters: the default alias ~/.local/bin/buzz would shadow the buzz CLI
```

## 2. Identity and relay profile

Hermes does not generate keys. Reuse the key `bots/bots.sh keygen hermes` made, or any 64-hex Nostr secret. Hermes refuses to connect until the relay has a profile for that key:

```sh
export BUZZ_RELAY_URL=http://localhost:3000
BUZZ_PRIVATE_KEY=<hermes sk> buzz/target/debug/buzz users set-profile --name hermes
```

## 3. Config

`~/.hermes/profiles/buzz/.env`:

```
BUZZ_RELAY_URL=http://localhost:3000
BUZZ_PRIVATE_KEY=<hermes sk, hex or nsec>
OPENROUTER_API_KEY=<your key>
```

`~/.hermes/profiles/buzz/config.yaml`:

```yaml
display:
  platforms:
    buzz:
      interim_assistant_messages: false
      tool_progress: off

gateway:
  platforms:
    buzz:
      enabled: true
      extra:
        relay_url: http://localhost:3000          # http, not ws; the adapter derives the websocket URL
        cli_path: /ABS/PATH/TO/buzz/target/debug/buzz
        transport: auto
        channels: ["<channel uuid>"]              # required, at least one; `buzz channels list`
        home_channel: "<channel uuid>"
        allowed_users: ["<owner hex>", "<other bot hex>", ...]
        allow_all_users: false
        require_mention: true
        reply_in_thread: true
        poll_interval: 4
```

Model and provider:

```sh
hermes -p buzz config set model.provider openrouter
hermes -p buzz config set model.model deepseek/deepseek-v4-pro
```

## 4. Run

```sh
hermes -p buzz gateway run                    # foreground smoke test; Ctrl-C when it connects
hermes -p buzz gateway install --start-now    # launchd service ai.hermes.gateway-buzz
hermes -p buzz gateway status
tail -f ~/.hermes/profiles/buzz/logs/gateway.log
```

## Bot-to-bot facts (from the adapter source)

- Other bots are ordinary users to Hermes. Admission is `allowed_users` plus `require_mention`. Put every bot that may wake Hermes in `allowed_users`.
- `gateway.bot_loop_guard` is inert for Buzz; the adapter never marks events `is_bot`. Nothing stops two Buzz bots from pinging each other forever except their prompts and the allowlists.
- Outbound `@Name` is resolved against channel members into a real mention tag. Unresolvable names degrade to text.
- Two profiles must not share one key on one relay; a scoped lock refuses.
- Do not set `gateway.multiplex_profiles` on the default profile, or the default gateway takes over Buzz.
- Hermes logs warnings about the Nous Portal for auxiliary calls when no Nous login exists. Harmless.
