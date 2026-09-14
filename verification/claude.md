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

准备 key —— **不导出**。新方案下 key 走文件，不走 shell；这里只把它放在手边，供第 1 步的命令使用：

```bash
 umask 077 && printf '%s' 'sk-...' > ~/.0g-key && ls -l ~/.0g-key   # 期望 -rw-------
```

**并确认 shell 里干净**，否则后面第 3 步验不出真东西：

```bash
env | grep -c '^ANTHROPIC'   # 期望 0
```

## 1. 安装

```bash
cd ~/Desktop/0g-probe
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/install.sh | bash -s claude --key "$(cat ~/.0g-key)"
echo "期望 0，实得 $?"
```

## 2. 写入后检查

```bash
# a) 除上下文上限外与仓库副本一致；上限由安装器按 live 重算，故单独校验
python3 -c "
import json,urllib.request
K='CLAUDE_CODE_MAX_CONTEXT_TOKENS'
a=json.load(open('.claude/settings.json')); b=json.load(open('$REPO/configs/claude/settings.json'))
live={m['id']:m.get('context_length') for m in json.load(urllib.request.urlopen('https://router-api.0g.ai/v1/models'))['data']}
ra={**a,'env':{k:v for k,v in a['env'].items() if k!=K}}
rb={**b,'env':{k:v for k,v in b['env'].items() if k!=K}}
want=live[a['env']['ANTHROPIC_MODEL']]*15//16
print('a1)', '通过' if ra==rb else '失败：除上限外应逐字段一致')
print('a2)', f'通过（上限 {a[\"env\"][K]}）' if int(a['env'][K])==want else f'失败：上限 {a[\"env\"][K]}，应为 {want}')"

# b) 配置中无凭据 —— 这是本次架构调整的核心
grep -c 'sk-\|AUTH_TOKEN' .claude/settings.json ; echo "b) 期望 0"

# c) 因此它可以安全提交
git check-ignore -q .claude/settings.json ; echo "c1) 期望 1（不被忽略），实得 $?"
git add -A --dry-run | grep settings.json ; echo "c2) 出现在暂存列表即符合预期（project 配置本就该共享）"

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

**必须重启**，且**特意换一个全新终端** —— 这一步的意义就在于此：key 在文件里，不在 shell 里，
所以换终端必须照样能用。开一个新窗口，先自证它是干净的，再启动：

```bash
env | grep -c '^ANTHROPIC'      # 期望 0 —— 若非 0，这一步验不出任何东西
cd ~/Desktop/0g-probe && claude
```

3.1 `/status` → Base URL 应为 `https://router-api.0g.ai`。
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

## 6b. 触发词互斥（#84）

三个 Skill 共用 `0g-pc-` 前缀、讲同一件事，靠 `description` 里的触发词分流。写重叠了就会挑错，而代价不对称：错到 `switch-model` 最多白问一轮，错到 `uninstall` 会走上删配置那条路。

```bash
python3 tests/triggers.py        # 无 key、不联网；PASSED 且退出码 0 为通过
```

它检查三件事：三个 Skill 两两之间没有互为子串的触发短语；12 条自然语言输入每条只命中预期的那一个；一条 Codex 的请求不会落到 Claude 的 Skill 上。

### 「0G 配置不工作」不路由到任何 Skill —— 定夺与理由

排错类输入（`0G 配置不工作`、`0G 用不了了`、`0G is broken`）**故意不被任何 Skill 命中**。

理由来自架构而不是口味：`/0g-pc-setup` 有一条前置检查，配置已存在时它拒绝启动。把排错路由给它，必然走进「已经装了，去用 switch 或 uninstall 吧」的死胡同。要让它不拒绝，就得按磁盘状态决定干哪件事——那正是这次拆分要消除的模式推断。

排错的入口是 `check-0g.sh` 和 `docs/claude-code.md`，三个 Skill 各自的 troubleshooting 表只管自己那件事。

### 跨客户端：子串消不掉，靠特异性

`set up 0G PC` 是 `set up 0G PC in Codex` 的子串，任何短语表都消不掉这个包含关系。所以两处一起解决：`0g-pc-setup` 的 description 明写「Claude Code only，提到 Codex 的请求属于 `0g-pc-model-config-codex`」，检查器按最长匹配判定归属。

### 已知且在案的重叠

旧 `0g-pc-model-config-claude` 与新三条共享 **7 个**触发短语。这是拆分过程中必然经过的一段，由 #86 撤掉旧 Skill 收尾——脚本报告它但不据此判失败。

## 7. 结论

- [ ] 通过 —— 第 3.2 步符合预期，第 2 步 a–d 全过
- [ ] 未通过 —— 现象记录在第 3.2 步

## 5. Skill 的模型清单（#65 起）

交互式 Skill 只呈现直连能到的模型，Path B 不出现。

```bash
# a) 文档里不得有任何桥的痕迹
grep -niE 'litellm|4000|bridge|zg_patch|ZG_API_KEY|uvx' "$REPO/skills/0g-pc-model-config-claude/SKILL.md"
echo "a) 期望 1（无命中），实得 $?"

# b) Skill 呈现的清单 == live 过滤结果
curl -s https://router-api.0g.ai/v1/models | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']
print('\n'.join(sorted(m['id'] for m in d if 'anthropic' in (m.get('supported_formats') or []))))"
```

b) 与 Skill 实际列出的逐条比对：不得多一个 openai-only，不得漏一个 anthropic-native。

c) TEE 标注必须三档：`TEE, model in enclave` / `TEE, proxied upstream` / `NO TEE`。
把 `TeeML` 与 `TeeTLS` 合并成一个 "TEE" 标签算**不通过** —— 前者模型权重在 enclave 内，后者不是，
而会话里没有任何东西会告诉用户自己在哪一档。

d) 让 Skill 处理"把主模型换成 kimi-k3"（一个 openai-only 模型）：应当一句说明加一个指向
`docs/claude-code.md` 的指引，**然后停下**。若它开始引导安装本地翻译层，算不通过。
