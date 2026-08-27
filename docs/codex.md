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

## Switching models

Each run of the skill writes another `~/.codex/zg-<name>.config.toml`. They all stay; `--profile` picks between them.
