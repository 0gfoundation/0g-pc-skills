#!/bin/sh
# check-0g.sh — sanity-check a 0G PC config for Claude Code.
# Run from the project that holds .claude/settings.json. Silent when healthy.
exec python3 - "$@" <<'PY'
import json, os, pathlib, sys, urllib.request

REASONING = {"glm-5.2", "glm-5.3", "glm-5", "kimi-k3", "deepseek-v4-pro", "minimax-m3"}
problems = []

def load(p):
    try:
        return json.loads(pathlib.Path(p).expanduser().read_text())
    except Exception:
        return {}

cfg = load(".claude/settings.json")
if not cfg:
    sys.exit("no .claude/settings.json here — run this from the project you configured")
env = cfg.get("env", {})

# .claude/settings.local.json is loaded after project settings and wins. A config that
# "does not apply" is usually this, and nothing else reports it.
shadow = load(".claude/settings.local.json")
overlap = [k for k in ("env", "modelOverrides", "permissions") if k in shadow]
if overlap:
    problems.append(f'.claude/settings.local.json also sets {", ".join(overlap)} and takes precedence\n'
                    '  over the project settings checked here — Claude Code loads local after project.')

# 1 — a [1m] session model poisons the classifier derived from the Sonnet tier
for label, path in (("project local", ".claude/settings.local.json"),
                    ("project", ".claude/settings.json"),
                    ("user", "~/.claude/settings.json")):
    m = load(path).get("model")
    if isinstance(m, str) and m.strip():
        if m.strip().lower().endswith("[1m]"):
            problems.append(
                f'model "{m}" (from {label}) carries [1m]. Claude Code copies that tag onto the\n'
                f'  classifier it derives from the Sonnet tier, asking the router for an ID it does not\n'
                f'  serve; auto mode then refuses every non-read-only tool while chat keeps working.\n'
                f'  Fix: /model without the (1M context) variant, or "model": "glm-5.2" in the project config.')
        break

# 2 — the permission gate
gate = (cfg.get("modelOverrides") or {}).get("claude-sonnet-5")
if not gate:
    problems.append('modelOverrides["claude-sonnet-5"] is unset — the auto-mode gate resolves through the\n'
                    '  Sonnet tier, so leaving it out sends the safety call to whatever Claude Code picks.')
elif gate in REASONING:
    problems.append(f'the gate modelOverrides["claude-sonnet-5"] points at "{gate}", a reasoning model.\n'
                    '  Every gated action becomes a long reasoning pass that times out. Use 0gm-1.0-35b-a3b.')

# 3 — base URL
base = env.get("ANTHROPIC_BASE_URL", "")
if "router-api.0g.ai" not in base and "127.0.0.1" not in base:
    problems.append(f'ANTHROPIC_BASE_URL is "{base}" — expected the 0G router or a local bridge.')

# 4 — context ceiling against the live model list
model = env.get("ANTHROPIC_MODEL")
ceiling = env.get("CLAUDE_CODE_MAX_CONTEXT_TOKENS")
if model and ceiling:
    try:
        with urllib.request.urlopen("https://router-api.0g.ai/v1/models", timeout=10) as r:
            live = {m["id"]: m.get("context_length") for m in json.load(r)["data"]}
    except Exception:
        live = {}
    real = live.get(model)
    if real and int(ceiling) > real:
        problems.append(f'CLAUDE_CODE_MAX_CONTEXT_TOKENS is {ceiling} but {model} accepts {real}.\n'
                        f'  Long sessions fail on context length, hours after the switch that caused it.\n'
                        f'  Use {int(real * 15 // 16)} or lower.')
    elif not live:
        print("note: router unreachable, context ceiling not checked", file=sys.stderr)

if problems:
    for p in problems:
        print("✗ " + p, file=sys.stderr)
    sys.exit(1)
PY
