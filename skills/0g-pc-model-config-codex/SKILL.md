---
name: 0g-pc-model-config-codex
description: Configure Codex CLI to use 0G Private Computer (pc.0g.ai, router-api.0g.ai) models (glm-5.3, glm-5.2, kimi-k3, qwen3.8-max, etc.) through a local LiteLLM bridge — mandatory because Codex 0.145 and later speaks only the OpenAI Responses API, which the 0G Router does not serve. Use when the user wants to set up, connect, switch, or fix 0G PC / 0G Private Computer / 0G router models in Codex. Triggers include "set up 0G PC in Codex", "connect Codex to 0G", "use 0G models in Codex", "在 Codex 接入 0G PC", "配置 Codex 用 0G", "Codex 连 0G", "0G 在 Codex 里跑不起来".
---

# 0G PC Setup for Codex

Configure Codex CLI to run on 0G Private Computer's inference API. Every config in this skill was verified end-to-end on 2026-08-26 (Codex CLI 0.145.0, LiteLLM 1.98.0). Follow it exactly — do not improvise config values.

Why a bridge is mandatory (state this once to the user, then move on): Codex ≥ 0.145 removed `wire_api = "chat"` and speaks only the OpenAI Responses API; `router-api.0g.ai/v1/responses` returns 404. A local LiteLLM proxy bridges Responses → chat completions. There is no direct-connection option.

## Hard rules (read first)

1. **Never modify `~/.codex/config.toml`.** That file carries the user's other providers, approval policy, and MCP servers; appending to it makes rollback a manual un-append. Everything this skill needs — the profile *and* the `[model_providers.zg]` block — fits in a standalone `~/.codex/<name>.config.toml`, verified to load with no base `config.toml` present at all. Rollback is deleting one file. Read the base file freely; never modify it. **Be straight with the user about what this does and does not promise** (see the note below Workflow): Codex has no project-level config discovery — profiles are only found in `$CODEX_HOME` — so unlike the Claude Code skill, this one cannot keep its output inside the project. What it can promise is that nothing they already configured is edited, and that removing one added file undoes everything. Do not dress that up as project scoping.
2. **Never echo, log, or repeat the user's API key.** It goes only into the `ZG_API_KEY` environment variable of the proxy terminal. Never write it into any file inside a git repository. Note that `ZG_LITELLM_KEY="sk-anything"` in Step 6 is **not** a placeholder waiting to be filled in — the local proxy performs no authentication, so any string works. Leave it alone; the real key lives only in the proxy terminal.
3. **Only use configs from this skill.** Two items are load-bearing and non-obvious: `use_chat_completions_api: true` on every model entry (without it requests hit a nonexistent upstream endpoint) and the `zg_patch.py` callback (without it every response stream breaks before completion and Codex reconnects forever).
4. **Config edits take effect on the next `codex` launch.** Finish by handing the user the run + verification commands — do not claim the current session is already on 0G.

## Workflow

**Before asking anything, say this to the user:**

> Codex only discovers configuration under `~/.codex` — it has no per-project config, so unlike the Claude Code setup this cannot be confined to one folder. What I will not do is edit anything already there: your `~/.codex/config.toml` is read, never written. Everything I add is one new file, `~/.codex/zg-<model>.config.toml`, plus a bridge directory at `~/.0g-litellm/`. Deleting them undoes all of it, and the setup only applies when you launch with `--profile zg-<model>`.

That last clause matters: nothing changes for their existing Codex sessions unless they pass the profile flag.

### Step 1 — Pick the model

Ask which model the user wants (default: `glm-5.3`). Check it exists on the live list.

Tool: **Bash**

```bash
curl -s https://router-api.0g.ai/v1/models | jq -r \
  '.data[] | [.id, (.supported_formats|join("+")), (.context_length|tostring)] | @tsv'
```

If `jq` is not installed, use this instead (macOS ships python3):

```bash
curl -s https://router-api.0g.ai/v1/models | python3 -c "import json,sys; [print(m['id'], '+'.join(m.get('supported_formats',[])), m.get('context_length')) for m in json.load(sys.stdin)['data']]"
```

Expected output: a table of model IDs, formats, context length. Any model with `openai` in its formats works through the bridge (that is all of the chat models). If the endpoint is unreachable, stop and report — do not proceed on a stale model list.

### Step 2 — Get the API key

Tell the user: create an inference key (starts with `sk-`) at pc.0g.ai → Dashboard → API Keys, and have it ready for the proxy terminal in Step 4. Do not ask them to paste it into any file you will create.

### Step 3 — Write the LiteLLM bridge files

Create a dedicated directory outside any git repository.

Tool: **Bash**

```bash
mkdir -p ~/.0g-litellm
```

Tool: **Write** `~/.0g-litellm/litellm-config.yaml` (add or remove `model_list` entries to match the models the user wants; keep every entry's two critical params):

```yaml
model_list:
  - model_name: glm-5.3
    litellm_params:
      model: hosted_vllm/glm-5.3           # prefix MUST be hosted_vllm/ (openai/ routes upstream to a nonexistent /v1/responses -> 404)
      api_base: https://router-api.0g.ai/v1
      api_key: os.environ/ZG_API_KEY
      use_chat_completions_api: true        # REQUIRED for the Responses->chat bridge Codex depends on
      additional_drop_params: ["reasoning_effort"]   # router rejects Codex's reasoning object with HTTP 400
  - model_name: glm-5.2
    litellm_params:
      model: hosted_vllm/glm-5.2
      api_base: https://router-api.0g.ai/v1
      api_key: os.environ/ZG_API_KEY
      use_chat_completions_api: true
      additional_drop_params: ["reasoning_effort"]
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

### Step 4 — Start the bridge

Tell the user to run this in a separate terminal (it must keep running; first launch takes 1–2 min to install dependencies):

```bash
cd ~/.0g-litellm
export ZG_API_KEY="sk-...your key..."
uvx --from 'litellm[proxy]==1.98.0' litellm --config litellm-config.yaml --port 4000
```

(If `uvx` is unavailable: `pip install 'litellm[proxy]==1.98.0'` then `litellm --config litellm-config.yaml --port 4000` from the same directory. Pin 1.98.0 — it is the tested version; 1.99.0rc1 carries the same stream bug and the patch covers both.)

Health check once it prints its startup banner — Tool: **Bash**

```bash
curl -s -m 5 http://127.0.0.1:4000/health/liveliness && echo && \
curl -s http://127.0.0.1:4000/v1/models -H "Authorization: Bearer sk-anything" | jq -r '.data[].id'
```

(Without `jq`, replace the second line's pipe with `python3 -c "import json,sys; [print(m['id']) for m in json.load(sys.stdin)['data']]"`.)

Expected output: a liveliness response, then the model names from `model_list`.

### Step 5 — Configure Codex

Everything goes in one standalone profile file. `~/.codex/config.toml` is never touched — a profile file carries its own `[model_providers.*]` block, and Codex loads it even when no base `config.toml` exists.

Profiles in Codex ≥ 0.145 are **standalone files**; an inline `[profiles.x]` table in config.toml makes Codex refuse to start.

Tool: **Bash**. Write it with this script — it validates the TOML in memory before anything reaches disk, and backs up a previous file of the same name:

```bash
python3 - <<'PY'
import pathlib, shutil, sys
try:
    import tomllib
except ModuleNotFoundError:
    tomllib = None

MODEL = "glm-5.3"          # must exist in the LiteLLM model_list
NAME  = "zg-glm53"         # the --profile name

body = """model = "%s"
model_provider = "zg"

[model_providers.zg]
name = "0G Private Computer via LiteLLM"
base_url = "http://127.0.0.1:4000/v1"
env_key = "ZG_LITELLM_KEY"
wire_api = "responses"
""" % MODEL

if tomllib is not None:
    try:
        parsed = tomllib.loads(body)
    except tomllib.TOMLDecodeError as e:
        sys.exit("refusing to write: generated TOML does not parse (%s)" % e)
    if parsed["model_providers"]["zg"]["wire_api"] != "responses":
        sys.exit('refusing to write: wire_api must be "responses" on Codex >= 0.145')
else:
    print("note: python < 3.11, no tomllib — relying on the config-load check below")

home = pathlib.Path.home() / ".codex"
home.mkdir(parents=True, exist_ok=True)
target = home / (NAME + ".config.toml")
if target.is_file():
    shutil.copy2(target, str(target) + ".bak")
    print("backed up previous profile to", str(target) + ".bak")
target.write_text(body)
print("wrote", target)
PY
```

For each additional model, run it again with `MODEL` and `NAME` changed (the model must exist in the LiteLLM `model_list`).

Then confirm Codex can actually load it — **before** handing off. Unsetting the key makes the check stop right after config resolution, so it needs neither the proxy nor the network:

```bash
env -u ZG_LITELLM_KEY codex exec --profile zg-glm53 --skip-git-repo-check hi < /dev/null 2>&1 | tail -3
```

The `< /dev/null` is required — `codex exec` blocks waiting on stdin when it is a pipe. Expected: ``Missing environment variable: `ZG_LITELLM_KEY` `` — that message means the config parsed *and* the `zg` provider resolved. Anything starting `Error loading config.toml:` means the profile is broken; fix it before continuing. (`codex doctor` will not catch this — it does not read profile files.)

### Step 6 — Hand off: run + verify

Give the user these commands:

```bash
export ZG_LITELLM_KEY="sk-anything"   # placeholder; the local proxy does not check it
codex --profile zg-glm53
# or non-interactive:
codex exec --profile zg-glm53 "create hello.txt containing: hello from 0g, then cat it"
```

Expected: Codex plans, runs the shell command, and reports the file content. The startup warning `Model metadata for glm-5.3 not found... fallback metadata` is harmless.

If something fails, probe layer by layer (Tool: **Bash**) and match the first layer that breaks:

```bash
# Layer 1 — router reachable with the key (expect: HTTP 200)
curl -s https://router-api.0g.ai/v1/chat/completions -H "Authorization: Bearer $ZG_API_KEY" \
  -H "content-type: application/json" \
  -d '{"model":"glm-5.3","messages":[{"role":"user","content":"ping"}],"max_tokens":600}' \
  -w '\nHTTP %{http_code}\n' | tail -1

# Layer 2 — the bridge's Responses endpoint, the one Codex actually uses
# (expect: output "1", meaning the stream ends with response.completed)
curl -s -N http://127.0.0.1:4000/v1/responses -H "Authorization: Bearer sk-anything" \
  -H "content-type: application/json" \
  -d '{"model":"glm-5.3","input":"ping","stream":true}' | grep -c "response.completed"
```

## Troubleshooting map

| Symptom | Cause → fix |
|---|---|
| `wire_api = "chat" is no longer supported` at startup | Provider config says `chat`. Use `wire_api = "responses"` pointed at the LiteLLM bridge (Step 5). |
| `stream disconnected before completion` + endless reconnects | `zg_patch.py` not loaded: confirm `litellm_settings.callbacks` names it, the file sits next to the config, and the proxy was started from that directory. Re-check with Layer 2 (expect 1). |
| HTTP 400 `cannot unmarshal object into ... reasoning_effort` | `additional_drop_params: ["reasoning_effort"]` missing from the model entry. |
| LiteLLM 404 "page not found" | Model prefix written as `openai/`; must be `hosted_vllm/`. |
| `Error loading config.toml: <file>:L:C: ...` naming your profile file | The profile TOML is malformed. The Step 5 writer validates before writing; if the file was hand-edited since, re-run the writer. `codex doctor` will not surface this — it does not load profile files. |
| `codex doctor` says config is fine but `--profile` fails | Expected: doctor reads only the base `config.toml`. Use the Step 5 config-load check (`env -u ZG_LITELLM_KEY codex exec --profile …`) to validate a profile. |
| `--profile ... cannot be used while config.toml contains legacy [profiles.x]` | Old inline profile table present. Move it into a standalone `<name>.config.toml` (Step 5). |
| 401 from the router | `ZG_API_KEY` not exported in the proxy terminal, or the key is invalid. |
| Codex hangs with no request reaching LiteLLM | Proxy not running or wrong port — re-run the Step 4 health check. |
