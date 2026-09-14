#!/bin/sh
# install.sh — put Claude Code on 0G Private Computer, in one command.
#
#   curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/install.sh \
#     | bash -s claude --key sk-…
#
# The pc.0g.ai Quick Start card serves this same file from https://pc.0g.ai/install with the
# user's key filled in. Both are this script; see docs/install-contract.md.
#
# Writes two files into the current project and nothing else. Your global
# ~/.claude/settings.json is never touched.
set -eu

BASE_URL="${ZG_BASE_URL:-https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main}"
ROUTER="${ZG_ROUTER:-https://router-api.0g.ai}"

SETTINGS=".claude/settings.json"
LOCAL=".claude/settings.local.json"
BACKUP=".claude/settings.json.0g-backup"
GITIGNORE=".gitignore"
MARK_HEAD="# >>> 0g-pc install >>>"
MARK_FOOT="# <<< 0g-pc install <<<"

die() { printf '%s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

usage() {
    cat <<'EOF'
Put Claude Code on 0G Private Computer.

  install.sh claude --key <YOUR_API_KEY>    install into the current project
  install.sh claude --key -                 read the key from the terminal instead,
                                            keeping it out of your shell history
  install.sh claude --uninstall             remove it again
  install.sh --help

Get a key at https://pc.0g.ai → Dashboard → API Keys.

Writes .claude/settings.json (no credentials, safe to commit) and
.claude/settings.local.json (your key, mode 600, added to .gitignore).
A settings.json already in the project is kept as settings.json.0g-backup
and put back by --uninstall. Your global ~/.claude/settings.json is never
written.
EOF
}

# ---------------------------------------------------------------- arguments

CLIENT=""
KEY=""
MODE="install"

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)   usage; exit 0 ;;
        --uninstall) MODE="uninstall" ;;
        --key)
            [ $# -ge 2 ] || die "--key needs a value (or - to be prompted). Try --help."
            KEY="$2"; shift ;;
        --key=*)     KEY="${1#--key=}" ;;
        -*)          die "unknown option: $1. Try --help." ;;
        *)
            [ -z "$CLIENT" ] || die "unexpected argument: $1. Try --help."
            CLIENT="$1" ;;
    esac
    shift
done

[ -n "$CLIENT" ] || { usage >&2; die "
which client? Only 'claude' is supported today."; }

case "$CLIENT" in
    claude) ;;
    codex)  die "codex is not supported by this installer yet — it needs a long-running
LiteLLM bridge, which one command cannot leave behind. See
https://github.com/0gfoundation/0g-pc-skills#set-up--codex" ;;
    gemini|curl) die "$CLIENT is not supported yet. Only 'claude' is." ;;
    *)      die "unknown client: $CLIENT. Only 'claude' is supported today." ;;
esac

have() { command -v "$1" >/dev/null 2>&1; }
have python3 || die "python3 is required and was not found."

# ------------------------------------------------------------- .gitignore

gitignore_add() {
    if [ -f "$GITIGNORE" ] && grep -qF "$MARK_HEAD" "$GITIGNORE"; then
        # An install from before the backup existed wrote a block covering only the
        # key file. Leaving it alone would let the backup reach a commit, so replace
        # the block rather than return.
        grep -qF "$BACKUP" "$GITIGNORE" && return 0
        gitignore_remove
    fi
    [ ! -f "$GITIGNORE" ] || [ -z "$(tail -c 1 "$GITIGNORE")" ] || printf '\n' >> "$GITIGNORE"
    printf '%s\n%s\n%s\n%s\n' "$MARK_HEAD" "$LOCAL" "$BACKUP" "$MARK_FOOT" >> "$GITIGNORE"
}

gitignore_remove() {
    [ -f "$GITIGNORE" ] || return 0
    python3 - "$GITIGNORE" "$MARK_HEAD" "$MARK_FOOT" <<'PY'
import pathlib, sys
p, head, foot = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
out, skipping = [], False
for line in p.read_text().splitlines(True):
    if line.strip() == head:
        skipping = True
    elif skipping:
        if line.strip() == foot:
            skipping = False
    else:
        out.append(line)
text = "".join(out)
if text.strip():
    p.write_text(text)
else:
    p.unlink()
PY
}

# --------------------------------------------------------------- uninstall

if [ "$MODE" = uninstall ]; then
    touched=0
    restored=0

    # The install merged one field into settings.local.json rather than replacing it,
    # because a project may already keep personal settings there. Take the same field
    # back out; deleting the file would undo more than the install ever did.
    if [ -e "$LOCAL" ]; then
        python3 - "$LOCAL" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
try:
    doc = json.loads(p.read_text())
except Exception:
    doc = None
if not isinstance(doc, dict):
    p.unlink()                       # unreadable: nothing of the user's to preserve
    raise SystemExit(0)
env = doc.get("env")
if isinstance(env, dict):
    env.pop("ANTHROPIC_AUTH_TOKEN", None)
    if not env:
        doc.pop("env", None)
if doc:
    p.write_text(json.dumps(doc, indent=2) + "\n")
else:
    p.unlink()                       # it held nothing but the key
PY
        touched=$((touched + 1))
    fi

    # settings.json was replaced wholesale, so hand the previous one back if the
    # install found one to save. No backup means there was nothing here before.
    if [ -e "$BACKUP" ]; then
        mv -f "$BACKUP" "$SETTINGS"
        touched=$((touched + 1)); restored=1
    elif [ -e "$SETTINGS" ]; then
        rm -f "$SETTINGS"
        touched=$((touched + 1))
    fi

    gitignore_remove
    [ ! -d .claude ] || rmdir .claude 2>/dev/null || true

    if [ "$touched" -eq 0 ]; then
        note "nothing to remove here — no 0G config in this project."
    elif [ "$restored" -eq 1 ]; then
        note "removed, and your previous $SETTINGS is back in place. Anything you
changed in the 0G configuration after installing it — a different model, say — went
with it. Your key is out of $LOCAL, so there is nothing to unset:
start Claude Code in a new terminal and it is back on the Anthropic API."
    else
        note "removed. Your key is out of $LOCAL, so there is nothing to unset:
start Claude Code in a new terminal and it is back on the Anthropic API."
    fi
    exit 0
fi

# --------------------------------------------------------------------- key

if [ "$KEY" = "-" ]; then
    if [ -r /dev/tty ]; then
        printf 'Paste your 0G API key (not shown): ' > /dev/tty
        stty -echo < /dev/tty 2>/dev/null || true
        read -r KEY < /dev/tty || true
        stty echo < /dev/tty 2>/dev/null || true
        printf '\n' > /dev/tty
    else
        read -r KEY || true
    fi
fi

[ -n "$KEY" ] || die "no key. Pass --key sk-… , or --key - to be prompted for it.
Get one at https://pc.0g.ai → Dashboard → API Keys."

case "$KEY" in
    sk-*) ;;
    *) die "that does not look like a 0G key — they start with 'sk-'." ;;
esac

# ---------------------------------------------------------------- preflight

# .gitignore does nothing for a file git already tracks, so refuse to write a key
# into one. This is the case where the usual fix looks applied and is not.
if have git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git ls-files --error-unmatch "$LOCAL" >/dev/null 2>&1; then
        die "$LOCAL is tracked by git. Writing your key into it would put it one
commit from being pushed, and .gitignore does not help with a file git already
tracks. Run this first:

  git rm --cached $LOCAL"
    fi
fi

if ! have claude; then
    have npm || die "Claude Code is not installed and npm was not found either.
Install Node.js, then run: npm install -g @anthropic-ai/claude-code"
    note "Claude Code not found — installing it…"
    npm install -g @anthropic-ai/claude-code >&2 || die "npm could not install Claude Code."
    have claude || die "npm finished but 'claude' is still not on PATH."
fi

# ------------------------------------------------------------------- write

mkdir -p .claude

tmp_cfg="$(mktemp)"
trap 'rm -f "$tmp_cfg"' EXIT INT TERM
curl -fsSL "$BASE_URL/configs/claude/settings.json" -o "$tmp_cfg" \
    || die "could not fetch the config from $BASE_URL — check your connection."
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$tmp_cfg" \
    || die "the config fetched from $BASE_URL is not valid JSON."
# Save a settings.json that was already here — once, and only once. On a second
# install the file in place is the one this script wrote, and copying that over the
# backup would destroy the user's original silently, with nothing left to restore.
if [ -e "$SETTINGS" ] && [ ! -e "$BACKUP" ]; then
    cp -p "$SETTINGS" "$BACKUP"
    note "kept your existing $SETTINGS as $BACKUP — --uninstall puts it back."
fi

cat "$tmp_cfg" > "$SETTINGS"

# The model to check the key with, and the context ceiling, both come from the router rather
# than from a number typed into this script. A model name written here would outlive its
# presence on the router and turn every install into a report that the user's key was refused.
if ! MODEL="$(python3 - "$SETTINGS" "$ROUTER" <<'PY'
import json, pathlib, sys, urllib.request
p = pathlib.Path(sys.argv[1])
cfg = json.loads(p.read_text())
model = (cfg.get("env") or {}).get("ANTHROPIC_MODEL")
if not model:
    sys.exit("the config carries no ANTHROPIC_MODEL — nothing to install.")
try:
    with urllib.request.urlopen(sys.argv[2] + "/v1/models", timeout=20) as r:
        live = {m["id"]: m for m in json.load(r)["data"]}
except Exception:
    live = {}                      # offline: keep the shipped ceiling and let the key check report
if live:
    m = live.get(model)
    if m is None:
        sys.exit(f"the config asks for {model}, which the router does not serve right now.\n"
                 f"This is not a problem with your key. See {sys.argv[2]}/v1/models")
    if "anthropic" not in (m.get("supported_formats") or []):
        sys.exit(f"the router serves {model} in "
                 f"{'+'.join(m.get('supported_formats') or ['no'])} format only, which a direct\n"
                 "config cannot reach. This is not a problem with your key.")
    ctx = m.get("context_length")
    if ctx:
        cfg["env"]["CLAUDE_CODE_MAX_CONTEXT_TOKENS"] = str(ctx * 15 // 16)
        p.write_text(json.dumps(cfg, indent=2) + "\n")
print(model)
PY
)"; then
    die "the config could not be prepared."
fi

# The key goes in the local file, which is merged rather than replaced: a project
# may already keep personal settings there.
KEY="$KEY" python3 - "$LOCAL" <<'PY'
import json, os, pathlib
p = pathlib.Path(os.sys.argv[1])
try:
    doc = json.loads(p.read_text())
    if not isinstance(doc, dict):
        doc = {}
except Exception:
    doc = {}
doc.setdefault("env", {})["ANTHROPIC_AUTH_TOKEN"] = os.environ["KEY"]
p.write_text(json.dumps(doc, indent=2) + "\n")
PY
chmod 600 "$LOCAL"

gitignore_add

# ---------------------------------------------------------------- validate

note "checking the key against the router…"
status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 \
    -X POST "$ROUTER/v1/messages" \
    -H "Authorization: Bearer $KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "{\"model\":\"$MODEL\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\".\"}]}" \
    || echo 000)"

case "$status" in
    200) ;;
    401) die "the config is written, but the router rejected this key (401).
Check it at https://pc.0g.ai → Dashboard → API Keys, then run this again." ;;
    402) die "the config is written, and the key is valid — but the account has no
balance (402). Top up at https://pc.0g.ai/dashboard/overview and you are done;
nothing here needs changing." ;;
    000) die "the config is written, but the router could not be reached to check
the key. Verify with: curl -s $ROUTER/v1/models" ;;
    *)   die "the config is written, but the router answered $status when checking
the key. Try again, or see https://pc.0g.ai/dashboard/overview" ;;
esac

# -------------------------------------------------------------- self-check

tmp_chk="$(mktemp)"
trap 'rm -f "$tmp_cfg" "$tmp_chk"' EXIT INT TERM
if curl -fsSL "$BASE_URL/check-0g.sh" -o "$tmp_chk" 2>/dev/null; then
    sh "$tmp_chk" || die "the config is written and the key works, but the checks
above found a problem. Fix it and run this again."
fi

note "done. Claude Code is on 0G in this project.
Start it in any terminal — no export needed:

  claude

Undo with: install.sh claude --uninstall"
