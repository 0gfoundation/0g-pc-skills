# 0G PC Skills

Agent Skills that configure **Claude Code** and **Codex** to run on [0G Private Computer](https://pc.0g.ai) (`router-api.0g.ai`) — TEE-backed inference with OpenAI/Anthropic-compatible APIs.

Both skills follow the open [Agent Skills](https://agentskills.io) format (`SKILL.md`), so one repository serves both clients; only the install entry point differs. Every config the skills produce was verified end-to-end (real sessions, real tool calls) on 2026-08-26 with Claude Code 2.1.246, Codex CLI 0.145.0, and LiteLLM 1.98.0.

| Skill | For | What it does |
|---|---|---|
| [`0g-pc-model-config-claude`](skills/0g-pc-model-config-claude/SKILL.md) | Claude Code | Direct connection (glm-5.2 + 0GM permission gate) or LiteLLM bridge for openai-only models (glm-5.3 / kimi-k3 / qwen), with the permission-gate model configured correctly |
| [`0g-pc-model-config-codex`](skills/0g-pc-model-config-codex/SKILL.md) | Codex | LiteLLM bridge (mandatory — Codex 0.145+ speaks only the Responses API, which the 0G Router does not serve) + provider/profile config |

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

- A 0G PC inference API key (`sk-…`) from [pc.0g.ai](https://pc.0g.ai) → Dashboard → API Keys. The skills never ask you to paste the key into the chat — you insert it yourself in the final step.
- For the LiteLLM paths: [uv](https://docs.astral.sh/uv/) or `pip`.

Live model list (the skills check this before configuring anything):

```bash
curl -s https://router-api.0g.ai/v1/models
```
