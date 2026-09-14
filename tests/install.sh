#!/bin/sh
# tests/install.sh — acceptance tests for install.sh, lettered as in issue #64.
#
#   sh tests/install.sh                 # key from ~/.0g-key
#   ZG_TEST_KEY=sk-… sh tests/install.sh
#   sh tests/install.sh skills          # only the cases that need no key
#
# Each install spends about 14 tokens validating the key against the router.
set -u

ONLY="${1:-all}"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$REPO/install.sh"
export ZG_BASE_URL="file://$REPO"

KEY="${ZG_TEST_KEY:-}"
[ -n "$KEY" ] || [ ! -f "$HOME/.0g-key" ] || KEY="$(cat "$HOME/.0g-key")"
[ "$ONLY" = skills ] || [ -n "$KEY" ] || {
    echo "no key: set ZG_TEST_KEY or write ~/.0g-key" >&2
    echo "(the skills subcommand needs none: sh tests/install.sh skills)" >&2
    exit 2; }
FAKE="sk-fake-key-that-the-router-will-reject"

# stat is spelled differently on BSD and GNU; tests should run on both.
mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null; }

pass=0; fail=0
ok()   { pass=$((pass + 1)); printf '  ✅ %s\n' "$1"; }
no()   { fail=$((fail + 1)); printf '  ❌ %s\n' "$1"; [ $# -lt 2 ] || printf '       %s\n' "$2"; }
want() { # want <名称> <期望 pass|fail> <实际退出码>
    if [ "$2" = pass ]; then [ "$3" -eq 0 ] && ok "$1" || no "$1" "exit=$3，期望 0"
    else [ "$3" -ne 0 ] && ok "$1" || no "$1" "exit=0，期望非 0"; fi
}

# The one file this installer must never touch. Fingerprint it up front and check
# at the end, so a stray write anywhere in the run is caught rather than assumed away.
GLOBAL="$HOME/.claude/settings.json"
GLOBAL_BEFORE="$( [ -f "$GLOBAL" ] && shasum "$GLOBAL" | cut -d" " -f1 || echo absent )"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM
fresh() { rm -rf "$WORK/p"; mkdir -p "$WORK/p"; cd "$WORK/p"; git init -q .; }

# ----------------------------------------------------------------------- #85
# No key, no router: the skills subcommand touches neither. Kept first so that
# `sh tests/install.sh skills` can stop before anything that needs one.
echo "#85 — skills 子命令"
SKD="$WORK/skills"
rm -rf "$SKD"

ZG_SKILLS_DIR="$SKD" sh "$INSTALL" skills >/dev/null 2>&1; want "安装退出 0" pass $?
n=0
for k in setup switch-model uninstall; do
    diff -q "$SKD/0g-pc-$k/SKILL.md" "$REPO/skills/0g-pc-$k/SKILL.md" >/dev/null 2>&1 \
        && n=$((n + 1))
done
[ "$n" = 3 ] && ok "三个 SKILL.md 与仓库逐字节一致" || no "三个 SKILL.md 与仓库逐字节一致" "一致 $n/3"

before="$(find "$SKD" -name SKILL.md -exec shasum {} \; | shasum)"
ZG_SKILLS_DIR="$SKD" sh "$INSTALL" skills >/dev/null 2>&1; want "二次安装退出 0" pass $?
[ "$before" = "$(find "$SKD" -name SKILL.md -exec shasum {} \; | shasum)" ] \
    && ok "幂等：文件逐字节不变" || no "幂等：文件逐字节不变"

# 旧 Skill 归用户处置：脚本必须提醒，但不得代为删除
mkdir -p "$SKD/0g-pc-model-config-claude"
printf 'old\n' > "$SKD/0g-pc-model-config-claude/SKILL.md"
out="$(ZG_SKILLS_DIR="$SKD" sh "$INSTALL" skills 2>&1)"
printf '%s' "$out" | grep -q 'still installed' \
    && ok "旧 Skill 在场时给出提醒" || no "旧 Skill 在场时给出提醒"
[ -f "$SKD/0g-pc-model-config-claude/SKILL.md" ] \
    && ok "但不代替用户删除" || no "但不代替用户删除"

ZG_SKILLS_DIR="$SKD" sh "$INSTALL" skills --uninstall >/dev/null 2>&1; want "卸载退出 0" pass $?
left=0
for k in setup switch-model uninstall; do [ -e "$SKD/0g-pc-$k" ] && left=$((left + 1)); done
[ "$left" = 0 ] && ok "三个目录已移除" || no "三个目录已移除" "剩 $left"
[ -e "$SKD/0g-pc-model-config-claude" ] \
    && ok "只移除自己装的，旧 Skill 留在原处" || no "只移除自己装的，旧 Skill 留在原处"

ZG_SKILLS_DIR="$SKD" sh "$INSTALL" skills --key sk-anything >/dev/null 2>&1
want "skills 带 key 被拒" fail $?
sh "$INSTALL" --help 2>/dev/null | grep -q 'install.sh skills' \
    && ok "--help 列出 skills" || no "--help 列出 skills"
sh "$INSTALL" claude skills >/dev/null 2>&1; want "两个 client 被拒" fail $?

if [ "$ONLY" = skills ]; then
    echo
    echo "通过 ${pass}，失败 ${fail}（仅 skills 段）"
    [ "$fail" -eq 0 ]
    exit $?
fi

# ------------------------------------------------------------------------ J
echo "J — 参数处理"
fresh
sh "$INSTALL" --help >/dev/null 2>&1;                     want "--help 退出 0" pass $?
sh "$INSTALL" claude >/dev/null 2>&1;                     want "缺 --key" fail $?
sh "$INSTALL" --key "$FAKE" >/dev/null 2>&1;              want "缺 client" fail $?
sh "$INSTALL" gemini --key "$FAKE" >/dev/null 2>&1;       want "gemini 未支持" fail $?
sh "$INSTALL" claude --key "$FAKE" --bogus >/dev/null 2>&1; want "未知选项" fail $?
sh "$INSTALL" claude --key "not-a-key" >/dev/null 2>&1;   want "key 形状不对" fail $?
out="$(sh "$INSTALL" codex --key "$FAKE" 2>&1)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'LiteLLM' && ok "codex 被拒且说明原因" \
    || no "codex 被拒且说明原因" "exit=$rc"
[ -e .claude ] && no "参数错误时不应写文件" || ok "参数错误时未写任何文件"

# ------------------------------------------------------------------------ K
echo "K — 坏 key 立刻可见"
fresh
out="$(sh "$INSTALL" claude --key "$FAKE" 2>&1)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q '401' && ok "坏 key 非 0 退出并点名 401" \
    || no "坏 key 非 0 退出并点名 401" "exit=$rc"

# ------------------------------------------------------------------------ A
echo "A — 纯净安装"
sh "$INSTALL" claude --key "$KEY" >/dev/null 2>&1;        want "安装退出 0" pass $?
[ "$(mode_of .claude/settings.local.json)" = 600 ] \
    && ok "local 权限 600" || no "local 权限 600"
grep -q 'settings.local.json' .gitignore 2>/dev/null \
    && ok ".gitignore 已覆盖" || no ".gitignore 已覆盖"
grep -q "$KEY" .claude/settings.json 2>/dev/null \
    && no "可提交那份不含凭据" || ok "可提交那份不含凭据"
grep -q "$KEY" .claude/settings.local.json 2>/dev/null \
    && ok "local 含凭据" || no "local 含凭据"
git status --porcelain --untracked-files=all | grep -q 'settings.local' \
    && no "git 看不见 local" || ok "git 看不见 local"

# ------------------------------------------------------------------------ F
echo "F — 换 key 无残留（承接 K 留下的假 key 现场）"
grep -q "$FAKE" .claude/settings.local.json 2>/dev/null \
    && no "旧假 key 已被替换" || ok "旧假 key 已被替换"

# ------------------------------------------------------------------------ E
echo "E — 幂等"
cp .claude/settings.json "$WORK/first.json"
sh "$INSTALL" claude --key "$KEY" >/dev/null 2>&1;        want "二次安装退出 0" pass $?
diff -q "$WORK/first.json" .claude/settings.json >/dev/null 2>&1 \
    && ok "settings.json 逐字节一致" || no "settings.json 逐字节一致"
[ "$(grep -c 'settings.local.json' .gitignore)" = 1 ] \
    && ok ".gitignore 未重复追加" || no ".gitignore 未重复追加"

# ------------------------------------------------------------------------ G
echo "G — 已有 local 不被吞"
fresh
mkdir -p .claude
printf '{\n  "permissions": {"defaultMode": "plan"},\n  "env": {"MY_OWN": "keepme"}\n}\n' > .claude/settings.local.json
sh "$INSTALL" claude --key "$KEY" >/dev/null 2>&1
python3 - <<'PY' && ok "自定义键仍在且 key 已写入" || no "自定义键仍在且 key 已写入"
import json, sys
d = json.load(open(".claude/settings.local.json"))
sys.exit(0 if d.get("permissions", {}).get("defaultMode") == "plan"
         and d.get("env", {}).get("MY_OWN") == "keepme"
         and d.get("env", {}).get("ANTHROPIC_AUTH_TOKEN") else 1)
PY

# ------------------------------------------------------------------------ H
echo "H — 卸载"
fresh
sh "$INSTALL" claude --key "$KEY" >/dev/null 2>&1
sh "$INSTALL" claude --uninstall >/dev/null 2>&1;         want "卸载退出 0" pass $?
[ ! -e .claude/settings.local.json ] && ok "local 已删" || no "local 已删"
[ ! -e .claude/settings.json ]       && ok "settings.json 已删" || no "settings.json 已删"
grep -q 'settings.local.json' .gitignore 2>/dev/null \
    && no "标记块已精确移除" || ok "标记块已精确移除"

echo "H' — 卸载只动自己那一段"
fresh
printf 'node_modules/\n' > .gitignore
sh "$INSTALL" claude --key "$KEY" >/dev/null 2>&1
sh "$INSTALL" claude --uninstall >/dev/null 2>&1
[ "$(cat .gitignore)" = "node_modules/" ] \
    && ok "用户原有 .gitignore 内容完好" || no "用户原有 .gitignore 内容完好" "$(cat .gitignore)"

# ------------------------------------------------------------------------ I
echo "I — 缺 CLI"
fresh
out="$(env PATH=/usr/bin:/bin sh "$INSTALL" claude --key "$FAKE" 2>&1)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'npm' \
    && ok "无 claude 无 npm 时非 0 退出并指路" || no "无 claude 无 npm 时非 0 退出并指路" "exit=$rc"

# ------------------------------------------------------------------------ C
echo "C — 末尾自检真的在跑"
fresh
BROKEN="$WORK/broken"; mkdir -p "$BROKEN/configs/claude"
cp "$REPO/check-0g.sh" "$BROKEN/check-0g.sh"
python3 - "$REPO/configs/claude/settings.json" "$BROKEN/configs/claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["modelOverrides"]["claude-sonnet-5"] = "glm-5.3"   # 把权限门指向推理模型
json.dump(d, open(sys.argv[2], "w"), indent=2)
PY
out="$(ZG_BASE_URL="file://$BROKEN" sh "$INSTALL" claude --key "$KEY" 2>&1)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'gate' \
    && ok "坏配置被自检拦下" || no "坏配置被自检拦下" "exit=$rc"

fresh
out="$(sh "$INSTALL" claude --key "$KEY" 2>&1)"; rc=$?
[ $rc -eq 0 ] && ! printf '%s' "$out" | grep -q '✗' \
    && ok "好配置自检静默通过" || no "好配置自检静默通过" "exit=$rc"

# ------------------------------------------------------------------ #74
echo "#74 — 不写死模型名与上限"
fresh
sh "$INSTALL" claude --key "$KEY" >/dev/null 2>&1
python3 - <<'PY' && ok "上限 = live context_length × 15/16" || no "上限 = live context_length × 15/16"
import json, pathlib, sys, urllib.request
live = {m["id"]: m.get("context_length")
        for m in json.load(urllib.request.urlopen("https://router-api.0g.ai/v1/models"))["data"]}
e = json.loads(pathlib.Path(".claude/settings.json").read_text())["env"]
sys.exit(0 if int(e["CLAUDE_CODE_MAX_CONTEXT_TOKENS"]) == live[e["ANTHROPIC_MODEL"]] * 15 // 16 else 1)
PY

# 配置指向 router 上没有的模型：必须点名模型，且不得让用户去怀疑自己的 key
BROKEN="$WORK/nomodel"; mkdir -p "$BROKEN/configs/claude"; cp "$REPO/check-0g.sh" "$BROKEN/"
python3 - "$REPO/configs/claude/settings.json" "$BROKEN/configs/claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["env"]["ANTHROPIC_MODEL"] = "glm-9.9-does-not-exist"
json.dump(d, open(sys.argv[2], "w"), indent=2)
PY
fresh
out="$(ZG_BASE_URL="file://$BROKEN" sh "$INSTALL" claude --key "$KEY" 2>&1)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'glm-9.9-does-not-exist'     && printf '%s' "$out" | grep -qi 'not a problem with your key'     && ok "缺失的模型被点名，且明确与 key 无关"     || no "缺失的模型被点名，且明确与 key 无关" "exit=$rc"

# ----------------------------------------------------------------------- #81
echo "#81 — 备份与恢复"

# 项目里原本就有一份 settings.json（用户自己的 hooks / permissions）
fresh
mkdir -p .claude
printf '{\n  "permissions": {"defaultMode": "plan"},\n  "statusLine": {"type": "command", "command": "echo mine"}\n}\n' > .claude/settings.json
cp .claude/settings.json "$WORK/orig-settings.json"

sh "$INSTALL" claude --key "$KEY" >/dev/null 2>&1;         want "有已存在配置时安装退出 0" pass $?
diff -q "$WORK/orig-settings.json" .claude/settings.json.0g-backup >/dev/null 2>&1 \
    && ok "备份与原件逐字节相同" || no "备份与原件逐字节相同"
grep -q 'statusLine' .claude/settings.json 2>/dev/null \
    && no "settings.json 已被 0G 配置取代" || ok "settings.json 已被 0G 配置取代"
grep -q '0g-backup' .gitignore 2>/dev/null \
    && ok ".gitignore 覆盖备份文件" || no ".gitignore 覆盖备份文件"
git status --porcelain --untracked-files=all | grep -q '0g-backup' \
    && no "git 看不见备份" || ok "git 看不见备份"

# 核心：二次安装时，就位的那份已经是 0G 配置了。若拿它去盖备份，
# 用户原件就此永久消失，而且不会有任何报错。
sh "$INSTALL" claude --key "$KEY" >/dev/null 2>&1;         want "二次安装退出 0" pass $?
diff -q "$WORK/orig-settings.json" .claude/settings.json.0g-backup >/dev/null 2>&1 \
    && ok "二次安装未覆盖备份（原件仍在）" || no "二次安装未覆盖备份（原件仍在）"

sh "$INSTALL" claude --uninstall >/dev/null 2>&1;          want "卸载退出 0" pass $?
diff -q "$WORK/orig-settings.json" .claude/settings.json >/dev/null 2>&1 \
    && ok "settings.json 已恢复成原件" || no "settings.json 已恢复成原件"
[ ! -e .claude/settings.json.0g-backup ] \
    && ok "备份已清理" || no "备份已清理"
grep -q '0g-backup' .gitignore 2>/dev/null \
    && no "卸载后 .gitignore 标记块已清" || ok "卸载后 .gitignore 标记块已清"

# 装进去时是合并，出来时也必须是合并
echo "#81 — 卸载不吞掉 local 里用户自己的东西"
fresh
mkdir -p .claude
printf '{\n  "permissions": {"defaultMode": "plan"},\n  "env": {"MY_OWN": "keepme"}\n}\n' > .claude/settings.local.json
sh "$INSTALL" claude --key "$KEY" >/dev/null 2>&1
sh "$INSTALL" claude --uninstall >/dev/null 2>&1
[ -e .claude/settings.local.json ] \
    && ok "local 文件仍在" || no "local 文件仍在"
python3 - <<'PYX' && ok "用户键保留，凭据已移除" || no "用户键保留，凭据已移除"
import json, sys
d = json.load(open(".claude/settings.local.json"))
sys.exit(0 if d.get("permissions", {}).get("defaultMode") == "plan"
         and d.get("env", {}).get("MY_OWN") == "keepme"
         and "ANTHROPIC_AUTH_TOKEN" not in d.get("env", {}) else 1)
PYX

# 原本一无所有：装完再卸，应当不留痕迹
echo "#81 — 无前置状态时装后卸不留痕"
fresh
sh "$INSTALL" claude --key "$KEY" >/dev/null 2>&1
sh "$INSTALL" claude --uninstall >/dev/null 2>&1
[ ! -e .claude ] && ok ".claude 目录已消失" || no ".claude 目录已消失" "$(ls -a .claude 2>/dev/null | tr '\n' ' ')"

echo "#81 — 全局配置全程未被触碰"
GLOBAL_AFTER="$( [ -f "$GLOBAL" ] && shasum "$GLOBAL" | cut -d' ' -f1 || echo absent )"
[ "$GLOBAL_BEFORE" = "$GLOBAL_AFTER" ] \
    && ok "~/.claude/settings.json 逐字节未变" \
    || no "~/.claude/settings.json 逐字节未变" "before=$GLOBAL_BEFORE after=$GLOBAL_AFTER"

# ------------------------------------------------------------------------- 
echo
echo "通过 ${pass}，失败 ${fail}"
[ "$fail" -eq 0 ]
