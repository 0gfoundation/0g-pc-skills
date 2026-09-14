#!/bin/sh
# tests/install.sh — acceptance tests for install.sh, lettered as in issue #64.
#
#   sh tests/install.sh                 # key from ~/.0g-key
#   ZG_TEST_KEY=sk-… sh tests/install.sh
#
# Each install spends about 14 tokens validating the key against the router.
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$REPO/install.sh"
export ZG_BASE_URL="file://$REPO"

KEY="${ZG_TEST_KEY:-}"
[ -n "$KEY" ] || [ ! -f "$HOME/.0g-key" ] || KEY="$(cat "$HOME/.0g-key")"
[ -n "$KEY" ] || { echo "no key: set ZG_TEST_KEY or write ~/.0g-key" >&2; exit 2; }
FAKE="sk-fake-key-that-the-router-will-reject"

pass=0; fail=0
ok()   { pass=$((pass + 1)); printf '  ✅ %s\n' "$1"; }
no()   { fail=$((fail + 1)); printf '  ❌ %s\n' "$1"; [ $# -lt 2 ] || printf '       %s\n' "$2"; }
want() { # want <名称> <期望 pass|fail> <实际退出码>
    if [ "$2" = pass ]; then [ "$3" -eq 0 ] && ok "$1" || no "$1" "exit=$3，期望 0"
    else [ "$3" -ne 0 ] && ok "$1" || no "$1" "exit=0，期望非 0"; fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM
fresh() { rm -rf "$WORK/p"; mkdir -p "$WORK/p"; cd "$WORK/p"; git init -q .; }

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
[ "$(stat -f '%Lp' .claude/settings.local.json 2>/dev/null)" = 600 ] \
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

# -------------------------------------------------------------------------
echo
echo "通过 ${pass}，失败 ${fail}"
[ "$fail" -eq 0 ]
