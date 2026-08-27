---
name: 0g-pc-model-config-codex
description: Configure Codex CLI to use 0G Private Computer (pc.0g.ai, router-api.0g.ai) models (glm-5.3, glm-5.2, kimi-k3, qwen3.8-max, etc.) through a local LiteLLM bridge — mandatory because Codex 0.145 and later speaks only the OpenAI Responses API, which the 0G Router does not serve. Use when the user wants to set up, connect, switch, or fix 0G PC / 0G Private Computer / 0G router models in Codex. Triggers include "set up 0G PC in Codex", "connect Codex to 0G", "use 0G models in Codex", "在 Codex 接入 0G PC", "配置 Codex 用 0G", "Codex 连 0G", "0G 在 Codex 里跑不起来".
---

# 0G PC Setup for Codex

Point Codex at 0G Private Computer through a local LiteLLM bridge. All three config files live in this repo — install them, start the proxy, hand off.

Codex ≥ 0.145 speaks only the OpenAI Responses API, and `router-api.0g.ai/v1/responses` returns 404, so the bridge is mandatory. There is no direct-connection option.

## Hard rules

1. **Never modify `~/.codex/config.toml`.** It holds the user's other providers, approval policy and MCP servers. Everything here goes into a standalone profile file plus a bridge directory; deleting those undoes it all. Be straight that this is a weaker promise than the Claude Code skill's: Codex has no per-project config, so nothing can be confined to a folder.
2. **The key never enters the conversation or a config file.** It reaches the proxy only as `ZG_API_KEY` in that terminal's environment. `ZG_LITELLM_KEY="sk-anything"` is **not** a placeholder awaiting a real value — the local proxy performs no authentication, so any string works. Leave it.
3. **Two settings are load-bearing and non-obvious**: `use_chat_completions_api: true` on every model entry (without it requests hit a nonexistent upstream endpoint), and the `zg_patch.py` callback (without it every response stream breaks before completion and Codex reconnects forever). Install the shipped files rather than retyping them.
4. **Nothing changes for existing sessions.** The config applies only when launched with `--profile`. Config edits take effect on the next launch; hand the user the run and verify commands rather than claiming the current session is on 0G.

## Steps

### 1 — Pick the model

```bash
curl -s https://router-api.0g.ai/v1/models | python3 -c "import json,sys; [print(m['id'], m.get('context_length')) for m in json.load(sys.stdin)['data']]"
```

Default `glm-5.3`. Any chat model works through the bridge. If the endpoint is unreachable, stop and report.

### 2 — Confirm the key is exported

```bash
[ -n "$ZG_API_KEY" ] && echo "present (${#ZG_API_KEY} chars)" || echo "absent"
```

Presence and length only. If absent, ask the user to run ` export ZG_API_KEY='sk-…'` in the terminal that will run the proxy — the leading space keeps it out of shell history.

### 3 — Install the three files

```bash
mkdir -p ~/.0g-litellm
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/codex/litellm-config.yaml -o ~/.0g-litellm/litellm-config.yaml
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/codex/zg_patch.py -o ~/.0g-litellm/zg_patch.py
mkdir -p "${CODEX_HOME:-$HOME/.codex}" && curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/codex/zg-glm53.config.toml -o "${CODEX_HOME:-$HOME/.codex}/zg-glm53.config.toml"
```

The profile must land in `$CODEX_HOME` when that is set — Codex looks nowhere else, and it reports nothing when a profile is missing: it silently falls back to its own default and sends the request to OpenAI.

For another model, copy the profile to `zg-<name>.config.toml` and change its `model =` line; the model must appear in the bridge's `model_list`.

### 4 — Start the bridge

Its **own terminal**, kept running; first launch takes a minute or two to install dependencies:

```bash
cd ~/.0g-litellm && uvx --from 'litellm[proxy]==1.98.0' litellm --config litellm-config.yaml --port 4000
```

(`pip install 'litellm[proxy]==1.98.0'` works too. Pin 1.98.0.) Check port 4000 is free first with `lsof -i :4000` — something else listening there produces a confusing 503. Then, from another terminal:

```bash
curl -s -m 5 http://127.0.0.1:4000/health/liveliness && echo
```

### 5 — Confirm Codex loads the profile

Needs neither the proxy nor the network — dropping the key stops Codex right after config resolution:

```bash
env -u ZG_LITELLM_KEY codex exec --profile zg-glm53 --skip-git-repo-check hi < /dev/null 2>&1 | tail -3
```

Expected: ``Missing environment variable: `ZG_LITELLM_KEY` `` — the TOML parsed and the `zg` provider resolved. `Error loading config.toml:` means the profile is broken. The `< /dev/null` is required; `codex exec` blocks on stdin when stdin is a pipe. `codex doctor` will not catch this — it never reads profile files.

### 6 — Hand off

```bash
 export ZG_LITELLM_KEY='sk-anything'
codex --profile zg-glm53
```

**Tell the user to read the `model:` line in the startup banner every time.** `glm-5.3` means the profile loaded. `gpt-*` means it did not, and the request is going to `api.openai.com` — a user logged in to Codex gets a normal-looking answer and never learns their code left the TEE path. That line is the only warning Codex gives.

**Rollback:** `rm "${CODEX_HOME:-$HOME/.codex}"/zg-*.config.toml && rm -rf ~/.0g-litellm`.

## Troubleshooting map

| Symptom | Cause → fix |
|---|---|
| `wire_api = "chat" is no longer supported` at startup | Provider config says `chat`. Use `wire_api = "responses"` pointed at the LiteLLM bridge (Step 5). |
| `stream disconnected before completion` + endless reconnects | `zg_patch.py` not loaded: confirm `litellm_settings.callbacks` names it, the file sits next to the config, and the proxy was started from that directory. Re-check with Layer 2 (expect 1). |
| HTTP 400 `cannot unmarshal object into ... reasoning_effort` | `additional_drop_params: ["reasoning_effort"]` missing from the model entry. |
| LiteLLM 404 "page not found" | Model prefix written as `openai/`; must be `hosted_vllm/`. |
| `Error loading config.toml: <file>:L:C: ...` naming your profile file | The profile TOML is malformed. The Step 5 writer validates before writing; if the file was hand-edited since, re-run the writer. `codex doctor` will not surface this — it does not load profile files. |
| `codex doctor` says config is fine but `--profile` fails | Expected: doctor reads only the base `config.toml`. Use the Step 5 config-load check (`env -u ZG_LITELLM_KEY codex exec --profile …`) to validate a profile. |
| Startup banner shows `model: gpt-*`, or errors name `https://api.openai.com/...` | The profile was not found and Codex fell through to its default provider — silently. Check that the profile file sits in `$CODEX_HOME` (not `~/.codex`) if `CODEX_HOME` is set, and that `--profile` matches the filename. |
| `--profile ... cannot be used while config.toml contains legacy [profiles.x]` | Old inline profile table present. Move it into a standalone `<name>.config.toml` (Step 5). |
| 401 from the router | `ZG_API_KEY` not exported in the proxy terminal, or the key is invalid. |
| Codex hangs with no request reaching LiteLLM | Proxy not running or wrong port — re-run the Step 4 health check. |
