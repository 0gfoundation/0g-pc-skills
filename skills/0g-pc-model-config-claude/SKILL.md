---
name: 0g-pc-model-config-claude
description: Configure Claude Code to use 0G Private Computer (pc.0g.ai, router-api.0g.ai) as its model backend, with tested model combinations (glm-5.2 / glm-5.3 / kimi-k3 / qwen via LiteLLM) and a correctly configured permission-gate model. Use when the user wants to set up, connect, switch, or fix 0G PC / 0G Private Computer / 0G router models in Claude Code. Triggers include "set up 0G PC", "connect Claude Code to 0G", "use 0G models in Claude Code", "接入 0G PC", "配置 0G", "把 Claude Code 接到 0G", "用 0G 的模型", "0G 配置不工作".
---

# 0G PC Setup for Claude Code

Configure Claude Code to run on 0G Private Computer's inference API. Every config in this skill was verified end-to-end on 2026-08-26 (Claude Code 2.1.246, LiteLLM 1.98.0). Follow it exactly — do not improvise config values.

## Hard rules (read first)

1. **Never write a placeholder key; never let the key into the transcript.** These are one rule, not two — the config must be usable the moment it lands on disk, *and* the key must never pass through the conversation. Writing a literal `YOUR_API_KEY` and trusting the user to swap it in later produces a config that 401s on the very next launch, and the failure surfaces in a session this skill cannot observe. Resolve the key in this order: (1) the `ZG_API_KEY` environment variable; (2) a `ZG_API_KEY=` line in the project's `.env`; (3) ask the user to `export ZG_API_KEY='sk-…'` and continue. Never `cat` the key, never echo it, never put it on a command line, and never pass it through an Edit/Write tool call — the writer script in Step 5 reads it from the environment and injects it, so the value never enters your context. **If no key resolves, write no file at all** and say so: a missing config is recoverable, a broken one silently is not. The key lands in a file inside the user's repository, so it may only be written once git is confirmed to be ignoring that file — the writer script in Step 5 enforces this and aborts if it cannot.
2. **Only use configs from this skill.** They are tested; improvised combinations fail in ways that are hard to diagnose (see "Why the gate model matters" below).
3. **Permission-gate iron rule:** the `modelOverrides` and `ANTHROPIC_DEFAULT_HAIKU_MODEL` entries must point to a fast non-reasoning model (`0gm-1.0-35b-a3b`). Never put a reasoning model (glm-5.2, glm-5.3, kimi-k3) there. Reason: in auto mode, every non-read-only action triggers a yes/no safety call on that slot; a reasoning model turns it into a ~950-token reasoning pass, times out, and every Bash/git/network action fails with "model is temporarily unavailable" while chat still works.
4. **Never write to `~/.claude/settings.json`.** That file carries the user's hooks, statusLine, plugins, and their `/model` choice; merging a provider config into it entangles two unrelated things and makes rollback a manual un-merge. Write the project-level `.claude/settings.local.json` instead (verified to carry `env` and `modelOverrides`), or — when the user wants 0G across projects — a standalone `~/.0g/0g-settings.json` they load with `claude --settings`. Either way rollback is deleting one file. Read the global file freely; never modify it.
5. **This skill cannot switch the current session.** Config edits take effect on the next `claude` launch. Finish by telling the user to restart and run the verification steps — do not claim the current session now uses 0G.

## Workflow

### Step 1 — Ask two questions

Ask the user (briefly, not a questionnaire):

1. "Is your code/data confidential (must run fully inside TEE enclaves)?" → If yes: use **Path A** with a **Private**-mode key (note: only 3 models available, no failover; tell the user this trade-off).
2. "Which main model do you want?" → `glm-5.2` (or another anthropic-format model) → **Path A (direct)**. `glm-5.3` / `kimi-k3` / `qwen3.8-max` / other openai-only models → **Path B (via LiteLLM)**.

If the user has no preference: default to Path A with `glm-5.2`.

### Step 2 — Check the live model list

Tool: **Bash**

```bash
curl -s https://router-api.0g.ai/v1/models | jq -r \
  '.data[] | [.id, (.supported_formats|join("+")), (.verifiability // "-"), (.context_length|tostring)] | @tsv'
```

If `jq` is not installed, use this instead (macOS ships python3):

```bash
curl -s https://router-api.0g.ai/v1/models | python3 -c "import json,sys; [print(m['id'], '+'.join(m.get('supported_formats',[])), m.get('verifiability','-'), m.get('context_length')) for m in json.load(sys.stdin)['data']]"
```

Expected output: a table of model IDs, formats, TEE type, context length. Confirm the chosen main model exists and note its `supported_formats`:

- contains `anthropic` → Path A works (direct connection).
- `openai` only → Path B required (LiteLLM translation).

Also confirm `0gm-1.0-35b-a3b` is listed (it is the gate model for both paths). If the endpoint is unreachable, stop and report — do not proceed on a stale model list.

### Step 3 — Inspect existing config (read only — never modify it)

Tool: **Read** `~/.claude/settings.json` and `<project>/.claude/settings.json` if they exist. Both are inspected for conflicts; **neither is written** (hard rule 4).

- If either `env` already contains `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL`, or any `ANTHROPIC_DEFAULT_*_MODEL` from a previous provider (Kimi, GLM, etc.): tell the user those values will be shadowed by the project-level file this skill writes, and that removing them is their call — leftovers in the global file are the usual reason a later rollback appears not to work.
- Also warn the user to check `~/.zshrc` / `~/.bashrc` for stale `ANTHROPIC_*` exports — settings `env` overrides shell exports, but leftovers cause confusion when the config file is removed later.

### Step 4 — Resolve the API key (never see it, never fake it)

Tool: **Bash**. Probe for a key without reading its value — both commands report presence and length only:

```bash
[ -n "$ZG_API_KEY" ] && echo "env ZG_API_KEY: present (${#ZG_API_KEY} chars)" || echo "env ZG_API_KEY: absent"
grep -q '^ZG_API_KEY=' .env 2>/dev/null && echo ".env: has ZG_API_KEY" || echo ".env: no ZG_API_KEY"
```

If neither reports a key, stop and tell the user:

> Create an inference key (starts with `sk-`) at pc.0g.ai → Dashboard → API Keys. For confidential mode (Path A + Private), select the **Private** trust mode when creating it. Then run ` export ZG_API_KEY='sk-…'` in this shell — the leading space keeps it out of shell history — and tell me to continue.

**Do not advance to Step 5 without a key.** Hard rule 1 forbids writing a placeholder, so with no key there is nothing to write; say that plainly rather than producing a file that will 401.

### Step 5A — Path A: direct connection (main model glm-5.2)

Target: `<repo root>/.claude/settings.local.json`. This is the shape the config takes (`ANTHROPIC_AUTH_TOKEN` is filled in by the writer script below, from the environment — never typed by hand):

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://router-api.0g.ai",
    "ANTHROPIC_AUTH_TOKEN": "<injected from $ZG_API_KEY>",
    "ANTHROPIC_API_KEY": "",

    "ANTHROPIC_MODEL": "glm-5.2",
    "ANTHROPIC_DEFAULT_FABLE_MODEL": "glm-5.2",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5.2",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "0gm-1.0-35b-a3b",

    "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "983616"
  },
  "modelOverrides": {
    "claude-sonnet-5": "0gm-1.0-35b-a3b"
  },
  "permissions": { "defaultMode": "auto" }
}
```

Tool: **Bash**. Write it with this script — **not** with Edit/Write. The script is the only thing that ever touches the key value, so the key never reaches your context or a tool result, and it refuses to produce a file when no key resolves:

```bash
python3 - <<'PY'
import json, os, pathlib, re, subprocess, sys

key = os.environ.get("ZG_API_KEY", "").strip()
if not key:
    env = pathlib.Path(".env")
    if env.is_file():
        m = re.search(r'^ZG_API_KEY=(.+)$', env.read_text(), re.M)
        if m:
            key = m.group(1).strip().strip('"').strip("'")
if not key:
    sys.exit("no ZG_API_KEY resolved — refusing to write a placeholder config (hard rule 1)")

def git(*args):
    r = subprocess.run(("git",) + args, capture_output=True, text=True)
    return r.returncode, r.stdout.strip()

rc, root = git("rev-parse", "--show-toplevel")
root = pathlib.Path(root) if rc == 0 else pathlib.Path.cwd()
target = root / ".claude" / "settings.local.json"

# The key lands inside the repo, so git must be ignoring this file before it exists.
if rc == 0:
    rel = target.relative_to(root).as_posix()
    if git("ls-files", "--error-unmatch", rel)[0] == 0:
        sys.exit("%s is tracked by git — adding a key to it would stage a secret. "
                 "Run `git rm --cached %s` first, then re-run this step." % (rel, rel))
    if git("check-ignore", "-q", rel)[0] != 0:
        gi = root / ".gitignore"
        prev = gi.read_text() if gi.is_file() else ""
        with gi.open("a") as f:
            if prev and not prev.endswith("\n"):
                f.write("\n")
            f.write("\n# 0G PC config — contains an API key, never commit\n.claude/settings.local.json\n")
        print("appended .claude/settings.local.json to", gi)
    if git("check-ignore", "-q", rel)[0] != 0:
        sys.exit("git still does not ignore %s — refusing to write a key into a tracked path" % rel)

cfg = json.loads(target.read_text()) if target.is_file() else {}
cfg.setdefault("env", {}).update({
    "ANTHROPIC_BASE_URL": "https://router-api.0g.ai",
    "ANTHROPIC_AUTH_TOKEN": key,
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_MODEL": "glm-5.2",
    "ANTHROPIC_DEFAULT_FABLE_MODEL": "glm-5.2",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5.2",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "0gm-1.0-35b-a3b",
    "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "983616",
})
cfg.setdefault("modelOverrides", {})["claude-sonnet-5"] = "0gm-1.0-35b-a3b"
cfg.setdefault("permissions", {})["defaultMode"] = "auto"
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(cfg, indent=2) + "\n")
print("wrote", target)
PY
```

Then prove the key actually works before handing off — this is the check that turns "written" into "verified" (expect `HTTP 200`; `401` means the key is wrong or expired, and the config is not done):

```bash
curl -s https://router-api.0g.ai/v1/chat/completions \
  -H "Authorization: Bearer $ZG_API_KEY" -H "content-type: application/json" \
  -d '{"model":"glm-5.2","messages":[{"role":"user","content":"ping"}],"max_tokens":600}' \
  -o /dev/null -w 'HTTP %{http_code}\n'
```

Notes to apply, not to debate:

- `modelOverrides` sets the permission-gate model and exists **only** in settings.json (no env-var equivalent). Do not substitute `ANTHROPIC_DEFAULT_SONNET_MODEL` — that replaces the whole slot and re-enables reasoning on the gate call.
- `CLAUDE_CODE_MAX_CONTEXT_TOKENS` is required; without it a 1M-context model is treated as 200K and compacts early.
- If using a different anthropic-format main model, change only the three main-model lines; keep the gate entries as-is.
- **Scope:** a project-level file applies only inside that directory. If the user wants 0G in every project, write the same JSON to `~/.0g/0g-settings.json` instead (outside any repo, so the gitignore guard is not needed) and have them launch with `claude --settings ~/.0g/0g-settings.json` — worth an alias. Rollback is still one `rm`.

Then go to Step 6.

### Step 5B — Path B: via LiteLLM (main model glm-5.3 / kimi-k3 / qwen3.8-max / minimax-m3)

Create a dedicated directory outside any git repository.

Tool: **Bash**

```bash
mkdir -p ~/.0g-litellm
```

Tool: **Write** `~/.0g-litellm/litellm-config.yaml`:

```yaml
model_list:
  - model_name: glm-5.3
    litellm_params:
      model: hosted_vllm/glm-5.3           # prefix MUST be hosted_vllm/ (openai/ routes to a nonexistent /v1/responses -> 404)
      api_base: https://router-api.0g.ai/v1
      api_key: os.environ/ZG_API_KEY
      use_chat_completions_api: true
      additional_drop_params: ["reasoning_effort"]   # router rejects the object form with HTTP 400
  - model_name: kimi-k3
    litellm_params:
      model: hosted_vllm/kimi-k3
      api_base: https://router-api.0g.ai/v1
      api_key: os.environ/ZG_API_KEY
      use_chat_completions_api: true
      additional_drop_params: ["reasoning_effort"]
  - model_name: qwen3.8-max
    litellm_params:
      model: hosted_vllm/qwen3.8-max
      api_base: https://router-api.0g.ai/v1
      api_key: os.environ/ZG_API_KEY
      use_chat_completions_api: true
      additional_drop_params: ["reasoning_effort"]
  - model_name: 0gm-1.0-35b-a3b            # gate model goes through the proxy too: one BASE_URL per session
    litellm_params:
      model: hosted_vllm/0gm-1.0-35b-a3b
      api_base: https://router-api.0g.ai/v1
      api_key: os.environ/ZG_API_KEY
      use_chat_completions_api: true
      additional_drop_params: ["reasoning_effort"]

litellm_settings:
  num_retries: 2
  callbacks: zg_patch.zg_patch_instance
```

Tool: **Write** `~/.0g-litellm/zg_patch.py`:

```python
"""Workaround: 0G Router ends every stream with a billing chunk whose "choices" is [],
and LiteLLM's Responses-API bridge crashes on it (choices[0] IndexError).
Loaded via litellm_settings.callbacks; remove once fixed upstream in LiteLLM."""
from litellm.integrations.custom_logger import CustomLogger
from litellm.responses.litellm_completion_transformation import streaming_iterator as _si

_orig = _si.LiteLLMCompletionStreamingIterator._get_delta_string_from_streaming_choices

def _safe(self, choices):
    if not choices:
        return ""
    return _orig(self, choices)

_si.LiteLLMCompletionStreamingIterator._get_delta_string_from_streaming_choices = _safe

class _Noop(CustomLogger):
    pass

zg_patch_instance = _Noop()
```

Tell the user to start the proxy in a separate terminal (it must keep running; first launch takes 1–2 min to install dependencies):

```bash
cd ~/.0g-litellm
export ZG_API_KEY="sk-...your key..."
uvx --from 'litellm[proxy]==1.98.0' litellm --config litellm-config.yaml --port 4000
```

(If `uvx` is unavailable, alternative: `pip install 'litellm[proxy]==1.98.0'` then `litellm --config litellm-config.yaml --port 4000` from the same directory. Pin 1.98.0 — it is the tested version.)

Then write `<repo root>/.claude/settings.local.json` with the same script as Step 5A (same gitignore guard; substitute the values below). The main model here is `glm-5.3` — substitute the user's chosen model name in the three main-model lines. Path B's token is the literal `sk-anything`, not a key: the local proxy does not authenticate, and the real key lives only in the proxy terminal's `ZG_API_KEY`.

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:4000",
    "ANTHROPIC_AUTH_TOKEN": "sk-anything",
    "ANTHROPIC_API_KEY": "",

    "ANTHROPIC_MODEL": "glm-5.3",
    "ANTHROPIC_DEFAULT_FABLE_MODEL": "glm-5.3",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5.3",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "0gm-1.0-35b-a3b",

    "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "983616"
  },
  "modelOverrides": {
    "claude-sonnet-5": "0gm-1.0-35b-a3b"
  },
  "permissions": { "defaultMode": "auto" }
}
```

`ANTHROPIC_AUTH_TOKEN` is a placeholder — the local proxy does not authenticate; the real key lives only in the `ZG_API_KEY` environment variable of the proxy terminal.

### Step 6 — Hand off: restart + verify

Tell the user, verbatim in substance:

1. The config is already complete — it lives in `.claude/settings.local.json` in this project, the key was injected from `ZG_API_KEY` in Step 5, and the `HTTP 200` probe confirmed it works. Nothing is left to fill in by hand, and their global `~/.claude/settings.json` was not touched. **To roll back: `rm .claude/settings.local.json`.** (Path B: the token in that file stays `sk-anything`; the real key lives only in the proxy terminal's `export ZG_API_KEY=…`.)
2. Restart Claude Code (close all windows, open a new terminal, run `claude`). Config changes do not affect the current session.
3. In the new session, type `/status` — the Base URL must show `https://router-api.0g.ai` (Path A) or `http://127.0.0.1:4000` (Path B). The startup warning `[claude-code:unrecognized_model]` is harmless.
4. Ask the new session to run one gated action, e.g. "use Bash to run `echo ok > probe.txt && cat probe.txt`". Success with no "temporarily unavailable" error proves the gate path works.

If something fails, run these probes (Tool: **Bash**) and match the layer that breaks:

```bash
# Layer 1 — router reachable with the key (expect: HTTP 200)
curl -s https://router-api.0g.ai/v1/chat/completions -H "Authorization: Bearer $ZG_API_KEY" \
  -H "content-type: application/json" \
  -d '{"model":"glm-5.2","messages":[{"role":"user","content":"ping"}],"max_tokens":600}' \
  -w '\nHTTP %{http_code}\n' | tail -1

# Layer 2 (Path B only) — LiteLLM anthropic endpoint (expect: HTTP 200)
curl -s http://127.0.0.1:4000/v1/messages -H "x-api-key: sk-anything" \
  -H "anthropic-version: 2023-06-01" -H "content-type: application/json" \
  -d '{"model":"glm-5.3","max_tokens":64,"messages":[{"role":"user","content":"ping"}]}' \
  -w '\nHTTP %{http_code}\n' | tail -1
```

## Troubleshooting map

| Symptom | Cause → fix |
|---|---|
| Auto mode: "xxx is temporarily unavailable, cannot determine the safety of …" | Gate model wrong. Point `modelOverrides` + `ANTHROPIC_DEFAULT_HAIKU_MODEL` at `0gm-1.0-35b-a3b` (hard rule 3). |
| 401 | Key wrong or expired. Path A: re-run Step 4's probe, re-export a fresh key, re-run the Step 5A writer, and re-run the `HTTP 200` check before handing off. Path B: `ZG_API_KEY` not exported in the proxy terminal. A 401 also takes down the auto-mode classifier, so fix this before diagnosing any gate symptom. |
| Model not found | Typo vs Step 2 list, or (Path B) model missing from `model_list`. |
| LiteLLM 404 "page not found" | Model prefix written as `openai/`; must be `hosted_vllm/`. |
| Config edits ignored | Old session still running; or `claude` was launched from a directory other than the project holding `.claude/settings.local.json` (project config is scoped to that directory — use the `~/.0g/0g-settings.json` + `claude --settings` route for global use); or leftover `ANTHROPIC_*` in the global `env` or the shell — re-run Step 3. |
