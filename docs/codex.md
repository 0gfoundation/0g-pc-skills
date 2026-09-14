# Codex on 0G — reference

Everything worth knowing once the setup works. Setting it up in the first place is [two terminals in the README](../README.md#set-up--codex).

## Every launch needs the flag

That includes `codex exec`. No restart, though — there is no session to restart.

```bash
codex --profile zg-glm53
codex exec --profile zg-glm53 "…"
```

## Keep the bridge running

Codex speaks only the Responses API, which the 0G router does not serve, so a local LiteLLM bridge translates. It lives in its own terminal and must stay up for the whole session:

```bash
cd ~/.0g-litellm && export ZG_API_KEY='sk-…'
uvx --from 'litellm[proxy]==1.98.0' litellm --config litellm-config.yaml --port 4000
```

## Reading the `model:` line

Check it in the startup banner, every launch.

| `model:` shows | Meaning |
|---|---|
| your configured model, e.g. `glm-5.3` | The profile loaded; requests go through the bridge. |
| `gpt-*` | **Stop.** The profile was not found and Codex fell back to its own default — your request is going to `api.openai.com`. Codex reports nothing when a profile is missing, so this line is the only warning you get. |

## The noise above the banner is not a fault

Three things print on a normal launch and none of them is broken. They are here so you can match
them and move on rather than chase them.

```
ERROR codex_models_manager::manager: failed to refresh available models:
  failed to decode models response: missing field `models`;
  body: {"data":[{"id":"glm-5.3",...}],"object":"list"}
```

Codex asks the provider for its model list and expects a `models` field; LiteLLM answers in
OpenAI's shape, with `data`. It is logged at ERROR level, it appears twice, and it sits above
everything else on screen — but nothing depends on it. Your `--profile` already names the model.

```
warning: Model metadata for `glm-5.3` not found. Defaulting to fallback metadata
```

Codex does not know 0G's model names. The Claude Code setup prints
`[claude-code:unrecognized_model]` for the same reason.

```
Reading additional input from stdin...
```

Normal for `codex exec ... < /dev/null`.

What is *not* noise is the `model:` line above — that one you read every time.

## What a task costs

A one-file task measured 168,081 tokens through this path. `glm-5.3` is a reasoning model and
spends most of a budget before it writes anything, which also means **a small `max_tokens` comes
back with empty content rather than a short answer** — 105 reasoning tokens went into answering
"reply with exactly: BRIDGE OK". If you are testing the bridge by hand, give it room, or you will
read an empty string as a broken bridge.

## Switching models

Each run of the skill writes another `~/.codex/zg-<name>.config.toml`. They all stay; `--profile` picks between them.

## `Insufficient balance` (402)

An empty 0G balance surfaces as a 402 from the bridge, not as anything that mentions billing. The bridge terminal is where it shows up most clearly — it is the process talking to the router. Top up at https://pc.0g.ai/dashboard/overview

Worth separating from the `model:` line check above: a `gpt-*` banner means the profile never loaded, while a 402 means the profile loaded fine and the account has no credit. Different causes, and the fixes have nothing to do with each other.
