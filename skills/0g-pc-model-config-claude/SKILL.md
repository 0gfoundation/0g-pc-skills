---
name: 0g-pc-model-config-claude
argument-hint: "[model name, or 'revert']"
description: Configure Claude Code to use 0G Private Computer (pc.0g.ai, router-api.0g.ai) as its model backend, with tested model combinations and a correctly configured permission-gate model. Use when the user wants to set up, connect, switch, or fix 0G PC / 0G Private Computer / 0G router models in Claude Code. Triggers include "set up 0G PC", "connect Claude Code to 0G", "use 0G models in Claude Code", "接入 0G PC", "配置 0G", "把 Claude Code 接到 0G", "用 0G 的模型", "0G 配置不工作".
---

# 0G PC Setup for Claude Code

Point Claude Code at 0G Private Computer's inference API. The config is a file in this repo — your job is to put it in the right place, not to compose it.

## Hard rules

1. **Never write `~/.claude/settings.json`.** It holds the user's hooks, plugins, status line and `/model` choice. Read it freely; everything you install goes inside `<project>/.claude/` — `settings.json` for configuration (committed and shared) and `settings.local.json` for the key (mode 600, git-ignored). Local is loaded after project and wins, so check it when a setting appears not to apply.
2. **The key never enters the conversation.** You do not ask for it, read it, or put it on a command line you run. It does now live in a file — `<project>/.claude/settings.local.json`, which is what makes a fresh terminal work — but the file is written by the **installer, run by the user**, not by you. Hand them the command and let them paste their own key into it. You may check that a credential is present; never print one. `settings.json`, the file that gets committed, still has no credential field.
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

### 1 — Show what can actually be reached

```bash
curl -s https://router-api.0g.ai/v1/models | python3 -c "
import json,sys
rows=[m for m in json.load(sys.stdin)['data'] if 'anthropic' in (m.get('supported_formats') or [])]
if not rows: sys.exit('router returned no anthropic-format model - stop and report')
for m in sorted(rows, key=lambda x:-(x.get('context_length') or 0)):
    v=m.get('verifiability') if m.get('tee_attested') else None
    tee={'TeeML':'TEE, model in enclave','TeeTLS':'TEE, proxied upstream'}.get(v,'NO TEE')
    a=m.get('architecture') or {}
    img='text+image' if 'image' in (a.get('input_modalities') or []) else 'text only'
    print(f\"{m['id']:22} ctx={m.get('context_length'):>8}  {tee:22} {img}\")"
```

The list is filtered live, never from memory: the router's lineup moves, and a model that
spoke `anthropic` last month may not today. Only what this command prints can be reached by a
direct config — everything else on the router speaks `openai` only and is not on offer here.

Read the TEE column out loud to the user; it is why they are on 0G at all, and the three values
are not interchangeable:

| Column | What it means |
|---|---|
| `TEE, model in enclave` | The model itself runs inside the enclave and signs its responses. The strongest guarantee the router offers. |
| `TEE, proxied upstream` | A broker inside an enclave relays to a centralised upstream. The link is protected; the model weights are not in the enclave. |
| `NO TEE` | No attestation. These are reachable and work fine — they simply carry none of the privacy guarantee. |

Do not collapse the first two into one "TEE" label. A user who reads them as equivalent has been
told something false about where their prompt is processed. The default below, `glm-5.3`, is in
the strongest tier — say so rather than leaving them to notice.

If the endpoint is unreachable, stop and report rather than proceed on a stale list.

### 2 — See whether a key is already installed

```bash
python3 -c "
import json,pathlib
try: e=json.loads(pathlib.Path('.claude/settings.local.json').read_text()).get('env',{})
except Exception: e={}
k=e.get('ANTHROPIC_AUTH_TOKEN') or e.get('ANTHROPIC_API_KEY')
print(f'credential present ({len(k)} chars)' if k else 'no credential installed')"
```

Length only, never the value — do not `cat` that file. If one is present the user has run the
installer before; Step 4 will overwrite it in place, which is how you change keys.

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

If the effective model ends in `[1m]`, **stop**. Claude Code copies that tag onto the classifier it derives from the Sonnet tier, asking the router for `0gm-1.0-35b-a3b[1m]` — an ID it does not serve. Auto mode then fails closed on every non-read-only tool while chat still answers, reading as "model fine, tools broken". Have the user pick a non-1M entry with `/model`, or set `"model": "glm-5.3"` in the project config.

### 4 — Give the user the command to run

**You do not run this one.** It takes their key as an argument, and a key you type is a key in the
transcript. Print it, tell them to substitute their own key from
[pc.0g.ai](https://pc.0g.ai) → Dashboard → API Keys, and wait:

```bash
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/install.sh | bash -s claude --key <THEIR_KEY>
```

Say what it will do, so the command is not a black box: it writes `.claude/settings.json` (config,
no credential, safe to commit) and `.claude/settings.local.json` (their key, mode 600, added to
`.gitignore`), installs `claude` if it is missing, checks the key against the router, and runs the
config checks. It arrives on `glm-5.3` — the strongest TEE tier, and text only: it does not accept
images, and `fallbackModel` does not change that (it fires on overload, not on an unsupported
request).

Mention `--key -` if they would rather not have the key in their shell history — it prompts
instead, with echo off.

If they want a model other than `glm-5.3`, let them install first and then run Mode B. Mode B moves
the four fields together and takes the ceiling from the model's live context length, which is the
part that is easy to leave behind.

### 5 — Hand off

1. Restart Claude Code (close all windows, `claude`). **Any terminal** — the key is in a file now,
   so there is nothing to export and nothing that belongs to one particular shell.
2. `/status` — Base URL should read `https://router-api.0g.ai`. `[claude-code:unrecognized_model]`
   is expected and harmless.
3. Ask the new session to run `echo ok > probe.txt && cat probe.txt`. Under the shipped
   `acceptEdits` it prompts once and succeeds; if the user switched to `auto`, it should run with
   no prompt and no "temporarily unavailable".

Done. To change the model later, run this skill again — it will land in Mode B.

## Mode B — Switch the main model

The config already exists. Change the model in place; leave everything else alone.

### 1 — Offer only what can actually be reached

```bash
curl -s https://router-api.0g.ai/v1/models | python3 -c "
import json,sys
rows=[m for m in json.load(sys.stdin)['data'] if 'anthropic' in (m.get('supported_formats') or [])]
if not rows: sys.exit('router returned no anthropic-format model - stop and report')
for m in sorted(rows, key=lambda x:-(x.get('context_length') or 0)):
    v=m.get('verifiability') if m.get('tee_attested') else None
    tee={'TeeML':'TEE, model in enclave','TeeTLS':'TEE, proxied upstream'}.get(v,'NO TEE')
    a=m.get('architecture') or {}
    img='text+image' if 'image' in (a.get('input_modalities') or []) else 'text only'
    print(f\"{m['id']:22} ctx={m.get('context_length'):>8}  {tee:22} {img}\")"
```

Same list, same TEE column, same rule as Mode A: read the three tiers out loud and do not merge them.

Show it and let the user choose. **Never offer a model missing from it.** The config is a direct
connection, so a model the router serves only in `openai` format cannot be reached at all.

If the user names one — `kimi-k3` and `glm-5.2` are the ones people ask for — say plainly that a
direct config cannot reach it, point them at [the reference](https://github.com/0gfoundation/0g-pc-skills/blob/main/docs/claude-code.md),
and **stop there**. Do not start setting up a local translation layer inside this conversation.
That path exists and is documented; it is not what this skill does.

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
             "a direct config cannot reach it. Pick one from the Step 1 list.")

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

One step, then restart. This one you may run — it carries no key:

```bash
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/install.sh | bash -s claude --uninstall
```

It removes both files and its own block from `.gitignore`, and leaves everything else in `.claude/`
and in `.gitignore` alone — the user may keep their own files in both.

**There is nothing to unset, and that is new.** This used to be the step everyone missed: the key
lived in the shell, outlived the config, and Claude Code kept sending it to `api.anthropic.com`
where it is not valid — an authentication failure that reads as a broken account:

```
⚠ another auth source is set and takes precedence over your claude.ai login
```

If that message appears now, the key is genuinely being exported somewhere — a shell rc file, most
likely — and the fix is there, not here.

## Troubleshooting map

| Symptom | Cause → fix |
|---|---|
| Auto mode: "xxx is temporarily unavailable, cannot determine the safety of …" | Read the model name in the message — it names the classifier model, and the fix follows from it. Gate model wrong: point `modelOverrides["claude-sonnet-5"]` at `0gm-1.0-35b-a3b` (hard rule 4 — Sonnet tier, not Haiku). |
| That message names a model with a `[1m]` suffix (e.g. `0gm-1.0-35b-a3b[1m]`) | The session model carries `[1m]` and Claude Code copied the tag onto the derived classifier model; the router does not serve that ID. Drop the tag: `/model` without the (1M context) variant, or `"model": "glm-5.3"` in `.claude/settings.json`. The Step 5A writer refuses to run while this is in place. |
| That message names your main model (e.g. `glm-5.3`) | The Sonnet-tier resolution returned nothing and the classifier fell back to the main model — either `ANTHROPIC_DEFAULT_SONNET_MODEL` is set to an unrecognised ID (remove it), or a fable/mythos main model sent the classifier to the Opus tier, which this config points at the main model. |
| `API Error: 402` / `Insufficient balance` | Not a config problem — the 0G account is out of credit. Top up at https://pc.0g.ai/dashboard/overview |
| The gate reports `temporarily unavailable` **and** a 402 appeared in the same session | The same thing. An empty balance fails every model, and the gate is simply the first one Claude Code calls — so it surfaces as a gate fault. Check the balance before touching the gate config. |
| 401 | Key wrong or expired. Re-check the key, install it again, and confirm the router accepts it before handing off. A 401 also takes down the auto-mode classifier, so fix this before diagnosing any gate symptom. |
| Model not found | Typo against the Step 1 list — or the model left the router's anthropic-format lineup since the list was shown. Re-run Step 1. |
| Config edits ignored | Old session still running; or `claude` was launched from a directory other than the project holding `.claude/settings.json` (project config is scoped to that directory by design — either run the skill in the other project, or switch to the every-project scope from Step 2 question 3); or leftover `ANTHROPIC_*` in the global `env` or the shell — re-run Step 3. |
