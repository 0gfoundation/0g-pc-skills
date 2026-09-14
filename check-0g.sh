#!/bin/sh
# check-0g.sh — sanity-check a 0G PC config for Claude Code.
# Run from the project that holds .claude/settings.json. Silent when healthy.
exec python3 - "$@" <<'PY'
import json, os, pathlib, subprocess, sys, urllib.request

REASONING = {"glm-5.2", "glm-5.3", "glm-5", "kimi-k3", "deepseek-v4-pro", "minimax-m3"}
# These are main-model candidates. The gate must not be one of them — it is checked below.
CREDENTIALS = {"ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY"}
LOCAL = ".claude/settings.local.json"
problems = []

def git(*args):
    try:
        return subprocess.run(("git",) + args, capture_output=True, text=True, timeout=5)
    except Exception:
        return None

def load(p):
    try:
        return json.loads(pathlib.Path(p).expanduser().read_text())
    except Exception:
        return {}

cfg = load(".claude/settings.json")
if not cfg:
    sys.exit("no .claude/settings.json here — run this from the project you configured")
env = cfg.get("env", {})

# .claude/settings.local.json is where the key lives, so credentials there are expected and
# not reported. Anything else in it shadows the project settings checked below — local is
# loaded after project and wins — and a config that "does not apply" is usually this.
local_path = pathlib.Path(LOCAL)
shadow = load(LOCAL)
shadowing = [k for k in ("modelOverrides", "permissions") if k in shadow]
shadowing += [f"env.{k}" for k in sorted(set(shadow.get("env", {})) - CREDENTIALS)]
if shadowing:
    problems.append(f'{LOCAL} also sets {", ".join(shadowing)} and takes precedence over the\n'
                    '  project settings checked here — Claude Code loads local after project.\n'
                    '  Credentials belong there; configuration does not.')

# 0 — the key: present, private, and out of reach of git
key_in_file = any(shadow.get("env", {}).get(k) for k in CREDENTIALS)
key_in_shell = any(os.environ.get(k) for k in CREDENTIALS)

if not local_path.exists():
    if not key_in_shell:
        problems.append(f'no credential anywhere: {LOCAL} does not exist and ANTHROPIC_AUTH_TOKEN\n'
                        '  is not exported either. Claude Code will fall back to your Anthropic login\n'
                        '  and send it to the 0G router, which reads as a broken account.')
elif not key_in_file:
    problems.append(f'{LOCAL} exists but carries no credential. Either put the key there or\n'
                    '  delete the file — an empty one only shadows the project settings.')

if local_path.exists():
    mode = local_path.stat().st_mode & 0o777
    if mode & 0o077:
        problems.append(f'{LOCAL} is mode {mode:03o} — readable by other accounts on this machine.\n'
                        f'  It holds your key. Fix: chmod 600 {LOCAL}')

    # .gitignore does nothing for a file git already tracks, so check tracking first —
    # that is the case where the key is one commit away and the usual fix looks applied.
    if (r := git("rev-parse", "--is-inside-work-tree")) and r.returncode == 0:
        if (t := git("ls-files", "--error-unmatch", LOCAL)) and t.returncode == 0:
            problems.append(f'{LOCAL} is TRACKED BY GIT — your key is one commit from being pushed.\n'
                            '  Adding it to .gitignore will not help; git ignores nothing it already tracks.\n'
                            f'  Fix: git rm --cached {LOCAL}   (then confirm it is in .gitignore)')
        elif (g := git("check-ignore", "-q", LOCAL)) and g.returncode != 0:
            problems.append(f'{LOCAL} is not ignored by git — the next `git add -A` picks up your key.\n'
                            f'  Fix: echo {LOCAL} >> .gitignore')

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
                f'  Fix: /model without the (1M context) variant, or "model": "glm-5.3" in the project config.')
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
