# Claude Code on 0G — reference

Everything worth knowing once the setup works. Setting it up in the first place is [three steps in the README](../README.md#set-up--claude-code).

Config is read at launch, so nothing changes in a session that was already open. Close it, open a new terminal in the same project, run `claude`, and check `/status` — the Base URL should read `https://router-api.0g.ai`.

## What the config file contains

`.claude/settings.json`, in the project:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://router-api.0g.ai",
    "ANTHROPIC_API_KEY": "",                 // blanked so your exported token is the one used
    "ANTHROPIC_MODEL": "glm-5.2",            // the main model
    "ANTHROPIC_DEFAULT_FABLE_MODEL": "glm-5.2",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5.2",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "0gm-1.0-35b-a3b",
    "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "983616"
  },
  "modelOverrides": { "claude-sonnet-5": "0gm-1.0-35b-a3b" },
  "permissions": { "defaultMode": "acceptEdits" }
}
```

Every tier points at a 0G model, so whichever one Claude Code reaches for, the request stays on 0G. No credential appears anywhere in the file — that comes from `ANTHROPIC_AUTH_TOKEN` in your shell.

This is the project settings file, meant to be committed. If you also keep a personal `.claude/settings.local.json`, that one wins — Claude Code loads `local` after `project` — so a setting that seems not to apply is worth checking there first.

## Switching the main model

Edit `.claude/settings.json` and restart. Three fields move together:

```json
"ANTHROPIC_MODEL": "deepseek-v4-flash",
"ANTHROPIC_DEFAULT_FABLE_MODEL": "deepseek-v4-flash",
"ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-flash",
```

Leave `ANTHROPIC_DEFAULT_HAIKU_MODEL` and `modelOverrides.claude-sonnet-5` alone. The second one is the permission gate: point it at a reasoning model and every Bash, git and network call starts timing out under auto mode.

These eight models speak the Anthropic API and can be swapped in by editing alone:

| Model | Context | `CLAUDE_CODE_MAX_CONTEXT_TOKENS` |
|---|---|---|
| `glm-5.2` | 1048576 | `983616` (unchanged) |
| `claude-fable-5` | 1000000 | `983616` |
| `claude-opus-5` | 1000000 | `983616` |
| `claude-opus-4-8` | 1000000 | `983616` |
| `claude-sonnet-5` | 1000000 | `983616` |
| `deepseek-v4-flash` | 1000000 | `983616` |
| `0gm-1.0-35b-a3b` | 262144 | **`245760`** |
| `glm-5` | 202752 | **`190080`** |

> The last two rows are the trap. `CLAUDE_CODE_MAX_CONTEXT_TOKENS` ships as `983616`, which is far above what those models accept — leave it and the session fails on context length only once it grows long, by which point the model switch is the last thing you'd suspect. Lower it in the same edit.

Or run [`check-0g.sh`](../check-0g.sh) after any change — it reads the effective model, the gate and the ceiling, and says nothing when everything is fine:

```bash
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/check-0g.sh | sh
```

Check the current list yourself with `curl -s https://router-api.0g.ai/v1/models`; anything whose `supported_formats` contains `anthropic` belongs in the table above. And whichever model you pick, don't append `[1m]` to its name — same failure as below.

## Don't pick a "(1M context)" entry

`/model` moves between the tiers above with no restart. What it must not move to is a "(1M context)" variant. Claude Code derives the auto-mode safety classifier from the Sonnet tier and copies your main model's `[1m]` tag onto the result, asking the router for `0gm-1.0-35b-a3b[1m]` — an ID it does not serve. The classifier becomes unreachable and auto mode fails closed on every Bash, git and network call, while chat keeps working, so it reads like the model is fine and the tools are broken.

Your `/model` choice is remembered in `~/.claude/settings.json`, so this survives restarts and follows you into other projects. The skill will then refuse to write a new config until you clear it — that refusal is the guard working, not a bug. Fix it with `/model` and a plain (non-1M) entry.

## OpenAI-only models need the bridge

`glm-5.3`, `kimi-k3`, `qwen3.8-max`, `minimax-m3`, `gpt-5.6-*` and `deepseek-v4-pro` cannot reach Claude Code directly. They need the same local LiteLLM bridge the Codex setup uses — install the two bridge files and start it in its own terminal:

```bash
mkdir -p ~/.0g-litellm
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/codex/litellm-config.yaml -o ~/.0g-litellm/litellm-config.yaml
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/codex/zg_patch.py -o ~/.0g-litellm/zg_patch.py
cd ~/.0g-litellm && export ZG_API_KEY="$ANTHROPIC_AUTH_TOKEN"
uvx --from 'litellm[proxy]==1.98.0' litellm --config litellm-config.yaml --port 4000
```

Then two changes in `.claude/settings.json`: `ANTHROPIC_BASE_URL` to `http://127.0.0.1:4000`, and the three model fields to the model you want. The bridge does not authenticate, so in this mode `ANTHROPIC_AUTH_TOKEN` can be any string — the real key is the one `ZG_API_KEY` carries into the bridge. Or say "switch to glm-5.3" to the skill and let it do all of it.

## Going back to Anthropic

`rm .claude/settings.json` and restart. Nothing else to undo.
