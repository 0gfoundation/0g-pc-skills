# 0G PC Skills

Agent Skills that configure **Claude Code** and **Codex** to run on [0G Private Computer](https://pc.0g.ai) (`router-api.0g.ai`) — TEE-backed inference with OpenAI/Anthropic-compatible APIs.

Both skills follow the open [Agent Skills](https://agentskills.io) format (`SKILL.md`), so one repository serves both clients; only the install entry point differs. Every config the skills produce was verified end-to-end (real sessions, real tool calls) on 2026-08-26 with Claude Code 2.1.246, Codex CLI 0.145.0, and LiteLLM 1.98.0.

| Skill | For | What it does |
|---|---|---|
| [`0g-pc-model-config-claude`](skills/0g-pc-model-config-claude/SKILL.md) | Claude Code | Direct connection (glm-5.2 + 0GM permission gate) or LiteLLM bridge for openai-only models (glm-5.3 / kimi-k3 / qwen), with the permission-gate model configured correctly |
| [`0g-pc-model-config-codex`](skills/0g-pc-model-config-codex/SKILL.md) | Codex | LiteLLM bridge (mandatory — Codex 0.145+ speaks only the Responses API, which the 0G Router does not serve) + provider/profile config |

## What these skills will and won't touch

Read this before installing. The two skills make different promises, because the two clients differ.

**Claude Code** — your global `~/.claude/settings.json` (hooks, plugins, status line, your `/model` choice) is **read but never written**, whichever scope you pick. By default the config goes into `.claude/settings.local.json` in the project you run it from; undoing it is deleting that one file, and the skill adds a `.gitignore` rule first so the key never reaches a commit. If you'd rather have 0G apply everywhere, you can ask for that — it writes a standalone `~/.0g/0g-settings.json` you load with `claude --settings`, which still leaves your global settings alone. The skill states all of this before it asks you anything.

**Codex** — Codex has no per-project configuration, so this one cannot be confined to a folder; be aware of that going in. What it does guarantee: your `~/.codex/config.toml` is **read, never written**. Everything it adds is one new file (`~/.codex/zg-<model>.config.toml`) plus a bridge directory (`~/.0g-litellm/`), and it only takes effect when you launch with `--profile zg-<model>` — existing Codex sessions are unaffected. Deleting those undoes everything.

Neither skill writes your API key anywhere you did not choose, and neither asks you to paste it into the chat.

## Install — Claude Code

Paste this in a terminal, then open a new one:

```bash
mkdir -p ~/.claude/skills/0g-pc-model-config-claude && curl -fsSL \
  https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/skills/0g-pc-model-config-claude/SKILL.md \
  -o ~/.claude/skills/0g-pc-model-config-claude/SKILL.md
```

A skill is a single `SKILL.md`, so that is the whole install — no repository left on your disk. In any session say **“set up 0G PC” / “接入 0G PC”**, or invoke it explicitly with `/0g-pc-model-config-claude`.

**Just one project?** Put the same file in that project's `.claude/skills/0g-pc-model-config-claude/` instead of `~/.claude/skills/` — it then travels with the repo and is available only there.

**Update:** re-run the curl. **Uninstall:** `rm -rf ~/.claude/skills/0g-pc-model-config-claude`.

## Install — Codex

Codex discovers skills in `~/.codex/skills/` (or `$CODEX_HOME/skills` if you set it). Paste this, then open a new terminal:

```bash
mkdir -p ~/.codex/skills/0g-pc-model-config-codex && curl -fsSL \
  https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/skills/0g-pc-model-config-codex/SKILL.md \
  -o ~/.codex/skills/0g-pc-model-config-codex/SKILL.md
```

Then in Codex say **“set up 0G PC in Codex” / “在 Codex 接入 0G PC”**. Codex has no per-project skills — `~/.codex/skills/` is the only location.

**Update:** re-run the curl. **Uninstall:** `rm -rf ~/.codex/skills/0g-pc-model-config-codex`.

## After it's configured

### Claude Code

**Restart first.** Config is read at launch, so nothing changes in the session that ran the skill. Close it, open a new terminal in the same project, run `claude`, and check `/status` — the Base URL should read `https://router-api.0g.ai`. The startup line `[claude-code:unrecognized_model]` is expected and harmless: Claude Code simply doesn't know 0G's model names.

**What got written** — `.claude/settings.local.json` in the project:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://router-api.0g.ai",
    "ANTHROPIC_AUTH_TOKEN": "sk-…",          // injected from $ZG_API_KEY, never typed in chat
    "ANTHROPIC_API_KEY": "",                 // blanked so the token above is the one used
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

Every tier points at a 0G model, so whichever one Claude Code reaches for, the request stays on 0G.

**Switching models in a session.** `/model` moves between the tiers above — Opus and Fable land on `glm-5.2`, Sonnet and Haiku on `0gm-1.0-35b-a3b`. No restart needed.

> ⚠️ **Do not pick a "(1M context)" variant.** Claude Code derives the auto-mode safety classifier from the Sonnet tier and copies your main model's `[1m]` tag onto the result, asking the router for `0gm-1.0-35b-a3b[1m]` — an ID it does not serve. The classifier becomes unreachable and auto mode fails closed on every Bash, git and network call, while chat keeps working, so it reads like the model is fine and the tools are broken.
>
> Your `/model` choice is remembered in `~/.claude/settings.json`, so this survives restarts and follows you into other projects. The skill will then refuse to write a new config until you clear it — that refusal is the guard working, not a bug. Fix it with `/model` and a plain (non-1M) entry.

**Switching the main model** — say "switch to glm-5.3" and run the skill again. It is not a one-line edit: `glm-5.2` speaks the Anthropic API directly, while `glm-5.3`, `kimi-k3` and `qwen3.8-max` are OpenAI-only and need a local LiteLLM bridge the skill sets up for you. Restart afterwards.

**Going back to Anthropic** — `rm .claude/settings.local.json` and restart. Nothing else to undo.

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

## What you need

- A 0G PC inference API key (`sk-…`) from [pc.0g.ai](https://pc.0g.ai) → Dashboard → API Keys. Export it before you start — ` export ZG_API_KEY='sk-…'` (the leading space keeps it out of your shell history), or put a `ZG_API_KEY=` line in the project's `.env`. The skills read it from there and inject it directly, so the key never passes through the conversation. If neither is present they will ask you to set one and write nothing until you do — they never leave a placeholder behind for you to fill in later.
- For the LiteLLM paths: [uv](https://docs.astral.sh/uv/) or `pip`.

Live model list (the skills check this before configuring anything):

```bash
curl -s https://router-api.0g.ai/v1/models
```
