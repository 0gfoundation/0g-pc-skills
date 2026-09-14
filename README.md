# 0G PC Skills

Point **Claude Code** and **Codex** at [0G Private Computer](https://pc.0g.ai) (`router-api.0g.ai`) — TEE-backed inference, OpenAI/Anthropic-compatible. For Claude Code it is one command.

The config in [`configs/`](configs/) is an ordinary file: readable, diffable, and **carrying no credentials**, so a team can commit it and each person brings their own key. Your key goes in a second file next to it, mode 600 and git-ignored. Your global `~/.claude/settings.json` is never written — [what is and isn't touched](docs/claude-code.md#what-is-and-isnt-touched).

## Set up — Claude Code

Needs a 0G key from [pc.0g.ai](https://pc.0g.ai) → Dashboard → API Keys. It installs `claude` for you if you don't have it.

### User workflow

**Run this from the project you want on 0G.** It writes into that folder and nowhere else, so where you run it is the one thing that matters.

```bash
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/install.sh | bash -s claude --key sk-…
```

The Quick Start card on [pc.0g.ai](https://pc.0g.ai) hands you the same command with your key
already in it, shortened to `https://pc.0g.ai/install`. Same script, same arguments — copy
whichever you have in front of you.

Then start Claude Code — **any terminal, no export**:

```bash
claude
```

Run `/status` if you want to see it: the Base URL should read `https://router-api.0g.ai`. That is the whole setup. It arrives working, on `glm-5.3`, and the startup line `[claude-code:unrecognized_model]` is expected — Claude Code simply doesn't know 0G's model names.

The installer checks your key against the router before claiming success, so a rejected key says so straight away instead of surfacing later as a failure to start. An empty balance is reported as its own case: the key is fine, and nothing about the config needs changing.

Two notes on the key. It lands in `.claude/settings.local.json` — mode 600, added to `.gitignore`, and never in the file you commit. And it is on the command line, so it enters your shell history; `--key -` prompts for it instead, with echo off.

Another project? Run it there too. macOS and Linux; on Windows use WSL or Git Bash.

### Then what

| You want | Do this |
|---|---|
| a different tier, without restarting | `/model` — Opus and Fable are `glm-5.3`, Sonnet and Haiku `0gm-1.0-35b-a3b`. **Never pick a "(1M context)" entry:** [it breaks every Bash, git and network call](docs/claude-code.md#dont-pick-a-1m-context-entry). |
| a different main model | Edit four fields and restart — [ask the router which ones qualify, and take the ceiling it gives you](docs/claude-code.md#ask-the-router-dont-trust-a-list). |
| a model the router only serves in OpenAI format | It cannot reach Claude Code directly — [it needs the LiteLLM bridge](docs/claude-code.md#openai-only-models-need-the-bridge). Which models those are changes; ask the router rather than a list. |
| to confirm you are really on 0G | `curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/check-0g.sh \| sh` — it reads the effective model, the permission gate and the context ceiling, and says nothing when all three are right. |
| out | `curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/install.sh \| bash -s claude --uninstall`, then restart. It restores whatever `.claude/settings.json` was there before, and takes your key back out of `settings.local.json` — so there is nothing to unset [and nothing to tidy up by hand](docs/claude-code.md#going-back-to-anthropic). |

If you plan to edit the file, [what it contains](docs/claude-code.md#what-the-config-file-contains) is worth two minutes first.

## Set up — Codex

Codex cannot reach the 0G router directly — it speaks only the Responses API, which the router does not serve — so a local LiteLLM bridge translates. The bridge listens on `http://127.0.0.1:4000`, which is the address the profile points at; if that port is already taken, change it in both places.

That bridge makes this the heavier of the two paths, and in two more ways besides: **every launch needs `--profile`**, and **Codex has no per-project configuration**, so unlike the Claude Code setup this cannot be kept inside one folder.

### User workflow

Needs `codex` (`npm install -g @openai/codex`) and [`uv`](https://docs.astral.sh/uv/) — `uv` is what runs the LiteLLM bridge, though `pip` works too. Same 0G key as above.

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

## The skills

Three slash commands for Claude Code, one job each. They are not a gentler way to run the command
above — `/0g-pc-switch-model` and `/0g-pc-uninstall` do things no curl in this README does.

| Command | What it does |
|---|---|
| `/0g-pc-setup` | First-time setup: shows what the router actually serves, with the TEE tier and whether the model takes images, then hands you the install command to run yourself |
| `/0g-pc-switch-model` | Changes the model, moving the context ceiling with it and leaving the permission gate alone |
| `/0g-pc-uninstall` | Puts the project back, telling you first what it will restore and what it will remove |

**They need a Claude Code that already starts.** A skill runs inside a session, so it cannot
rescue one that will not open — if you land on `Not logged in`, re-run the installer from the
[setup section](#set-up--claude-code) instead. (`/login` does not fix that one: it authenticates
against Anthropic, and that token is no use once the base URL points at 0G.)

Install all three:

```bash
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/install.sh | bash -s skills
```

Same script as the setup command, and the only subcommand that writes outside a project — the
skills go in `~/.claude/skills`, where Claude Code looks for them. It takes no key, and they
register without a restart. `bash -s skills --uninstall` removes them again.

**If you installed the old `0g-pc-model-config-claude`, remove it.** Deleting it here does not
delete it from your machine, and the copy you have competes with these three for the same
requests — while still teaching a setup that no longer works, one that ends at `Not logged in`.

```bash
rm -rf ~/.claude/skills/0g-pc-model-config-claude
```

**Codex** is a separate skill and a separate path — install it, then say **"set up 0G PC in Codex"**.

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
