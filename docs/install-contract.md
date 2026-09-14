# `pc.0g.ai/install` — contract for the portal

What the Quick Start card needs from this repository, and what this repository promises not to
change under it. Written for whoever builds the card in `0g-compute-new`.

Scope: the **Claude Code** tab. The other three tabs are covered at the end, because what they
should show is a decision this contract has to make rather than defer.

## The command

```
curl -fsSL https://pc.0g.ai/install | bash -s claude --key <KEY>
```

Substitute `<KEY>` with the signed-in user's key. Nothing else in the string varies: not the
client word, not the flag order, not the URL.

The key is a plain command-line argument. It must be a single shell word; the keys the dashboard
issues (`sk-` + base62) always are, so no quoting is required, and adding quotes is also safe.
If the key format ever grows a character that needs quoting, tell us before shipping it — the
installer rejects anything not starting with `sk-` and that check would need to move first.

## Serving the URL

`pc.0g.ai/install` must return the contents of [`install.sh`](../install.sh) with a
`text/plain`-ish content type. Two ways:

**302 to the raw file (recommended).**

```
https://pc.0g.ai/install  →  302  →
https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/install.sh
```

`curl -fsSL` follows redirects, so this works as-is. The portal ships nothing and cannot drift
from what this repository tested.

**Copy at build time (acceptable).** Fetch `install.sh` during the portal's build and serve it
from the portal's own origin. Removes the GitHub dependency at request time; in exchange the
portal now has a copy that ages, so it needs a refresh step. If you take this route, pin nothing
— always take `main` — because the installer and the config it fetches are released together.

**Do not rewrite or re-host a modified copy.** The installer fetches
`configs/claude/settings.json` from this repository at run time so there is exactly one place
where the tested configuration lives. A portal-side variant of either file breaks that.

## What the page must tell the user

Two things the mockup does not currently say, both of which produce support tickets:

**Run it inside the project you want on 0G.** The installer writes into the current directory and
nowhere else — your global `~/.claude/settings.json` is never touched. That is a deliberate
property, not an oversight, but a user who pastes this into their home directory gets a working
setup in exactly one place they did not mean. One line next to the command is enough: *run this
from your project folder.* Running it again in another project is expected and costs nothing.

**macOS and Linux.** The installer is POSIX shell. On Windows it needs WSL or Git Bash; plain
PowerShell will not run it.

Worth stating, less urgently: it needs `curl`, `python3` and `git` (present on a normal dev
machine), and if `claude` is missing it installs it with `npm`, so Node has to be there — or the
installer stops and says so rather than half-installing.

## What the user sees

Success is four lines and takes a few seconds, most of it spent checking the key:

```
checking the key against the router…
done. Claude Code is on 0G in this project.
Start it in any terminal — no export needed:

  claude
```

Failure prints one paragraph naming the cause and what to do. The cases the page may want to
pre-empt in its copy:

| What happened | What the installer says |
|---|---|
| Key rejected by the router | states the key was refused (401) and links the dashboard's API Keys page |
| Account out of balance | says the key is **valid** and the balance is empty, links the top-up page, and makes clear nothing about the config needs changing |
| `claude` and `npm` both missing | says to install Node, then gives the npm command |
| `.claude/settings.local.json` already tracked by git | refuses to write the key and prints the `git rm --cached` that fixes it |

The middle two matter for the card's copy: a user whose balance is empty has done nothing wrong
and should not be sent back to re-copy the command.

## Exit codes

`0` on success, `1` on any failure. That is the whole contract, and it is deliberately small:
**the portal never observes it.** The command runs in the user's terminal, not on the portal's
infrastructure, so there is no code for the page to read and no page-side feedback to drive from
it. What the page can do is set expectations for what the user will read on screen — the table
above.

Distinct per-failure codes would only matter if something started running this unattended (CI, a
provisioning script). Nothing does today. Ask before building on `1` meaning anything more
specific than "it did not work".

## Uninstall

```
curl -fsSL https://pc.0g.ai/install | bash -s claude --uninstall
```

No key needed. Removes both files and its own `.gitignore` block, leaving anything else in
`.gitignore` untouched. There is no `unset` step and no leftover shell variable: the key lived in
a file, and the file is gone.

## Key rotation

The command embeds the key at the moment the page renders it. If the user rotates or deletes that
key in the dashboard, previously copied commands stop working and already-installed projects
start returning 401. The fix is to copy the fresh command and run it again — it overwrites the
old key in place and leaves no trace of it.

If the card ever grows a "regenerate key" action, re-render the command next to it.

## The key in shell history

`--key <KEY>` puts a live credential in the user's shell history. That is a deliberate trade for
one-paste setup, and it should not be silently traded on the user's behalf. The installer accepts

```
curl -fsSL https://pc.0g.ai/install | bash -s claude --key -
```

which prompts for the key on the terminal instead, with echo off, and touches no history. If the
card has room for a second line, offer it. Users pasting into a shared or recorded terminal will
want it.

## The other three tabs

Only `claude` is implemented. The installer declines the rest by name rather than failing
strangely, so whatever the card does, a user who gets the command anyway gets a clear answer.

**Codex** — do not ship an install command. Codex speaks only the Responses API, which the router
does not serve, so it needs a LiteLLM bridge running in its own terminal for as long as Codex is
used. One pasted command cannot leave a live process behind, and pretending otherwise produces a
setup that dies when the terminal closes. Link
[the Codex section of the README](../README.md#set-up--codex) instead. This becomes a one-liner
if the router ever serves the Responses API — worth tracking as the thing that would unblock it.

**Gemini CLI** — not investigated yet. Nobody has checked which config shape it needs or whether
it can reach the router directly. Either hide the tab or mark it clearly as not yet supported;
do not show a command shaped like the Claude one.

**cURL** — this one is easy and needs no installer at all: it is a plain API request, and the
router is Anthropic- and OpenAI-compatible. Render it directly with the key substituted the same
way:

```
curl https://router-api.0g.ai/v1/messages \
  -H "Authorization: Bearer <KEY>" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"glm-5.3","max_tokens":256,
       "messages":[{"role":"user","content":"Hello"}]}'
```

`glm-5.3` is the same default the installer ships and is one of the two models whose weights run
inside the enclave. The live list of models a direct Anthropic-format call can reach:

```
curl -s https://router-api.0g.ai/v1/models
```

Filter on `supported_formats` containing `anthropic`. **Do not hardcode that list on the page.**
It moves: it went from eighteen models to sixteen in a single afternoon during the work that
produced this document.

## What this repository promises

While the card is live, these do not change without telling you first:

- the command shape `bash -s claude --key <KEY>`
- `0` on success, non-zero on failure
- the installer writing only into the current project, never `~/.claude/settings.json`
- `--uninstall` needing no key
- `claude` being the client word for Claude Code

Everything else — the files written, the default model, the wording on screen — may change as the
router does.
