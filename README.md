# 0G PC Skills

Ready-made configuration that points **Claude Code** and **Codex** at [0G Private Computer](https://pc.0g.ai) (`router-api.0g.ai`) — TEE-backed inference with OpenAI/Anthropic-compatible APIs.

Setup is: export your key, download a config file, restart. The config files live in [`configs/`](configs/) — they are ordinary files you can read, diff, and edit. Two Agent Skills ([`skills/`](skills/)) can walk you through the same steps in a session if you prefer that to reading this page.

- **Before you start** — [what you need](#what-you-need) · [where your key lives](#your-key-never-goes-in-a-file) · [what gets written](#what-is-and-isnt-touched)
- **Set it up** — [Claude Code](#set-up--claude-code) · [Codex](#set-up--codex) · [or let a skill do it](#using-the-skills-instead)
- **Already set up** — [Claude Code reference](docs/claude-code.md) for switching models, the 1M-context trap and the bridge; [Codex reference](docs/codex.md) for the `--profile` flag and reading the banner
- **Changing this repo** — [the verification protocols](verification/)

## What you need

This repo configures clients you already have; it does not install them. You only need the row for the client you are setting up — the two setups are independent.

| Check | Needed for | If missing |
|---|---|---|
| `claude --version` | the Claude Code setup | `npm install -g @anthropic-ai/claude-code` |
| `codex --version` | the Codex setup | `npm install -g @openai/codex` |
| `uv --version` | the Codex setup — it is what runs the LiteLLM bridge | [docs.astral.sh/uv](https://docs.astral.sh/uv/), or use `pip` instead |

Plus a **0G PC inference API key** (`sk-…`) from [pc.0g.ai](https://pc.0g.ai) → Dashboard → API Keys. Do not put it in a file inside a repository, where one `git add -A` can commit it — the next section is where it goes instead.

## Your key never goes in a file

The config files carry **no credentials**. Your key lives in a shell environment variable and nothing else, which is why these files are safe to read, safe to diff, and safe to commit — a team can share one config in the repo, and each person brings their own key.

Three variable names, because three different programs read them — but only two of them carry your key:

| Variable | Read by | Value |
|---|---|---|
| `ANTHROPIC_AUTH_TOKEN` | Claude Code | your key |
| `ZG_API_KEY` | the LiteLLM bridge, on its way out to 0G | your key |
| `ZG_LITELLM_KEY` | Codex, talking to the bridge on your own machine | any string — the bridge does not authenticate |

The first two take the same key, so export both at once:

```bash
 export ZG_API_KEY='sk-…'
 export ANTHROPIC_AUTH_TOKEN="$ZG_API_KEY"
```

The leading space keeps them out of your shell history. They last as long as the terminal — a new terminal needs them again.

## What is and isn't touched

**Claude Code** — your global `~/.claude/settings.json` (hooks, plugins, status line, your `/model` choice) is never written. The config goes to `.claude/settings.json` in one project; deleting that file undoes everything.

**Codex** — Codex has no per-project configuration, so this cannot be confined to a folder. Your `~/.codex/config.toml` is never written; what gets added is one profile file plus a bridge directory, and it only applies when you launch with `--profile`. Existing Codex sessions are unaffected.

## Set up — Claude Code

![Claude Code setup: export ANTHROPIC_AUTH_TOKEN in the terminal you will restart in, curl one settings.json into the project, pick a model, then verify with /status and any Bash call](Assets/0g-pc-claude-code-setup.png)

### User workflow

Two steps. The second one is where it goes wrong.

**① Key and config**, from inside the project you want on 0G. One line: `&&` runs it all in this shell, so the export stays put — which is where Claude Code will look for it.

```bash
 export ANTHROPIC_AUTH_TOKEN='sk-…' && mkdir -p .claude && curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/claude/settings.json -o .claude/settings.json
```

Already exported it in this terminal? Drop everything up to the first `&&`.

**② Restart Claude Code** — in that same terminal.

```bash
claude
```

Then run `/status`: the Base URL should read `https://router-api.0g.ai`. That is the whole setup. The config arrives working, on `glm-5.3`, and the startup line `[claude-code:unrecognized_model]` is expected — Claude Code simply doesn't know 0G's model names.

**Step ② is the one people miss.** Your key lives only in the shell you exported it in, so launching Claude Code from a different terminal returns a 401 that reads like a bad key. That is the cost of keeping credentials out of every file: every new terminal needs the export again.

### Then what

| You want | Do this |
|---|---|
| a different tier, without restarting | `/model` — Opus and Fable are `glm-5.3`, Sonnet and Haiku `0gm-1.0-35b-a3b`. **Never pick a "(1M context)" entry:** [it breaks every Bash, git and network call](docs/claude-code.md#dont-pick-a-1m-context-entry). |
| a different main model | Edit three fields and restart — [which models qualify, and the context ceiling that travels with them](docs/claude-code.md#switching-the-main-model). |
| `glm-5.2`, `kimi-k3`, `qwen3.8-max`, `minimax-m3`, `gpt-5.6-*`, `qwen3.8-flash` | These speak OpenAI only and cannot reach Claude Code directly — [they need the LiteLLM bridge](docs/claude-code.md#openai-only-models-need-the-bridge). |
| to confirm you are really on 0G | `curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/check-0g.sh \| sh` — it reads the effective model, the permission gate and the context ceiling, and says nothing when all three are right. |
| out | `rm .claude/settings.json`, then `unset ANTHROPIC_AUTH_TOKEN`, then restart — [the second step is not optional](docs/claude-code.md#going-back-to-anthropic). |

If you plan to edit the file, [what it contains](docs/claude-code.md#what-the-config-file-contains) is worth two minutes first.

## Set up — Codex

![Codex setup: export ZG_API_KEY, pull three files, run the LiteLLM bridge in its own window, launch with --profile every time, then read the banner — model: glm-5.3 means you are on 0G, model: gpt-* means the request went to OpenAI](Assets/0g-pc-codex-setup.png)

Codex cannot reach the 0G router directly — it speaks only the Responses API, which the router does not serve — so a local LiteLLM bridge translates. The bridge listens on `http://127.0.0.1:4000`, which is the address the profile points at; if that port is already taken, change it in both places.

That bridge makes this the heavier of the two paths, and in two more ways besides: **every launch needs `--profile`**, and **Codex has no per-project configuration**, so unlike the Claude Code setup this cannot be kept inside one folder.

### User workflow

**Two terminals, and they stay two.** The bridge occupies one for as long as you use Codex on 0G; Codex itself runs in the other. Close the first and every session in the second stops working.

First, three files — either terminal, they land in your home directory:

```bash
mkdir -p ~/.0g-litellm && curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/codex/litellm-config.yaml -o ~/.0g-litellm/litellm-config.yaml
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/codex/zg_patch.py -o ~/.0g-litellm/zg_patch.py
mkdir -p "${CODEX_HOME:-$HOME/.codex}" && curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/codex/zg-glm53.config.toml -o "${CODEX_HOME:-$HOME/.codex}/zg-glm53.config.toml"
```

**Terminal 1 — the bridge.** Leave it running; the first launch takes a minute or two to install dependencies.

```bash
 export ZG_API_KEY='sk-…'          # your real key — the bridge is what authenticates to 0G
cd ~/.0g-litellm && uvx --from 'litellm[proxy]==1.98.0' litellm --config litellm-config.yaml --port 4000
```

**Terminal 2 — Codex.** This is where you work.

```bash
 export ZG_LITELLM_KEY='sk-anything'    # literal, not a placeholder — the bridge does not authenticate
codex --profile zg-glm53
```

**The two exports are not interchangeable, and neither one travels.** `ZG_API_KEY` carries your real key from Terminal 1 out to 0G; `ZG_LITELLM_KEY` is what Codex hands the bridge on your own machine, which does not check it — `sk-anything` is the literal value, copy it as is. Put either in the wrong terminal and it does nothing at all: the bridge fails to authenticate, or Codex does. And both are ordinary shell variables, so a fresh Terminal 1 tomorrow needs its export again.

Then, every launch, read the `model:` line in the startup banner: your configured model means the profile loaded, `gpt-*` means it was not found and the request went to `api.openai.com` instead ([why that is silent](docs/codex.md#reading-the-model-line)).

### Then what

| You want | Do this |
|---|---|
| a different model | Run the skill again for it — it writes another `zg-<name>.config.toml` alongside the first. Both stay; `--profile` picks between them. |
| your ordinary Codex back | Launch without `--profile`. Nothing to undo, nothing to restart. |
| to work out what went wrong | [Read the `model:` line](docs/codex.md#reading-the-model-line) first — it catches the common case. Then check that Terminal 1 is still up. |
| out | `rm "${CODEX_HOME:-$HOME/.codex}"/zg-glm53.config.toml && rm -rf ~/.0g-litellm`, and Ctrl-C the bridge. |

`codex exec` takes the flag too, and the banner has one more failure mode worth knowing — both in the [Codex reference](docs/codex.md).

## Using the skills instead

If you would rather be walked through it, install the one for your client and ask for it by name. It performs the same steps and explains what each one does.

**Claude Code** — install it, then say **"set up 0G PC"**.

```bash
mkdir -p ~/.claude/skills/0g-pc-model-config-claude && curl -fsSL \
  https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/skills/0g-pc-model-config-claude/SKILL.md \
  -o ~/.claude/skills/0g-pc-model-config-claude/SKILL.md
```

**Codex** — install it, then say **"set up 0G PC in Codex"**.

```bash
mkdir -p ~/.codex/skills/0g-pc-model-config-codex && curl -fsSL \
  https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/skills/0g-pc-model-config-codex/SKILL.md \
  -o ~/.codex/skills/0g-pc-model-config-codex/SKILL.md
```

**Update:** re-run the curl. **Uninstall:** `rm -rf` the skill directory.

## Verifying a change

If you are changing this repo rather than using it, [`verification/`](verification/) holds the two manual protocols — one per client — that check a config end to end on a real machine: what to run, what each step should print, and how to read the failure modes. They exist because the interesting failures here (a poisoned classifier, a silently redirected Codex request) look like something other than what they are.

## Live model list

Worth checking before picking a model, since the tables in the [Claude Code reference](docs/claude-code.md#switching-the-main-model) age:

```bash
curl -s https://router-api.0g.ai/v1/models
```
