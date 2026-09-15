#!/bin/sh
# tests/check.sh — acceptance tests for check-0g.sh (issue #95).
#
#   sh tests/check.sh
#
# No key. It reaches the router once per case for the context-ceiling check, which
# check-0g.sh skips when the router is unreachable, so this also passes offline.
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CHK="$REPO/check-0g.sh"
CFG="$REPO/configs/claude/settings.json"
PLACEHOLDER='sk-placeholder-not-a-real-key'

pass=0; fail=0
ok() { pass=$((pass + 1)); printf '  ✅ %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  ❌ %s\n' "$1"; [ $# -lt 2 ] || printf '       %s\n' "$2"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

# scene <local json> [--no-project]
scene() {
    rm -rf "$WORK/p"; mkdir -p "$WORK/p/.claude"; cd "$WORK/p"; git init -q .
    printf '.claude/settings.local.json\n' > .gitignore
    [ "${2:-}" = --no-project ] || cp "$CFG" .claude/settings.json
    printf '%s\n' "$1" > .claude/settings.local.json
    chmod 600 .claude/settings.local.json
}

# ---------------------------------------------------------------------- 1
# Claude Code writes permissions.allow into this file every time a tool is
# approved. It overrides nothing the shipped config sets, and the advice to remove
# it cannot be followed — Claude Code writes it back. Flagging it failed the
# installer in 18 of 20 real projects on the machine where this was found.
echo "1 — Claude Code 自己写的 permissions.allow 不得报警"
scene "{\"env\":{\"ANTHROPIC_AUTH_TOKEN\":\"$PLACEHOLDER\"},\"permissions\":{\"allow\":[\"Bash(git status:*)\",\"Read(//Users/**)\"]}}"
out="$(sh "$CHK" 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && ok "静默且退出 0" || no "静默且退出 0" "exit=$rc out=$out"

echo "1b — deny / additionalDirectories 同样不得报警"
scene "{\"env\":{\"ANTHROPIC_AUTH_TOKEN\":\"$PLACEHOLDER\"},\"permissions\":{\"deny\":[\"Bash(rm:*)\"],\"additionalDirectories\":[\"/tmp\"]}}"
sh "$CHK" >/dev/null 2>&1; [ $? -eq 0 ] && ok "静默且退出 0" || no "静默且退出 0"

echo "1c — 同名同值不是冲突"
scene "{\"env\":{\"ANTHROPIC_AUTH_TOKEN\":\"$PLACEHOLDER\"},\"permissions\":{\"defaultMode\":\"acceptEdits\"}}"
sh "$CHK" >/dev/null 2>&1; [ $? -eq 0 ] && ok "与 shipped 取值相同，不报" || no "与 shipped 取值相同，不报"

# ---------------------------------------------------------------------- 2
echo "2 — 真遮蔽必须报，并写出两边的值"
scene "{\"env\":{\"ANTHROPIC_AUTH_TOKEN\":\"$PLACEHOLDER\"},\"permissions\":{\"defaultMode\":\"auto\",\"allow\":[\"Bash(ls:*)\"]}}"
out="$(sh "$CHK" 2>&1)"; rc=$?
[ $rc -ne 0 ] && ok "退出非 0" || no "退出非 0"
printf '%s' "$out" | grep -q "acceptEdits" && printf '%s' "$out" | grep -q "'auto'" \
    && ok "同时写出 project 与 local 的值" || no "同时写出 project 与 local 的值" "$out"
printf '%s' "$out" | grep -q 'allow' \
    && no "不得把无冲突的 allow 一并点名" || ok "不牵连无冲突的 allow"

# ---------------------------------------------------------------------- 3
echo "3 — local 改坏权限门，必须给出门的诊断"
scene "{\"env\":{\"ANTHROPIC_AUTH_TOKEN\":\"$PLACEHOLDER\"},\"modelOverrides\":{\"claude-sonnet-5\":\"glm-5.3\"}}"
out="$(sh "$CHK" 2>&1)"; rc=$?
[ $rc -ne 0 ] && ok "退出非 0" || no "退出非 0"
printf '%s' "$out" | grep -q 'reasoning model' && printf '%s' "$out" | grep -q 'glm-5.3' \
    && ok "点名模型并说明后果，而非笼统告警" || no "点名模型并说明后果，而非笼统告警" "$out"

# ---------------------------------------------------------------------- 4
echo "4 — 旧布局（配置全在 local，无 settings.json）给迁移指引"
scene "{\"env\":{\"ANTHROPIC_BASE_URL\":\"https://router-api.0g.ai\",\"ANTHROPIC_AUTH_TOKEN\":\"$PLACEHOLDER\",\"ANTHROPIC_MODEL\":\"glm-5.2\"},\"modelOverrides\":{\"claude-sonnet-5\":\"0gm-1.0-35b-a3b\"}}" --no-project
out="$(sh "$CHK" 2>&1)"; rc=$?
[ $rc -ne 0 ] && ok "退出非 0" || no "退出非 0"
printf '%s' "$out" | grep -q 'install.sh' \
    && ok "给出可执行的迁移命令" || no "给出可执行的迁移命令" "$out"

echo "4b — 既无 project 也无 0G 痕迹，仍是原来的拒绝"
rm -rf "$WORK/q"; mkdir -p "$WORK/q"; cd "$WORK/q"
out="$(sh "$CHK" 2>&1)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'run this from the project' \
    && ok "提示跑错目录" || no "提示跑错目录" "$out"

# ---------------------------------------------------------------------- 5
echo "5 — 健康配置仍然静默"
scene "{\"env\":{\"ANTHROPIC_AUTH_TOKEN\":\"$PLACEHOLDER\"}}"
out="$(sh "$CHK" 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && ok "静默且退出 0" || no "静默且退出 0" "exit=$rc out=$out"

echo
echo "通过 ${pass}，失败 ${fail}"
[ "$fail" -eq 0 ]
