---
name: 0g-pc-model-config-claude
argument-hint: "[model name, or 'revert']"
description: Configure Claude Code to use 0G Private Computer (pc.0g.ai, router-api.0g.ai) as its model backend, with tested model combinations (glm-5.3 direct; glm-5.2 / kimi-k3 / qwen via LiteLLM) and a correctly configured permission-gate model. Use when the user wants to set up, connect, switch, or fix 0G PC / 0G Private Computer / 0G router models in Claude Code. Triggers include "set up 0G PC", "connect Claude Code to 0G", "use 0G models in Claude Code", "接入 0G PC", "配置 0G", "把 Claude Code 接到 0G", "用 0G 的模型", "0G 配置不工作".
---

# 0G PC Setup for Claude Code

Point Claude Code at 0G Private Computer's inference API. The config is a file in this repo — your job is to put it in the right place, not to compose it.

## Hard rules

1. **Never write `~/.claude/settings.json`.** It holds the user's hooks, plugins, status line and `/model` choice. Read it freely; the config you install goes to `<project>/.claude/settings.json` — the project settings file, which is meant to be committed and shared — and removing that one file undoes everything. If the project also has a `.claude/settings.local.json`, it takes precedence; check there when a setting appears not to apply.
2. **The key never enters the conversation, and never enters a file.** It lives in the user's shell as `ANTHROPIC_AUTH_TOKEN`. Do not `cat` it, echo it, put it on a command line, or write it anywhere. The config file deliberately has no credential field — that is what makes it safe to commit.
3. **Do not touch the permission gate.** `modelOverrides["claude-sonnet-5"]` must stay on `0gm-1.0-35b-a3b`. In auto mode the safety classifier resolves through the **Sonnet** tier, not Haiku; put a reasoning model there and every Bash, git and network call times out with "temporarily unavailable" while chat keeps working. `ANTHROPIC_DEFAULT_HAIKU_MODEL` is not the gate but is kept fast for background work.
4. **Nothing takes effect until the next launch.** Finish by telling the user to restart — never claim the current session is now on 0G.

## Pick the mode before doing anything

Three jobs share this skill. Decide from the ground, not from the wording:

| Situation | Mode |
|---|---|
| The user asks to undo, revert, turn it off, or go back to the normal API | **C — Revert** |
| `<project>/.claude/settings.json` does not exist | **A — Install** |
| It exists | **B — Switch the main model** |

Only C depends on what the user said; A and B are decided by the file. If an argument was passed (`/0g-pc-model-config-claude glm-5.3`), treat it as the target model for B, or as `revert` for C.

## Mode A — Install

### 1 — Show the live model list

```bash
curl -s https://router-api.0g.ai/v1/models | python3 -c "import json,sys; [print(m['id'], '+'.join(m.get('supported_formats',[])), m.get('context_length')) for m in json.load(sys.stdin)['data']]"
```

Formats including `anthropic` work directly; `openai`-only ones (`glm-5.2`, `kimi-k3`, `qwen3.8-max`, `minimax-m3`, `gpt-5.6-*`, `qwen3.8-flash`) need the bridge — see the last section. If the endpoint is unreachable, stop and report rather than proceed on a stale list.

### 2 — Confirm the key is exported

```bash
[ -n "$ANTHROPIC_AUTH_TOKEN" ] && echo "present (${#ANTHROPIC_AUTH_TOKEN} chars)" || echo "absent"
```

Presence and length only, never the value. If absent, stop and ask the user to run ` export ANTHROPIC_AUTH_TOKEN='sk-…'` (leading space keeps it out of shell history). Do not look in `.env` or anywhere else in the project — a key in a repo file is one `git add -A` from being committed.

### 3 — Check for a `[1m]` conflict

```bash
python3 -c "
import json,pathlib
for lbl,f in (('project local','.claude/settings.local.json'),('project','.claude/settings.json'),('user','~/.claude/settings.json')):
    try: m=json.loads(pathlib.Path(f).expanduser().read_text()).get('model')
    except Exception: continue
    if isinstance(m,str) and m.strip(): print('effective model:',m,'(from',lbl+')'); break
else: print('no model pinned - fine')"
```

If the effective model ends in `[1m]`, **stop**. Claude Code copies that tag onto the classifier it derives from the Sonnet tier, asking the router for `0gm-1.0-35b-a3b[1m]` — an ID it does not serve. Auto mode then fails closed on every non-read-only tool while chat still answers, reading as "model fine, tools broken". Have the user pick a non-1M entry with `/model`, or set `"model": "glm-5.2"` in the project config.

### 4 — Install the config

```bash
mkdir -p .claude && curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/claude/settings.json -o .claude/settings.json
```

It arrives on `glm-5.3` — text only; it does not accept images, and `fallbackModel` does not change that (it fires on overload, not on an unsupported request). For another anthropic-format model, change `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_FABLE_MODEL` and `ANTHROPIC_DEFAULT_OPUS_MODEL` together; if its context is under 983616 (`glm-5` 202752, `0gm-1.0-35b-a3b` 262144) lower `CLAUDE_CODE_MAX_CONTEXT_TOKENS` too, or long sessions fail hours later. The file holds no credential — tell the user it is safe to commit and share.

### 5 — Hand off

1. Restart Claude Code (close all windows, new terminal, `claude`). The key must be exported in that terminal.
2. `/status` — Base URL should read `https://router-api.0g.ai`. `[claude-code:unrecognized_model]` is expected and harmless.
3. Ask the new session to run `echo ok > probe.txt && cat probe.txt`. Under the shipped `acceptEdits` it prompts once and succeeds; if the user switched to `auto`, it should run with no prompt and no "temporarily unavailable".

Done. To change the model later, run this skill again — it will land in Mode B.

## Mode B — Switch the main model

The config already exists. Change the model in place; leave everything else alone.

### 1 — Offer only what can actually be reached

```bash
curl -s https://router-api.0g.ai/v1/models | python3 -c "
import json,sys
for m in sorted(json.load(sys.stdin)['data'], key=lambda x:-(x.get('context_length') or 0)):
    if 'anthropic' not in m.get('supported_formats',[]): continue
    a=m.get('architecture') or {}
    img='image' in (a.get('input_modalities') or [])
    print(f\"{m['id']:22} ctx={m.get('context_length'):>8}  tee={str(m.get('tee_type')):5}  {'text+image' if img else 'text only'}\")"
```

Show this list and let the user choose. **Never offer a model missing from it** — the config is a direct connection, so an `openai`-only model cannot be reached at all. If the user names one, say so and point at the bridge section rather than writing a config that will fail.

### 2 — Rewrite the four fields together

```bash
python3 - <<'PY'
import json, pathlib, sys, urllib.request

TARGET = "glm-5.3"          # replace with the user's choice

with urllib.request.urlopen("https://router-api.0g.ai/v1/models", timeout=15) as r:
    live = {m["id"]: m for m in json.load(r)["data"]}
m = live.get(TARGET)
if m is None:
    sys.exit(f"{TARGET} is not on the router right now — check the list again")
if "anthropic" not in m.get("supported_formats", []):
    sys.exit(f"{TARGET} speaks {'+'.join(m.get('supported_formats', []))} only; "
             "a direct config cannot reach it. It needs the LiteLLM bridge.")

p = pathlib.Path(".claude/settings.json")
cfg = json.loads(p.read_text())          # fails loudly rather than clobbering
env = cfg["env"]
for k in ("ANTHROPIC_MODEL", "ANTHROPIC_DEFAULT_FABLE_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL"):
    env[k] = TARGET
ceiling = m["context_length"] * 15 // 16
env["CLAUDE_CODE_MAX_CONTEXT_TOKENS"] = str(ceiling)

text = json.dumps(cfg, indent=2) + "\n"
json.loads(text)                          # validate before touching disk
p.write_text(text)
print(f"{TARGET}  context {m['context_length']}  ceiling {ceiling}")
PY
```

The ceiling moves with the model on purpose. Leave it at a larger model's value and nothing fails until the session grows long — an error hours later, with no visible link to the switch that caused it.

**Do not touch** `modelOverrides`, `ANTHROPIC_DEFAULT_HAIKU_MODEL` or `fallbackModel`. The first is the permission gate (hard rule 3); the other two are deliberately pinned to the fast model.

### 3 — Hand off

Restart, then `/status` to confirm the Model line. The running session keeps the old model — `/model` switches tiers within the session, but it cannot reach a 0G model name (the client rejects it before any request goes out), so a restart is the only way.

## Mode C — Revert to the native Anthropic API

Two steps, and the second is the one that gets missed:

```bash
rm .claude/settings.json
unset ANTHROPIC_AUTH_TOKEN
```

**Deleting the file is not enough.** The key stays in the shell, and Claude Code will keep using it — against `api.anthropic.com`, where it is not valid. The symptom is an authentication failure that looks like a broken account rather than a leftover variable:

```
⚠ another auth source is set and takes precedence over your claude.ai login
```

Shell variables are per-terminal, not per-directory, so this also breaks unrelated projects opened from the same terminal. A fresh terminal works just as well as `unset`.

Then restart. Remove nothing else from `.claude/` — the user may keep their own files there.

## OpenAI-only models (LiteLLM bridge)

`glm-5.2` / `kimi-k3` / `qwen3.8-max` / `minimax-m3` / `qwen3.8-flash` cannot reach Claude Code directly. Install the bridge files, start the proxy in its own terminal, then change two things in the config: `ANTHROPIC_BASE_URL` to `http://127.0.0.1:4000` and the three model fields to the chosen model.

```bash
mkdir -p ~/.0g-litellm
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/codex/litellm-config.yaml -o ~/.0g-litellm/litellm-config.yaml
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/codex/zg_patch.py -o ~/.0g-litellm/zg_patch.py
cd ~/.0g-litellm && export ZG_API_KEY="$ANTHROPIC_AUTH_TOKEN" && uvx --from 'litellm[proxy]==1.98.0' litellm --config litellm-config.yaml --port 4000
```

The bridge files are shared with the Codex setup, hence their path. The proxy does not authenticate, so in this mode `ANTHROPIC_AUTH_TOKEN` may be any string — the real key is what `ZG_API_KEY` carries into the proxy.

## Troubleshooting map

| Symptom | Cause → fix |
|---|---|
| Auto mode: "xxx is temporarily unavailable, cannot determine the safety of …" | Read the model name in the message — it names the classifier model, and the fix follows from it. Gate model wrong: point `modelOverrides["claude-sonnet-5"]` at `0gm-1.0-35b-a3b` (hard rule 4 — Sonnet tier, not Haiku). |
| That message names a model with a `[1m]` suffix (e.g. `0gm-1.0-35b-a3b[1m]`) | The session model carries `[1m]` and Claude Code copied the tag onto the derived classifier model; the router does not serve that ID. Drop the tag: `/model` without the (1M context) variant, or `"model": "glm-5.2"` in `.claude/settings.json`. The Step 5A writer refuses to run while this is in place. |
| That message names your main model (e.g. `glm-5.3`) | The Sonnet-tier resolution returned nothing and the classifier fell back to the main model — either `ANTHROPIC_DEFAULT_SONNET_MODEL` is set to an unrecognised ID (remove it), or a fable/mythos main model sent the classifier to the Opus tier, which this config points at glm-5.2. |
| 401 | Key wrong or expired. Path A: re-run Step 4's probe, re-export a fresh key, re-run the Step 5A writer, and re-run the `HTTP 200` check before handing off. Path B: `ZG_API_KEY` not exported in the proxy terminal. A 401 also takes down the auto-mode classifier, so fix this before diagnosing any gate symptom. |
| Model not found | Typo vs the Step 1 list, or (Path B) model missing from `model_list`. |
| LiteLLM 404 "page not found" | Model prefix written as `openai/`; must be `hosted_vllm/`. |
| Config edits ignored | Old session still running; or `claude` was launched from a directory other than the project holding `.claude/settings.json` (project config is scoped to that directory by design — either run the skill in the other project, or switch to the every-project scope from Step 2 question 3); or leftover `ANTHROPIC_*` in the global `env` or the shell — re-run Step 3. |
