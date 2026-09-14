# Claude Code on 0G — reference

Everything worth knowing once the setup works. Setting it up in the first place is [three steps in the README](../README.md#set-up--claude-code).

Config is read at launch, so nothing changes in a session that was already open. Close it, open a new terminal in the same project, run `claude`, and check `/status` — the Base URL should read `https://router-api.0g.ai`.

## What is and isn't touched

Your global `~/.claude/settings.json` — hooks, plugins, status line, your `/model` choice — is **never written**. Two files land in the project you ran the installer from, and nothing outside it changes.

`.claude/settings.json` holds the configuration and **no credentials**, which is what makes it safe to read, diff, and commit: a team shares one config and each person brings their own key.

`.claude/settings.local.json` holds your key and nothing else. Claude Code loads it after the project settings, so it is the natural home for something personal. It is created mode 600 and added to `.gitignore`; the installer refuses to write it at all if git is already tracking that path, because `.gitignore` does nothing for a file git already tracks and the key would be one commit from being pushed.

The key being in a file rather than a shell variable is what makes a **new terminal work**. Nothing to export, nothing to remember. It costs you a credential on disk in the project folder — 600 and git-ignored, but on disk.

Codex differs: it has no per-project configuration, so [that setup cannot be confined to a folder](codex.md).

## What the config file contains

`.claude/settings.json`, in the project:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://router-api.0g.ai",
    "ANTHROPIC_API_KEY": "",                 // blanked so your exported token is the one used
    "ANTHROPIC_MODEL": "glm-5.3",            // the main model — text only, see below
    "ANTHROPIC_DEFAULT_FABLE_MODEL": "glm-5.3",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5.3",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "0gm-1.0-35b-a3b",
    "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "983616"
  },
  "fallbackModel": ["0gm-1.0-35b-a3b"],      // used when glm-5.3 is overloaded or unavailable
  "modelOverrides": { "claude-sonnet-5": "0gm-1.0-35b-a3b" },
  "permissions": { "defaultMode": "acceptEdits" }
}
```

Every tier points at a 0G model, so whichever one Claude Code reaches for, the request stays on 0G. No credential appears anywhere in this file — that lives in `.claude/settings.local.json` beside it.

### The main model is text only

`glm-5.3` does not accept images. Pasting a screenshot into a session on the shipped config will fail — and `fallbackModel` will not rescue it, because that fallback fires on *overloaded or unavailable*, which an unsupported content type is not.

On the direct path, the models that do accept images are `0gm-1.0-35b-a3b` — which runs in an enclave — and the `claude-*` family, which does not (see [the TEE column](#what-the-tee-column-means)). For image **and video**, `qwen3.8-flash` handles both, but it speaks OpenAI only and therefore needs [the bridge](#openai-only-models-need-the-bridge).

### What the fallback does and does not cover

`fallbackModel` takes an **array** — `"fallbackModel": "x"` is rejected with `Expected array`. It is tried when the primary model is overloaded or unavailable, which is worth having on a third-party router: a wobble no longer ends the session.

Two limits worth knowing:

- **It is not a capability net.** A request the primary model cannot serve — an image, say — is an error about the request, not about availability, so the chain does not advance.
- **`CLAUDE_CODE_MAX_CONTEXT_TOKENS` is one global number, not per model.** It is set for the shipped main model, while the fallback accepts a fraction of that. A session that has already grown past that will not be rescued either; the fallback helps early, not late.

This is the project settings file, meant to be committed. If you also keep a personal `.claude/settings.local.json`, that one wins — Claude Code loads `local` after `project` — so a setting that seems not to apply is worth checking there first.

## Switching the main model

Edit `.claude/settings.json` and restart. Three fields move together:

```json
"ANTHROPIC_MODEL": "deepseek-v4-flash",
"ANTHROPIC_DEFAULT_FABLE_MODEL": "deepseek-v4-flash",
"ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-flash",
```

Leave `ANTHROPIC_DEFAULT_HAIKU_MODEL` and `modelOverrides.claude-sonnet-5` alone. The second one is the permission gate: point it at a reasoning model and every Bash, git and network call starts timing out under auto mode.

### Ask the router, don't trust a list

There used to be a table here. It aged faster than anyone reading it would expect: eleven models
became eighteen and then sixteen inside a single day, and three of the context lengths it quoted
had already moved. A list of models in a file is a claim about a service that changes without
telling you, so this asks the service instead:

```bash
curl -s https://router-api.0g.ai/v1/models | python3 -c "
import json,sys
rows=[m for m in json.load(sys.stdin)['data'] if 'anthropic' in (m.get('supported_formats') or [])]
for m in sorted(rows, key=lambda x:-(x.get('context_length') or 0)):
    c=m.get('context_length') or 0
    v=m.get('verifiability') if m.get('tee_attested') else None
    tee={'TeeML':'TEE, model in enclave','TeeTLS':'TEE, proxied upstream'}.get(v,'NO TEE')
    print(f\"{m['id']:22} ctx={c:>8}  ceiling={c*15//16:>8}  {tee}\")"
```

Anything it prints can be swapped in by editing alone. Anything it does not print speaks OpenAI
only, and no amount of editing reaches it — it needs [the bridge](#openai-only-models-need-the-bridge).

**Use the `ceiling` column.** It is the model's context length times 15/16, and it belongs in
`CLAUDE_CODE_MAX_CONTEXT_TOKENS` in the same edit that changes the model. This is the part that
gets left behind, and it fails in the least helpful way available: the config ships a ceiling
suited to a large model, so moving to a smaller one breaks nothing until the session grows long —
an error hours later, with the model switch the last thing you would suspect.

Or run [`check-0g.sh`](../check-0g.sh) after any change — it reads the effective model, the gate
and the ceiling, and says nothing when everything is fine:

```bash
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/check-0g.sh | sh
```

Whichever model you pick, don't append `[1m]` to its name — same failure as below.

### What the TEE column means

It has three values, and the first two are not the same thing:

| Value | What runs where |
|---|---|
| `TEE, model in enclave` | The model itself runs inside the enclave and signs its responses. The strongest guarantee the router offers, and what `glm-5.3` — the model this config ships with — gives you. |
| `TEE, proxied upstream` | A broker runs inside an enclave and relays to a centralised upstream provider. The link is attested; the model weights are not in the enclave. |
| `NO TEE` | No attestation at all. These work fine and are reachable like any other — they simply carry none of the privacy guarantee you came here for. |

The distinction is worth the paragraph because it is invisible at the point of use: every model
on the list answers the same way, and nothing in a session tells you which tier you are on. The
`claude-*` family is the whole of the third row — convenient, 1M context, and outside the
guarantee.

## Don't pick a "(1M context)" entry

`/model` moves between the tiers above with no restart. What it must not move to is a "(1M context)" variant. Claude Code derives the auto-mode safety classifier from the Sonnet tier and copies your main model's `[1m]` tag onto the result, asking the router for `0gm-1.0-35b-a3b[1m]` — an ID it does not serve. The classifier becomes unreachable and auto mode fails closed on every Bash, git and network call, while chat keeps working, so it reads like the model is fine and the tools are broken.

Your `/model` choice is remembered in `~/.claude/settings.json`, so this survives restarts and follows you into other projects. The skill will then refuse to write a new config until you clear it — that refusal is the guard working, not a bug. Fix it with `/model` and a plain (non-1M) entry.

## OpenAI-only models need the bridge

`glm-5.2`, `kimi-k3`, `qwen3.8-max`, `minimax-m3`, `gpt-5.6-*` and `qwen3.8-flash` cannot reach Claude Code directly. They need the same local LiteLLM bridge the Codex setup uses — install the two bridge files and start it in its own terminal:

```bash
mkdir -p ~/.0g-litellm
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/codex/litellm-config.yaml -o ~/.0g-litellm/litellm-config.yaml
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/codex/zg_patch.py -o ~/.0g-litellm/zg_patch.py
cd ~/.0g-litellm && export ZG_API_KEY='sk-…'          # your 0G key, pasted
uvx --from 'litellm[proxy]==1.98.0' litellm --config litellm-config.yaml --port 4000
```

Paste the key rather than reaching for a shell variable: since the installer put it in a file, there is no `ANTHROPIC_AUTH_TOKEN` in your environment to borrow. `cat .claude/settings.local.json` if you need to see it.

Then two changes in `.claude/settings.json`: `ANTHROPIC_BASE_URL` to `http://127.0.0.1:4000`, and the three model fields to the model you want. The bridge does not authenticate, so the credential in `settings.local.json` can be any string in this mode — the real key is the one `ZG_API_KEY` carries into the bridge.

## Going back to Anthropic

One step, then restart:

```bash
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/install.sh | bash -s claude --uninstall
```

It puts the project back the way it found it. A `.claude/settings.json` that was there before the install is restored from the backup it kept; if there was none, the file is removed. `settings.local.json` loses the key and nothing else, so personal settings you keep there survive — the file itself stays if anything is left in it. Its own block comes out of `.gitignore`, leaving the rest alone.

**Do not reach for `rm -rf .claude` instead.** It takes the backup with it, along with any config that was in that folder before 0G ever arrived.

**There is nothing to unset.** This used to be the step everyone missed: the key lived in the shell, survived the deletion of the config, and Claude Code kept sending it — to `api.anthropic.com`, where it is not valid. The result was an authentication failure that reads as a broken account:

```
⚠ another auth source is set and takes precedence over your claude.ai login
```

That failure mode is gone, because the uninstall takes the key out of the file. If you still see that message, something really is exporting `ANTHROPIC_AUTH_TOKEN` in your shell — an old `.zshrc` line, most likely.

## When everything claims the model is unavailable

An empty 0G balance does not announce itself as a billing problem. It arrives as a 402 buried under whatever failed first — and what fails first is usually the permission gate:

```
0gm-1.0-35b-a3b is temporarily unavailable, so auto mode cannot determine the safety of Bash
Switched to … because glm-5.3 returned an error that could not be retried (402 … "Insufficient balance")
API Error: 402 Insufficient balance
```

Read top to bottom and you start editing the gate config, which is fine. Check the balance first: https://pc.0g.ai/dashboard/overview

`check-0g.sh` cannot catch this — it runs without a key, and the balance endpoint rejects inference keys by design, so there is no way for it to ask.
