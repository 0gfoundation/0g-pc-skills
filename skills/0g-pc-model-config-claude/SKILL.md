---
name: 0g-pc-model-config-claude
description: Configure Claude Code to use 0G Private Computer (pc.0g.ai, router-api.0g.ai) as its model backend, with tested model combinations (glm-5.2 / glm-5.3 / kimi-k3 / qwen via LiteLLM) and a correctly configured permission-gate model. Use when the user wants to set up, connect, switch, or fix 0G PC / 0G Private Computer / 0G router models in Claude Code. Triggers include "set up 0G PC", "connect Claude Code to 0G", "use 0G models in Claude Code", "接入 0G PC", "配置 0G", "把 Claude Code 接到 0G", "用 0G 的模型", "0G 配置不工作".
---

# 0G PC Setup for Claude Code

Configure Claude Code to run on 0G Private Computer's inference API. Every config in this skill was verified end-to-end on 2026-08-26 (Claude Code 2.1.246, LiteLLM 1.98.0). Follow it exactly — do not improvise config values.

## Hard rules (read first)

1. **Never modify `~/.claude/settings.json`, and default to project scope.** Two parts, and only the first is absolute:
   - **Absolute:** the user's global settings file — their hooks, statusLine, plugins, `/model` choice — is **read, never written**, whatever scope they pick. A failed setup must not be able to damage anything they configured.
   - **Default:** the config goes to `<repo root>/.claude/settings.local.json`. Rollback is deleting one file.
   - The user *may* choose to have 0G apply everywhere (Step 2, question 3). Honour it — but it is theirs to ask for, never your default and never silent: it goes to a standalone `~/.0g/0g-settings.json` loaded with `claude --settings`, which still leaves `~/.claude/settings.json` untouched.
   **State this to the user before asking anything** (Step 2); they should not have to infer it from the result.
2. **Never write a placeholder key; never let the key into the transcript.** These are one rule, not two — the config must be usable the moment it lands on disk, *and* the key must never pass through the conversation. Writing a literal `YOUR_API_KEY` and trusting the user to swap it in later produces a config that 401s on the very next launch, and the failure surfaces in a session this skill cannot observe. The key comes from one place only: the `ZG_API_KEY` environment variable. If it is not set, ask the user to `export ZG_API_KEY='sk-…'` and continue — do not go looking for it in `.env` or anywhere else in the project. A key sitting in a file inside the repository is one `git add -A` away from being committed, and this skill's gitignore guard covers only the files it writes, not the ones it might read. Never `cat` the key, never echo it, never put it on a command line, and never pass it through an Edit/Write tool call — the writer script in Step 5 reads it from the environment and injects it, so the value never enters your context. **If no key resolves, write no file at all** and say so: a missing config is recoverable, a broken one silently is not. The key lands in a file inside the user's repository, so it may only be written once git is confirmed to be ignoring that file — the writer script in Step 5 enforces this and aborts if it cannot.
3. **Only use configs from this skill.** They are tested; improvised combinations fail in ways that are hard to diagnose — the permission-gate entries in particular (hard rule 4).
4. **Permission-gate iron rule:** in auto mode the safety classifier resolves through the **Sonnet** tier — not Haiku. On a third-party router that means `ANTHROPIC_DEFAULT_SONNET_MODEL` when it is set *and* the value is recognised, otherwise the built-in `claude-sonnet-5` mapped through `modelOverrides`. So `modelOverrides["claude-sonnet-5"]` must point at a fast non-reasoning model (`0gm-1.0-35b-a3b`), never at a reasoning model (glm-5.2, glm-5.3, kimi-k3): every non-read-only action triggers a yes/no safety call on that slot, and a reasoning model turns it into a ~950-token reasoning pass that times out — every Bash/git/network action then fails with "model is temporarily unavailable" while chat keeps working. `ANTHROPIC_DEFAULT_HAIKU_MODEL` is *not* the gate; it is kept on a fast model for unrelated background work.
5. **This skill cannot switch the current session.** Config edits take effect on the next `claude` launch. Finish by telling the user to restart and run the verification steps — do not claim the current session now uses 0G.

## Workflow

### Step 1 — Fetch the live model list first

Ask nothing before this. The main-model question is unanswerable without the list, and the list is what decides Path A vs Path B.

Tool: **Bash**

```bash
curl -s https://router-api.0g.ai/v1/models | jq -r \
  '.data[] | [.id, (.supported_formats|join("+")), (.verifiability // "-"), (.context_length|tostring)] | @tsv'
```

If `jq` is not installed, use this instead (macOS ships python3):

```bash
curl -s https://router-api.0g.ai/v1/models | python3 -c "import json,sys; [print(m['id'], '+'.join(m.get('supported_formats',[])), m.get('verifiability','-'), m.get('context_length')) for m in json.load(sys.stdin)['data']]"
```

Show the user the result grouped by connection path — `supported_formats` containing `anthropic` means Path A (direct), `openai` only means Path B (via LiteLLM). Roughly:

```
Direct (Path A):   glm-5.2 (1048576)   0gm-1.0-35b-a3b (262144)   deepseek-v4-flash (1M)
                   glm-5 (202752)      claude-sonnet-5 (1M)       claude-opus-5 (1M)
Via LiteLLM (B):   glm-5.3 (1M)   kimi-k3 (1048576)   qwen3.8-max (1M)   minimax-m3 (1M)
                   gpt-5.6-* (1M)   deepseek-v4-pro (1M)   kimi-k2.7-code (262144)
```

That grouping is illustrative — always print what the live call returned, never this snapshot.

Also confirm `0gm-1.0-35b-a3b` is listed (it is the gate model for both paths). If the endpoint is unreachable, **stop and report** — do not proceed on a stale model list, and do not start asking questions.

### Step 2 — State the guarantee, then ask five questions

**First, say this to the user — before any question:**

> Your global `~/.claude/settings.json` — hooks, plugins, status line, your `/model` choice — will be read but never modified, whichever scope you pick. By default the config goes into `.claude/settings.local.json` in this project, and undoing it is deleting that one file. If you'd rather have 0G apply to every project, say so at question 3 and it goes into a standalone file instead — still not your global settings.

Then, with the model list on screen, ask all five at once. Every one has a default, so a user with no opinions answers by nodding once.

1. **Confidential?** Does the code/data have to run fully inside TEE enclaves? → yes means **Path A** with a **Private**-mode key (trade-off: only 3 models, no failover — say so). *Default: no.*
2. **Main model?** Pick from the Step 1 table. Anthropic-format → **Path A (direct)**; openai-only → **Path B (via LiteLLM)**. *Default: `glm-5.2` (Path A).*
3. **Scope?** This project, or every project? *Default: this project* — writes `.claude/settings.local.json`, no launch flag needed, `rm` to undo. Every-project writes `~/.0g/0g-settings.json`, loaded with `claude --settings ~/.0g/0g-settings.json` (worth an alias); it sits outside every repo, so the key never lands in a working tree, and `~/.claude/settings.json` is still untouched. Only offer this because they asked — never steer toward it.
4. **Permission mode?** State both costs — do not set this silently:
   - `acceptEdits` *(default)* — file edits pass automatically, Bash asks each time. No dependency on the safety classifier, so a router hiccup cannot take the session down.
   - `auto` — the classifier judges non-read-only actions, so far fewer confirmations; but it is an extra request against the router, and if it fails (router wobble, a `[1m]` model name, an expired key) Claude Code fails closed and refuses **every** non-read-only tool. Choose this only if the gate config in Step 5A has been verified.
5. **Key source?** Is `ZG_API_KEY` already exported, or will they export it now? *Default: whatever Step 4's probe finds.* There is no other accepted source.

### Step 3 — Inspect existing config (read only — never modify it)

Tool: **Read** `~/.claude/settings.json` and `<project>/.claude/settings.json` if they exist. Both are inspected for conflicts; **neither is written** (hard rule 1).

- If either `env` already contains `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL`, or any `ANTHROPIC_DEFAULT_*_MODEL` from a previous provider (Kimi, GLM, etc.): tell the user those values will be shadowed by the project-level file this skill writes, and that removing them is their call — leftovers in the global file are the usual reason a later rollback appears not to work.
- Also warn the user to check `~/.zshrc` / `~/.bashrc` for stale `ANTHROPIC_*` exports — settings `env` overrides shell exports, but leftovers cause confusion when the config file is removed later.

### Step 4 — Resolve the API key (never see it, never fake it)

Tool: **Bash**. Probe for a key without reading its value — both commands report presence and length only:

```bash
[ -n "$ZG_API_KEY" ] && echo "env ZG_API_KEY: present (${#ZG_API_KEY} chars)" || echo "env ZG_API_KEY: absent"
```

If it reports absent, stop and tell the user:

> Create an inference key (starts with `sk-`) at pc.0g.ai → Dashboard → API Keys. For confidential mode (Path A + Private), select the **Private** trust mode when creating it. Then run ` export ZG_API_KEY='sk-…'` in this shell — the leading space keeps it out of shell history — and tell me to continue.

**Do not advance to Step 5 without a key.** Hard rule 2 forbids writing a placeholder, so with no key there is nothing to write; say that plainly rather than producing a file that will 401.

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
  "permissions": { "defaultMode": "acceptEdits" }
}
```

Tool: **Bash**. Write it with this script — **not** with Edit/Write. The script is the only thing that ever touches the key value, so the key never reaches your context or a tool result, and it refuses to produce a file when no key resolves:

```bash
python3 - <<'PY'
import json, os, pathlib, subprocess, sys

key = os.environ.get("ZG_API_KEY", "").strip()
if not key:
    sys.exit("no ZG_API_KEY resolved — refusing to write a placeholder config (hard rule 2)")

def git(*args):
    r = subprocess.run(("git",) + args, capture_output=True, text=True)
    return r.returncode, r.stdout.strip()

rc, root = git("rev-parse", "--show-toplevel")
root = pathlib.Path(root) if rc == 0 else pathlib.Path.cwd()
target = root / ".claude" / "settings.local.json"

# A [1m]-tagged session model poisons the auto-mode classifier. Claude Code derives the
# classifier model from the Sonnet tier, then copies the main model's [1m] tag onto the
# result — asking the router for an ID such as 0gm-1.0-35b-a3b[1m], which it does not
# serve. The classifier becomes unreachable and auto mode fails closed on every
# non-read-only tool. Check the effective value (local > project > user) before writing.
effective = None
for label, src in (("project .claude/settings.local.json", target),
                   ("project .claude/settings.json", root / ".claude" / "settings.json"),
                   ("user ~/.claude/settings.json", pathlib.Path.home() / ".claude" / "settings.json")):
    try:
        m = json.loads(src.read_text()).get("model")
    except Exception:
        continue
    if isinstance(m, str) and m.strip():
        effective = (label, m.strip())
        break
if effective and effective[1].lower().endswith("[1m]"):
    sys.exit(
        'the effective session model is "%s" (from %s).\n'
        "Claude Code copies that [1m] tag onto the model it derives for the auto-mode "
        "safety classifier, producing an ID the 0G router does not serve — every Bash, "
        "git and network action then fails closed. Refusing to write a config that is "
        "known to break. Fix it one of two ways, then re-run this step:\n"
        "  1. run /model and pick the same model without the (1M context) variant, or\n"
        '  2. add "model": "glm-5.2" to .claude/settings.local.json to override it here.'
        % (effective[1], effective[0]))

# The key lands inside the repo, so git must be ignoring these paths before they exist.
# The .bak and .tmp siblings carry the key too — a rule covering only the exact filename
# would leave the backup committable.
if rc == 0:
    rel = target.relative_to(root).as_posix()
    guarded = [rel, rel + ".bak", rel + ".tmp"]
    for path in guarded:
        if git("ls-files", "--error-unmatch", path)[0] == 0:
            sys.exit("%s is tracked by git — adding a key to it would stage a secret. "
                     "Run `git rm --cached %s` first, then re-run this step." % (path, path))
    if any(git("check-ignore", "-q", path)[0] != 0 for path in guarded):
        gi = root / ".gitignore"
        prev = gi.read_text() if gi.is_file() else ""
        with gi.open("a") as f:
            if prev and not prev.endswith("\n"):
                f.write("\n")
            f.write("\n# 0G PC config — contains an API key, never commit\n"
                    ".claude/settings.local.json*\n")
        print("appended .claude/settings.local.json* to", gi)
    still = [path for path in guarded if git("check-ignore", "-q", path)[0] != 0]
    if still:
        sys.exit("git still does not ignore %s — refusing to write a key into a tracked path"
                 % ", ".join(still))

# The fragment this skill owns. Everything else already in the file is left alone.
FRAGMENT = {
    "env": {
        "ANTHROPIC_BASE_URL": "https://router-api.0g.ai",
        "ANTHROPIC_AUTH_TOKEN": key,
        "ANTHROPIC_API_KEY": "",
        "ANTHROPIC_MODEL": "glm-5.2",
        "ANTHROPIC_DEFAULT_FABLE_MODEL": "glm-5.2",
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5.2",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": "0gm-1.0-35b-a3b",
        "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "983616",
    },
    "modelOverrides": {"claude-sonnet-5": "0gm-1.0-35b-a3b"},
    "permissions": {"defaultMode": "acceptEdits"},   # "auto" only if the user chose it in Step 2
}
KNOWN_TOP = {"env", "modelOverrides", "permissions"}
KNOWN_ENV = {
    "ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "ANTHROPIC_MODEL",
    "ANTHROPIC_DEFAULT_FABLE_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL",
    "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL",
    "CLAUDE_CODE_MAX_CONTEXT_TOKENS",
}

# Claude Code ignores keys it does not recognise, silently — a typo here looks like success
# and fails hours later. Catch it before anything reaches disk.
unknown = sorted(set(FRAGMENT) - KNOWN_TOP)
if unknown:
    sys.exit("unknown top-level settings key(s): %s — refusing to write" % ", ".join(unknown))
unknown = sorted(set(FRAGMENT["env"]) - KNOWN_ENV)
if unknown:
    sys.exit("unknown env var(s): %s — refusing to write" % ", ".join(unknown))

# Never clobber a file that will not parse: it may be the user's own project config.
raw = None
cfg = {}
if target.is_file():
    raw = target.read_text()
    try:
        cfg = json.loads(raw)
    except json.JSONDecodeError as e:
        sys.exit("%s is not valid JSON (%s) — refusing to overwrite it; "
                 "fix or move it, then re-run this step" % (target, e))
    if not isinstance(cfg, dict):
        sys.exit("%s does not hold a JSON object — refusing to overwrite it" % target)

for k, v in FRAGMENT.items():
    cfg.setdefault(k, {}).update(v)

text = json.dumps(cfg, indent=2) + "\n"
json.loads(text)          # validate the result in memory, before touching disk

if raw is not None:
    backup = pathlib.Path(str(target) + ".bak")
    backup.write_text(raw)
    print("backed up previous config to", backup)

target.parent.mkdir(parents=True, exist_ok=True)
tmp = pathlib.Path(str(target) + ".tmp")
tmp.write_text(text)
os.replace(tmp, target)   # atomic — a half-written config is never visible

json.loads(target.read_text())   # read-back confirmation
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

- Do not substitute `ANTHROPIC_DEFAULT_SONNET_MODEL` for the `modelOverrides` entry. Claude Code reads that variable first but then checks the value is a model it recognises; a raw 0G model ID fails that check, the resolver returns nothing, and the classifier **silently falls back to the main model** — glm-5.2, a reasoning model, which is the timeout failure all over again. The `modelOverrides` mapping is not subject to that check.
- `CLAUDE_CODE_MAX_CONTEXT_TOKENS` is required; without it a 1M-context model is treated as 200K and compacts early. The value `983616` is 960K — deliberately just under every candidate's real ceiling (glm-5.2 1048576, kimi-k3 1048576, glm-5.3 / qwen3.8-max / minimax-m3 1000000), so one number is safe for both paths. Verify against Step 1's live list if adding a model.
- `modelOverrides["claude-sonnet-5"]` is what actually pins the permission gate. On a third-party router the auto-mode classifier resolves through the **Sonnet** tier: `ANTHROPIC_DEFAULT_SONNET_MODEL` if set and available, otherwise the built-in `claude-sonnet-5` mapped through `modelOverrides`. Leave this entry pointing at `0gm-1.0-35b-a3b`.
- Second-order hazard worth knowing: when the main model resolves to the fable or mythos tier, the classifier falls back to the **Opus** tier instead — which this config points at `glm-5.2`, a reasoning model. That is the ~950-token reasoning pass that times out and produces "model is temporarily unavailable" on every gated action. Another reason not to leave a `[1m]`/fable session model in play.
- The `[1m]` guard reads the config files only. It cannot see a `claude --model 'something[1m]'` launched by hand — if the symptom appears anyway, check how the session was started.
- The script validates **before** writing, not after: unknown top-level keys and unknown env var names abort the run, an unparseable existing file is never overwritten, and the write itself goes through a temp file plus `os.replace` so a half-written config is never visible. Validating after the write is useless — by then the user's previous config is already gone.
- If using a different anthropic-format main model, change only the three main-model lines; keep the gate entries as-is.
- **Scope:** a project-level file applies only inside that directory — that is the default and the recommended shape. If the user asked for every-project scope at question 3, write the same JSON to `~/.0g/0g-settings.json` instead: it lives outside every repo, so the gitignore guard is unnecessary and the key never sits in a working tree. Rollback is still one `rm`. Either way `~/.claude/settings.json` is never written — hard rule 1.

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
  "permissions": { "defaultMode": "acceptEdits" }
}
```

`ANTHROPIC_AUTH_TOKEN` is a placeholder — the local proxy does not authenticate; the real key lives only in the `ZG_API_KEY` environment variable of the proxy terminal.

### Step 6 — Hand off: restart + verify

Tell the user, verbatim in substance:

1. The config is already complete — it lives in `.claude/settings.local.json` in this project, the key was injected from `ZG_API_KEY` in Step 5, and the `HTTP 200` probe confirmed it works. Nothing is left to fill in by hand, and their global `~/.claude/settings.json` was not touched. **To roll back: `rm .claude/settings.local.json`.** (Path B: the token in that file stays `sk-anything`; the real key lives only in the proxy terminal's `export ZG_API_KEY=…`.)
2. Restart Claude Code (close all windows, open a new terminal, run `claude`). Config changes do not affect the current session.
3. In the new session, type `/status` — the Base URL must show `https://router-api.0g.ai` (Path A) or `http://127.0.0.1:4000` (Path B). The startup warning `[claude-code:unrecognized_model]` is harmless.
4. Ask the new session to run one Bash action, e.g. "use Bash to run `echo ok > probe.txt && cat probe.txt`". Under `acceptEdits` it should prompt for confirmation and then succeed — that exercises the model, not the classifier. If the user chose `auto` in Step 2, it should instead run without a prompt and without a "temporarily unavailable" error; that is the check that proves the gate config in Step 5A is right, and it is the only way to know before trusting `auto`.

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
| Auto mode: "xxx is temporarily unavailable, cannot determine the safety of …" | Read the model name in the message — it names the classifier model, and the fix follows from it. Gate model wrong: point `modelOverrides["claude-sonnet-5"]` at `0gm-1.0-35b-a3b` (hard rule 4 — Sonnet tier, not Haiku). |
| That message names a model with a `[1m]` suffix (e.g. `0gm-1.0-35b-a3b[1m]`) | The session model carries `[1m]` and Claude Code copied the tag onto the derived classifier model; the router does not serve that ID. Drop the tag: `/model` without the (1M context) variant, or `"model": "glm-5.2"` in `.claude/settings.local.json`. The Step 5A writer refuses to run while this is in place. |
| That message names your main model (e.g. `glm-5.2`) | The Sonnet-tier resolution returned nothing and the classifier fell back to the main model — either `ANTHROPIC_DEFAULT_SONNET_MODEL` is set to an unrecognised ID (remove it), or a fable/mythos main model sent the classifier to the Opus tier, which this config points at glm-5.2. |
| 401 | Key wrong or expired. Path A: re-run Step 4's probe, re-export a fresh key, re-run the Step 5A writer, and re-run the `HTTP 200` check before handing off. Path B: `ZG_API_KEY` not exported in the proxy terminal. A 401 also takes down the auto-mode classifier, so fix this before diagnosing any gate symptom. |
| Model not found | Typo vs the Step 1 list, or (Path B) model missing from `model_list`. |
| LiteLLM 404 "page not found" | Model prefix written as `openai/`; must be `hosted_vllm/`. |
| Config edits ignored | Old session still running; or `claude` was launched from a directory other than the project holding `.claude/settings.local.json` (project config is scoped to that directory by design — either run the skill in the other project, or switch to the every-project scope from Step 2 question 3); or leftover `ANTHROPIC_*` in the global `env` or the shell — re-run Step 3. |
