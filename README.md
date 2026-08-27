# 0G PC Skills

Ready-made configuration that points **Claude Code** and **Codex** at [0G Private Computer](https://pc.0g.ai) (`router-api.0g.ai`) — TEE-backed inference with OpenAI/Anthropic-compatible APIs.

Setup is: export your key, download a config file, restart. The config files live in [`configs/`](configs/) — they are ordinary files you can read, diff, and edit. Two Agent Skills ([`skills/`](skills/)) can walk you through the same steps in a session if you prefer that to reading this page.

Verified end-to-end on 2026-08-27 with Claude Code 2.1.246, Codex CLI 0.145.0 / 0.149.1, and LiteLLM 1.98.0.

## Your key never goes in a file

The config files carry **no credentials**. Your key lives in a shell environment variable and nothing else, which is why these files are safe to read, safe to diff, and safe to commit — a team can share one config in the repo, and each person brings their own key.

Two variable names, because two different programs read them:

| Variable | Read by | Needed for |
|---|---|---|
| `ANTHROPIC_AUTH_TOKEN` | Claude Code | Claude Code setup |
| `ZG_API_KEY` | the LiteLLM bridge | Codex setup |

Same key, so export both at once:

```bash
 export ZG_API_KEY='sk-…'
 export ANTHROPIC_AUTH_TOKEN="$ZG_API_KEY"
```

The leading space keeps them out of your shell history. They last as long as the terminal — a new terminal needs them again.

## What is and isn't touched

**Claude Code** — your global `~/.claude/settings.json` (hooks, plugins, status line, your `/model` choice) is never written. The config goes to `.claude/settings.json` in one project; deleting that file undoes everything.

**Codex** — Codex has no per-project configuration, so this cannot be confined to a folder. Your `~/.codex/config.toml` is never written; what gets added is one profile file plus a bridge directory, and it only applies when you launch with `--profile`. Existing Codex sessions are unaffected.

## Set up — Claude Code

```mermaid
flowchart TD
    K["export ANTHROPIC_AUTH_TOKEN<br/>this terminal only"]
    K --> D["curl configs/claude/settings.json<br/>into .claude/settings.json"]
    S["skill: say 'set up 0G PC'"] -.->|"walks you through<br/>the same steps"| D
    D --> M{"which model?"}
    M -->|"glm-5.2 — shipped default"| R["restart claude<br/>same terminal, key lives there"]
    M -->|"another anthropic-format model"| E["edit 3 model fields<br/>+ lower MAX_CONTEXT_TOKENS<br/>if its window is smaller"]
    M -->|"openai-only: glm-5.3, kimi-k3, qwen…"| B["start LiteLLM bridge<br/>+ point BASE_URL at 127.0.0.1:4000"]
    E --> R
    B --> R
    R --> V["/status → Base URL is router-api.0g.ai"]
    V --> T{"does a Bash call work?"}
    T -->|"yes"| OK["done — commit .claude/settings.json<br/>so the team shares it"]
    T -->|"no"| C["run check-0g.sh<br/>then the troubleshooting table"]
```

With the variables exported above, from the project you want on 0G:

```bash
mkdir -p .claude && curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/claude/settings.json -o .claude/settings.json
```

Restart Claude Code — config is read at launch — then check `/status`: the Base URL should read `https://router-api.0g.ai`.

That is the whole setup. The file arrives on `glm-5.2`; to use a different model edit one line before restarting (see [Switching the main model](#after-its-configured) below for which models work and which need the bridge).

**Uninstall:** `rm .claude/settings.json` and restart.

## Set up — Codex

```mermaid
flowchart TD
    K["export ZG_API_KEY"]
    K --> D["curl 3 files:<br/>litellm-config.yaml, zg_patch.py<br/>zg-glm53.config.toml"]
    S["skill: say 'set up 0G PC in Codex'"] -.->|"walks you through<br/>the same steps"| D
    D --> P["start the bridge in its own terminal<br/>leave it running"]
    P --> H["health check: curl 127.0.0.1:4000"]
    H --> L["codex --profile zg-glm53<br/>required every launch"]
    L --> M{"banner says model: ?"}
    M -->|"glm-5.3 — your model"| OK["done"]
    M -->|"gpt-* — profile not loaded"| X["STOP: the request is going to OpenAI.<br/>Codex reports nothing when a profile is missing"]
    M -->|"stream disconnects, reconnect loop"| Z["zg_patch.py not loaded —<br/>start the proxy from ~/.0g-litellm"]
```

Codex cannot reach the 0G router directly — it speaks only the Responses API, which the router does not serve — so a local LiteLLM proxy translates. It listens on `http://127.0.0.1:4000`, which is the address the profile points at; if that port is already taken, change it in both places. Three files, then the proxy.

```bash
mkdir -p ~/.0g-litellm && curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/codex/litellm-config.yaml -o ~/.0g-litellm/litellm-config.yaml
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/codex/zg_patch.py -o ~/.0g-litellm/zg_patch.py
mkdir -p "${CODEX_HOME:-$HOME/.codex}" && curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/codex/zg-glm53.config.toml -o "${CODEX_HOME:-$HOME/.codex}/zg-glm53.config.toml"
```

Start the proxy in **its own terminal** and leave it running (first launch takes a minute or two to install dependencies):

```bash
cd ~/.0g-litellm && uvx --from 'litellm[proxy]==1.98.0' litellm --config litellm-config.yaml --port 4000
```

Then, in any terminal:

```bash
 export ZG_LITELLM_KEY='sk-anything'    # the local proxy does not authenticate
codex --profile zg-glm53
```

`--profile` is required every time; without it you get your ordinary Codex, which is also how you switch back.

**Uninstall:** `rm "${CODEX_HOME:-$HOME/.codex}"/zg-glm53.config.toml && rm -rf ~/.0g-litellm`.

## Using the skills instead

If you would rather be walked through it, install either skill and ask for it by name. They perform the same steps and explain what each one does.

```bash
mkdir -p ~/.claude/skills/0g-pc-model-config-claude && curl -fsSL \
  https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/skills/0g-pc-model-config-claude/SKILL.md \
  -o ~/.claude/skills/0g-pc-model-config-claude/SKILL.md

mkdir -p ~/.codex/skills/0g-pc-model-config-codex && curl -fsSL \
  https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/skills/0g-pc-model-config-codex/SKILL.md \
  -o ~/.codex/skills/0g-pc-model-config-codex/SKILL.md
```

Then say **“set up 0G PC” / “接入 0G PC”** (Claude Code) or **“set up 0G PC in Codex” / “在 Codex 接入 0G PC”**.

**Update:** re-run the curl. **Uninstall:** `rm -rf` the skill directory.

## After it's configured

### Claude Code

**Restart first.** Config is read at launch, so nothing changes in a session that was already open. Close it, open a new terminal in the same project, run `claude`, and check `/status` — the Base URL should read `https://router-api.0g.ai`. The startup line `[claude-code:unrecognized_model]` is expected and harmless: Claude Code simply doesn't know 0G's model names.

**What the file contains** — `.claude/settings.json` in the project:

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

**Switching models in a session.** `/model` moves between the tiers above — Opus and Fable land on `glm-5.2`, Sonnet and Haiku on `0gm-1.0-35b-a3b`. No restart needed.

> ⚠️ **Do not pick a "(1M context)" variant.** Claude Code derives the auto-mode safety classifier from the Sonnet tier and copies your main model's `[1m]` tag onto the result, asking the router for `0gm-1.0-35b-a3b[1m]` — an ID it does not serve. The classifier becomes unreachable and auto mode fails closed on every Bash, git and network call, while chat keeps working, so it reads like the model is fine and the tools are broken.
>
> Your `/model` choice is remembered in `~/.claude/settings.json`, so this survives restarts and follows you into other projects. The skill will then refuse to write a new config until you clear it — that refusal is the guard working, not a bug. Fix it with `/model` and a plain (non-1M) entry.

**Switching the main model** — edit `.claude/settings.json` and restart. Three fields move together:

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

Or run [`check-0g.sh`](check-0g.sh) after any change — it reads the effective model, the gate and the ceiling, and says nothing when everything is fine:

```bash
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/check-0g.sh | sh
```

> The last two rows are the trap. `CLAUDE_CODE_MAX_CONTEXT_TOKENS` ships as `983616`, which is far above what those models accept — leave it and the session fails on context length only once it grows long, by which point the model switch is the last thing you'd suspect. Lower it in the same edit.

Everything else on the router — `glm-5.3`, `kimi-k3`, `qwen3.8-max`, `minimax-m3`, `gpt-5.6-*`, `deepseek-v4-pro` — is OpenAI-only and cannot reach Claude Code directly. Those need the LiteLLM bridge, so say "switch to glm-5.3" and run the skill again instead of editing.

Check the current list yourself with `curl -s https://router-api.0g.ai/v1/models`; anything whose `supported_formats` contains `anthropic` belongs in the table above.

And whichever model you pick, don't append `[1m]` to its name — same failure as the `/model` warning above.

**Going back to Anthropic** — `rm .claude/settings.json` and restart. Nothing else to undo.

### Codex

**No restart, but every launch needs the flag.** The config only applies with `--profile`:

```bash
codex --profile zg-glm53
codex exec --profile zg-glm53 "…"
```

Without it you get your ordinary Codex. That is also how you switch back — just drop the flag.

**Keep the bridge running.** Codex speaks only the Responses API, which the 0G router does not serve, so a local LiteLLM proxy translates. It lives in its own terminal and must stay up for the whole session:

```bash
cd ~/.0g-litellm && export ZG_API_KEY='sk-…'
uvx --from 'litellm[proxy]==1.98.0' litellm --config litellm-config.yaml --port 4000
```

**Check the `model:` line in the startup banner, every time.**

| `model:` shows | Meaning |
|---|---|
| your configured model, e.g. `glm-5.3` | The profile loaded; requests go through the bridge. |
| `gpt-*` | **Stop.** The profile was not found and Codex fell back to its own default — your request is going to `api.openai.com`. Codex reports nothing when a profile is missing, so this line is the only warning you get. |

**Switching models** — run the skill again for the model you want. It writes another `~/.codex/zg-<name>.config.toml`; both stay, and you pick with `--profile`.

## Verifying a change

If you are changing this repo rather than using it, [`verification/`](verification/) holds the two manual protocols — one per client — that check a config end to end on a real machine: what to run, what each step should print, and how to read the failure modes. They exist because the interesting failures here (a poisoned classifier, a silently redirected Codex request) look like something other than what they are.

## What you need

- A 0G PC inference API key (`sk-…`) from [pc.0g.ai](https://pc.0g.ai) → Dashboard → API Keys. Export it as shown above; do not put it in a file inside a repository, where one `git add -A` can commit it.
- For Codex: [uv](https://docs.astral.sh/uv/) or `pip`, for the LiteLLM bridge.

Live model list — worth checking before picking a model, since the table below ages:

```bash
curl -s https://router-api.0g.ai/v1/models
```
