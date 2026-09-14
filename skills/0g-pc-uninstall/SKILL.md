---
name: 0g-pc-uninstall
argument-hint: ""
description: Take this project off 0G Private Computer and back onto the normal Anthropic API, restoring whatever Claude Code configuration was there before. Use when the user wants to stop using 0G in a project, undo the setup, or return to their ordinary Claude Code. Triggers include "不用 0G 了", "退回原生", "退回原来的 API", "卸载 0G", "关掉 0G", "撤销 0G 配置", "uninstall 0G", "turn 0G off", "go back to Anthropic", "back to the normal API". Not for switching between 0G models and not for setting 0G up.
---

# Take this project off 0G

One job: return `<project>/.claude/` to the state it was in before 0G arrived.

If the user wants a *different* 0G model rather than no 0G at all, that is
`/0g-pc-switch-model` — say so and stop. People reach for "undo" when they mean "change", and
uninstalling to reinstall loses their key for no reason.

## Hard rules

1. **Only this project's `.claude/`.** Never delete or rewrite `~/.claude/settings.json`. The
   user's global file holds their hooks, plugins, status line and `/model` choice, and it has
   nothing to do with 0G.
2. **Removing the key is irreversible, so confirm before you start.** The key lives in
   `<project>/.claude/settings.local.json`. Once it is out, it is out — 0G keys are shown at
   creation and not retrievable afterwards, so getting it back means issuing a new one at
   pc.0g.ai. Show what is about to change, wait for an answer, and only then run anything.
3. **Let the installer do the removing.** Run `install.sh --uninstall`; do not compose your own
   `rm`. The removal has moving parts that live in that script — restoring a backup, taking one
   field out of `settings.local.json` without disturbing the rest, pulling its own block out of
   `.gitignore`. A hand-written `rm` skips all three and silently does more damage than the
   install ever did.
4. **Nothing takes effect until the next launch.** Finish by telling the user to restart.
5. **Every place the user has to decide is a tool call, not a sentence.** This file is loaded
   into whatever model drives the session, which in a project on 0G is a 0G model rather than
   Claude. "Ask the user first" written as prose reads as narration and gets walked past — which
   here means deleting a key nobody agreed to delete. Use AskUserQuestion and let it block.

## 1 — Say exactly what will happen

The removal is not "delete two files". What it does depends on what the install found when it
arrived, so read the project and report rather than guess:

```bash
python3 - <<'PY'
import json, pathlib

S = pathlib.Path(".claude/settings.json")
L = pathlib.Path(".claude/settings.local.json")
B = pathlib.Path(".claude/settings.json.0g-backup")

if not S.exists() and not L.exists():
    print("nothing to undo - this project is not on 0G")
    raise SystemExit(0)

if B.exists():
    print("settings.json      -> RESTORED to the file that was here before 0G")
    print("                      (anything changed in the 0G config since, including a")
    print("                       model switch, goes away with it)")
elif S.exists():
    print("settings.json      -> DELETED (there was no config here before 0G)")

if L.exists():
    try:
        doc = json.loads(L.read_text())
    except Exception:
        doc = {}
    env = dict(doc.get("env") or {})
    env.pop("ANTHROPIC_AUTH_TOKEN", None)
    rest = {k: v for k, v in doc.items() if k != "env"}
    if env or rest:
        keep = sorted(list(rest) + ["env." + k for k in env])
        print("settings.local.json-> KEPT, key removed; your own settings stay:", ", ".join(keep))
    else:
        print("settings.local.json-> DELETED (it held nothing but the key)")

print()
print("YOUR 0G KEY IS REMOVED EITHER WAY. 0G shows a key once, at creation - if you")
print("want this project back on 0G later you will need to issue a new one at")
print("https://pc.0g.ai -> Dashboard -> API Keys")
PY
```

If it prints `nothing to undo`, say so and stop. There is nothing here to remove and no
confirmation to ask for.

## 2 — Get a real answer

Put that output to the user with **AskUserQuestion**. Not a summary of it — the lines themselves,
so they can see whether their own settings survive and that the key does not.

**Run nothing until the answer comes back.** If they decline, stop there and change nothing.

## 3 — Hand it to the installer

```bash
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/install.sh | bash -s claude --uninstall
```

This one you may run yourself: it carries no key and takes no key. It prints what it did.

If `curl` cannot reach GitHub, stop and say so rather than improvising the removal by hand —
hard rule 3 is about exactly this moment.

## 4 — Hand off

Tell the user to restart Claude Code. The running session keeps the 0G configuration until it
exits.

**There is nothing to unset.** This used to be the step everyone missed, back when the key lived
in the shell: it survived the deletion of the config, and Claude Code kept sending it to
`api.anthropic.com`, where it is not valid — an authentication failure that reads like a broken
account. The key travels with the file now. If the user still sees

```
⚠ another auth source is set and takes precedence over your claude.ai login
```

then something really is exporting `ANTHROPIC_AUTH_TOKEN` — an old `.zshrc` line, most likely,
left over from the way this used to be set up.

## When it goes wrong

| Symptom | Cause → fix |
|---|---|
| Claude Code still talks to 0G | The old session is still running. Restart it. |
| `/status` still shows the 0G base URL after a restart | `claude` was launched from a different directory, or a parent directory also has a `.claude/settings.json`. Project config is scoped to the folder it sits in. |
| `nothing to undo`, but the user is sure they installed it | They installed it in a different project. `install.sh` writes into the directory it is run from and nowhere else. |
| The previous config came back but looks wrong | The backup is what was there before the install, byte for byte. If it looks unfamiliar, it predates 0G — this skill did not write it. |
