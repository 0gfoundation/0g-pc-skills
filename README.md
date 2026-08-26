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

Via plugin marketplace:

```
/plugin marketplace add 0gfoundation/0g-pc-skills
/plugin install 0g-pc-skills@0g-pc-skills
```

Or manually (user-level, all projects):

```bash
git clone https://github.com/0gfoundation/0g-pc-skills
cp -r 0g-pc-skills/skills/0g-pc-model-config-claude ~/.claude/skills/
```

Then in any Claude Code session say **“set up 0G PC” / “接入 0G PC”** — or invoke explicitly with `/0g-pc-model-config-claude` if it doesn't trigger.

## Install — Codex

Codex discovers skills in `~/.codex/skills/`:

```bash
git clone https://github.com/0gfoundation/0g-pc-skills
cp -r 0g-pc-skills/skills/0g-pc-model-config-codex ~/.codex/skills/
```

Then in Codex say **“set up 0G PC in Codex” / “在 Codex 接入 0G PC”**.

## What you need

- A 0G PC inference API key (`sk-…`) from [pc.0g.ai](https://pc.0g.ai) → Dashboard → API Keys. Export it before you start — ` export ZG_API_KEY='sk-…'` (the leading space keeps it out of your shell history), or put a `ZG_API_KEY=` line in the project's `.env`. The skills read it from there and inject it directly, so the key never passes through the conversation. If neither is present they will ask you to set one and write nothing until you do — they never leave a placeholder behind for you to fill in later.
- For the LiteLLM paths: [uv](https://docs.astral.sh/uv/) or `pip`.

Live model list (the skills check this before configuring anything):

```bash
curl -s https://router-api.0g.ai/v1/models
```
