# 0G PC 配置验证 — Claude Code

**被测 commit**：____________  **日期**：____________  **执行人**：____________

被测的是 README 描述的用户路径：export key → 取配置文件 → 重启。Skill 是可选走法，单独在第 6 步验。

> **架构已变（2026-08-27）**：配置由仓库分发，不再由 Skill 生成。因此本协议**不再包含**写前校验、`.bak` 备份、gitignore 守卫、占位符 key 等检查 —— 那些机制的保护对象（配置里的密钥）已经不存在。

---

## 0. 前置

从你 clone 的这个仓库里运行（本文件就在其中）：

```bash
git pull --ff-only
export REPO=$(git rev-parse --show-toplevel)   # 后续步骤会用；换终端要重新 export
git log --oneline -1                    # 被测 commit：____________
mkdir -p ~/Desktop/0g-probe && cd ~/Desktop/0g-probe && git init
```

probe 目录的作用只是别把测试产物丢进 clone。**它不再影响任何检查的有效性** —— 旧协议里那条「clone 自带的 `.gitignore` 会让检查恒真」的顾虑，随 gitignore 守卫一起消失了。

留全局配置基线（第 2 步 d 用）—— **存副本，不是只存哈希**：

```bash
cp ~/.claude/settings.json /tmp/global-before.json
```

导出 key：

```bash
 export ZG_API_KEY='sk-...'
 export ANTHROPIC_AUTH_TOKEN="$ZG_API_KEY"
echo "${#ANTHROPIC_AUTH_TOKEN} chars"   # 只看长度
```

## 1. 取配置

```bash
cd ~/Desktop/0g-probe
mkdir -p .claude && curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/claude/settings.local.json -o .claude/settings.local.json
```

## 2. 写入后检查

```bash
# a) 与仓库副本逐字节一致
cmp .claude/settings.local.json "$REPO/configs/claude/settings.local.json" ; echo "a) 期望 0，实得 $?"

# b) 配置中无凭据 —— 这是本次架构调整的核心
grep -c 'sk-\|AUTH_TOKEN' .claude/settings.local.json ; echo "b) 期望 0"

# c) 因此它可以安全提交
git add -A --dry-run | grep settings.local.json ; echo "c) 出现在暂存列表即符合预期（配置本就该共享）"

# d) 全局配置：只比对 Skill 可能写的三个键，不比整文件哈希
python3 -c "
import json
a=json.load(open('/tmp/global-before.json')); b=json.load(open('${HOME}/.claude/settings.json'))
ks=['env','modelOverrides','permissions']
print('d)', '通过' if all(a.get(k)==b.get(k) for k in ks) else '失败: '+str([k for k in ks if a.get(k)!=b.get(k)]))"
```

> **d 为什么不用整文件哈希**：Claude Code 自己会往 `settings.json` 写状态（`/model` 选择就落在那里），Codex 会写项目信任记录。整文件哈希分不清「配置被违规改写」和「客户端记录常规状态」，必然误报 —— 一个注定失败的检查会训练人忽略告警。见 issue #26。

结果：a __ b __ c __ d __

## 3. 重启后验证 ⭐

**必须重启**，且在**导出了 key 的终端**里：

```bash
cd ~/Desktop/0g-probe && claude
```

3.1 `/status` → Base URL 应为 `https://router-api.0g.ai`，Auth token 来源为 `ANTHROPIC_AUTH_TOKEN`。
（`[claude-code:unrecognized_model]` 是预期内的无害提示。）

3.2 让会话执行：`echo ok > probe.txt && cat probe.txt`

| 现象 | 结论 |
|---|---|
| 弹一次确认后成功 | ✅ 正常 —— 配置发的是 `acceptEdits` |
| 无提示直接成功 | ✅ 你把 `defaultMode` 改成了 `auto`，且门禁配置正确 |
| 报 `temporarily unavailable`，消息里的模型名是 `0gm-1.0-35b-a3b` | ❌ 门禁模型不可用 → 查 router 是否仍提供该模型 |
| 消息里的模型名带 `[1m]` 后缀 | ❌ 会话模型带 `[1m]`，见 `check-0g.sh` |
| **消息里的模型名 == 你配置的主模型** | ❌ Sonnet 档解析返回空，回落到主模型 → 查是否有残留的 `ANTHROPIC_DEFAULT_SONNET_MODEL` |

> 最后一行**不要写死成某个模型名** —— 它取决于你在配置里填了什么。（旧协议写死 `glm-5.2`，实测选 `deepseek-v4-flash` 时就对不上了。）

结果：____________

## 4. check-0g.sh

```bash
cd ~/Desktop/0g-probe
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/check-0g.sh | sh ; echo "期望 0，实得 $?"
```

## 5. 回滚

```bash
rm -rf ~/Desktop/0g-probe
python3 -c "
import json
a=json.load(open('/tmp/global-before.json')); b=json.load(open('${HOME}/.claude/settings.json'))
print('全局三键仍未变:', all(a.get(k)==b.get(k) for k in ['env','modelOverrides','permissions']))"
```

## 6. 附加：Skill 走法（可选）

```bash
mkdir -p ~/.claude/skills/0g-pc-model-config-claude && curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/skills/0g-pc-model-config-claude/SKILL.md -o ~/.claude/skills/0g-pc-model-config-claude/SKILL.md
```

**skill 发现无需重启** —— curl 落盘后当前会话即时注册（实测）。若当前会话没出现，再重开终端确认。
说「接入 0G PC」，它应当引导你走完与第 1–3 步等价的流程。

结果：____________

## 7. 结论

- [ ] 通过 —— 第 3.2 步符合预期，第 2 步 a–d 全过
- [ ] 未通过 —— 现象记录在第 3.2 步
