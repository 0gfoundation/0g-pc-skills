# 0G PC 配置验证 — Codex

**被测 commit**：____________  **日期**：____________  **执行人**：____________
**codex-cli 版本**：____________

被测的是 README 的用户路径：export key → 取三个文件 → 起代理 → `--profile` 启动。

> **架构已变（2026-08-27）**：三个配置文件由仓库分发，不再由 Skill 逐字重打。本协议**不再包含**写前 TOML 校验、`.bak` 备份等检查 —— 那些机制随写入脚本一起下线。
>
> **版本注意**：#11 的实测证据取自 codex-cli 0.145.0，0.149.1 上已复验通过。若你的版本更新且观察到与本协议描述不符的行为，那本身就是要记录的新信息。

---

## 0. 前置

从你 clone 的这个仓库里运行（本文件就在其中）：

```bash
git pull --ff-only
export REPO=$(git rev-parse --show-toplevel)   # 后续步骤会用；换终端要重新 export
git log --oneline -1                    # 被测 commit：____________
codex --version                         # 记下：____________
lsof -i :4000                           # 必须为空，否则代理端口被占
mkdir -p ~/Desktop/0g-probe-codex
```

留全局配置基线 —— **存副本，不是只存哈希**：

```bash
cp ~/.codex/config.toml /tmp/codex-config-before.toml
echo "CODEX_HOME=${CODEX_HOME:-<未设置>}"
 export ZG_API_KEY='sk-...'
```

## 1. 取三个文件

```bash
mkdir -p ~/.0g-litellm
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/codex/litellm-config.yaml -o ~/.0g-litellm/litellm-config.yaml
curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/codex/zg_patch.py -o ~/.0g-litellm/zg_patch.py
mkdir -p "${CODEX_HOME:-$HOME/.codex}" && curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/configs/codex/zg-glm53.config.toml -o "${CODEX_HOME:-$HOME/.codex}/zg-glm53.config.toml"
```

## 2. 取回后检查

```bash
R="$REPO/configs/codex"
# a) 三个文件与仓库副本逐字节一致
cmp ~/.0g-litellm/litellm-config.yaml $R/litellm-config.yaml ; echo "a1) 期望 0，实得 $?"
cmp ~/.0g-litellm/zg_patch.py $R/zg_patch.py ; echo "a2) 期望 0，实得 $?"
cmp "${CODEX_HOME:-$HOME/.codex}/zg-glm53.config.toml" $R/zg-glm53.config.toml ; echo "a3) 期望 0，实得 $?"

# b) 全局 config.toml 未被写入 Skill 的痕迹 —— 键级断言，不是整文件哈希
grep -c 'model_providers' ~/.codex/config.toml ; echo "b) 期望 0"

# c) 除 Codex 自己维护的表之外，其余内容未变
python3 -c "
import re
def keys(p):
    t=open(p).read()
    tb=[x for x in re.findall(r'^\[([^\]]+)\]', t, re.M) if not x.startswith(('projects.','hooks.state'))]
    tk=[l.split('=')[0].strip() for l in t.splitlines() if re.match(r'^[A-Za-z_]',l) and '=' in l]
    return set(tb), set(tk)
a=keys('/tmp/codex-config-before.toml'); b=keys('${HOME}/.codex/config.toml')
print('c)', '通过' if a==b else f'失败: 表差异 {a[0]^b[0]} 键差异 {a[1]^b[1]}')"
```

> **b/c 为什么不用整文件哈希**：Codex 在新目录首次运行会把 `[projects."<路径>"]` 信任记录写进 `config.toml`，还会写 `hooks.state.*`。而本协议要求在新目录跑 Codex —— 整文件哈希因此**必然失败**，且失败原因与要测的东西无关。一个注定误报的检查会训练人忽略告警。见 issue #26。

结果：a1 __ a2 __ a3 __ b __ c __

## 3. 配置加载检查（不需要代理、不需要网络）

```bash
cd ~/Desktop/0g-probe-codex
env -u ZG_LITELLM_KEY codex exec --profile zg-glm53 --skip-git-repo-check hi < /dev/null 2>&1 | tail -3
```

期望 ``Missing environment variable: `ZG_LITELLM_KEY` `` —— TOML 解析通过且 `zg` provider 已解析。
看到 `Error loading config.toml:` 就是配置坏了。`< /dev/null` 不能省（`codex exec` 在 stdin 是管道时会阻塞）。
`codex doctor` **不能**用来验这个 —— 它不读 profile 文件。

结果：____________

## 4. 起代理（**独立终端，保持运行**）

```bash
cd ~/.0g-litellm && uvx --from 'litellm[proxy]==1.98.0' litellm --config litellm-config.yaml --port 4000
```

另一终端健康检查：

```bash
curl -s -m 5 http://127.0.0.1:4000/health/liveliness && echo
```

## 5. 端到端 ⭐

```bash
cd ~/Desktop/0g-probe-codex
 export ZG_LITELLM_KEY='sk-anything'
codex exec --profile zg-glm53 --skip-git-repo-check "create hello.txt containing: hello from 0g, then cat it" < /dev/null
```

**先看启动横幅的 `model:` 行** —— 这是最关键的一次观察：

| `model:` 显示 | 含义 |
|---|---|
| `glm-5.3` | ✅ profile 已加载，请求走桥接 |
| `gpt-*` | 🚨 **停** —— profile 没加载，请求正发往 `api.openai.com`。Codex 对缺失 profile 一声不吭；已登录的用户会拿到看似正常的回答 |

| 其它现象 | 结论 |
|---|---|
| Codex 规划、执行 shell、回读文件内容 | ✅ **端到端通过** |
| `stream disconnected` + 反复重连 | ❌ `zg_patch.py` 没加载 —— 代理是否从 `~/.0g-litellm/` 启动 |
| `503 ... 127.0.0.1:4000` | ❌ 端口 4000 上是别的服务（第 0 步应已排除） |
| 代理终端报 401 | ❌ 那个终端的 `ZG_API_KEY` 无效或未导出 |

结果：____________

## 6. 附加：Skill 自动发现（g3）

```bash
mkdir -p ~/.codex/skills/0g-pc-model-config-codex && curl -fsSL https://raw.githubusercontent.com/0gfoundation/0g-pc-skills/main/skills/0g-pc-model-config-codex/SKILL.md -o ~/.codex/skills/0g-pc-model-config-codex/SKILL.md
```

起 codex 会话说「在 Codex 接入 0G PC」。

**判据（旧协议缺这一条，上轮因此长时间无输出后被终止、至今无结论）**：
- **60 秒内**应出现引用 Skill 内容的响应（提到 `~/.0g-litellm`、`--profile` 或 `zg_patch.py`）
- 超过 60 秒无任何输出 → 判为**未通过**，记录当时的 codex 版本与完整输出，不要无限等待

结果：____________

## 7. 回滚

```bash
rm -rf ~/Desktop/0g-probe-codex ~/.codex/skills/0g-pc-model-config-codex
rm -f "${CODEX_HOME:-$HOME/.codex}"/zg-*.config.toml
# ~/.0g-litellm 不含密钥，留删自便
```

代理终端 Ctrl-C。

## 8. 结论

- [ ] 端到端通过（第 5 步）
- [ ] 未通过 —— 现象记录在第 5 步
