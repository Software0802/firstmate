# Captain preferences

<!-- memory tiers: see the stow skill -->

## Communication

- 中文交流；技术标识符、路径、命令、URL、专有名词可原文。
- **持久文档写法（强制）：** 只写**明确规则**（谁 / 什么 / 阈值 / 命令）。禁止叙事、禁止「用户说过…」、禁止「不要怎样」堆砌、禁止复述决策过程。能用表就用表。

## Working style

- 软件工作只经 Firstmate 指挥与交付。
- 项目（均 `no-mistakes-prod-only +yolo`）：见下表与 `data/projects.md`。

| 项目 | 是什么 | 现状 |
| --- | --- | --- |
| VideoPlatform | 视频/图片生成 Web；**真实用户、正式付费项目**（后续多人） | 已上线阿里云；系统未完善 |
| TranlithionApp | 字幕翻译（刷剧 + 目标含会议实时字幕） | 刷剧可用；**会议实时字幕未实现** |
| Thai-Language-Learning_LB | 泰语学习 App，内接 Agent | 已上线；用户=亲友/家人 |
- 工人后端：`herdr`。
- 额度：`quota-axi --tui` 或 Pi `/quota`。
- Claude Code：`autoCompactWindow = 50000`（`~/.claude/settings.json`）。
- **视图理解 / 可视化评审：** 全局 skill **`lavish`**（`~/.agents/skills/lavish`，已软链 Claude/Codex/Pi）+ CLI `lavish-axi`。复杂方案/对比/计划/选项/UI 预览 → HTML → `lavish-axi` → `poll`。舰队看板：`/bearings lavish`。
- **结构化拍板（强制）：** 凡需船长多选/多决策（审查结论、路线、D1–Dn 类）→ **必须** Lavish 可视化确认页，**禁止**仅用聊天 md 表代替。每项选项须附 **一句「为何推荐/为何不推荐」**；默认预选侦察建议，可改后整包提交。侦察 brief 主交付仍可写 `report.md`，拍板面由副手或工人挂 Lavish。
- **跨船员用户 skill 枢纽：** 真源只放 `~/.agents/skills/`；`~/.claude/skills`、`~/.codex/skills`、`~/.pi/agent/skills` 用**同名软链接**指回枢纽。不把 Firstmate 家 `.agents/skills`（副手内部）整库链给工人。项目专用 skill 仍进该项目 `.agents/skills` 并提交 git。

## Infrastructure

| 需求 | 执行方 |
| --- | --- |
| 写码 / PR | 舰队船员 + Herdr |
| Ubuntu / iOS 编译 | Devin 云 |
| 部署 / 生产运维 → 阿里云 ECS | **仅** Devin SW2 Max + skill `https://github.com/Software0802/skills/tree/main/skills/aliyun-ecs` |
| 密钥 | 只在 Devin / skill 侧；不进本仓库、不进本文件 |

## Routing

### 副手

| 项 | 值 |
| --- | --- |
| 运行时 | Pi |
| 模型 | Devin `swe-2` · thinking max（provider `devin`，由 pi 包 `pi-devin-oauth` 提供，须保持安装并登录） |
| 职责 | 指挥、监督、中文汇报、分活；不改三项目产品代码 |

### 船员

| 任务 | 模型 |
| --- | --- |
| 编码 / 修 bug / 测试 / 审**代码** | Claude Opus 5 · max（默认） |
| **文档 / 说明 / 描述类文案** | **agy** · `gemini-3.8-flash-high`（档位在模型名里；勿再加 --effort） |
| 审 **Fable 计划** | Codex GPT-6-Astra · medium |
| 较重调查 / 长上下文非 UI | Cursor Grok 4.6 · xhigh |
| 写计划 | Fable 5.1 · medium；Fable 用量 ≥50% → Devin Fusion（Fable medium + SW2 medium） |
| UI | **1) Cursor `kimi-k3-max[context=20k]`**（非 1M 窗；推理 max 已在 id）→ **2) Fable 5.1 medium** → **3) Devin Kimi K3 max** |
| 部署 / SW2 测速 | Devin SW2 Max（TPS 低时少派；测速需明示） |

### 计划 / UI 细则

| 条件 | 动作 |
| --- | --- |
| 写计划且 Fable 用量 < 50% 或未知 | Fable medium（未知则说明） |
| 写计划且 Fable 用量 ≥ 50% | 请船长开 Devin Fusion |
| UI（默认） | Cursor `kimi-k3-max[context=20k]`（max；非 1M） |
| UI 回退 1 | Claude Fable 5.1 medium |
| UI 回退 2 | 请船长开 Devin Kimi K3 max |
| Fusion / SW2 / Grok | 默认不做 UI |

### 默认派工

- harness `claude` · model `opus` · effort `max`
- Codex 不承担日常编码
- 文档类 → harness **`agy`**（Antigravity；船员/侦察；非 secondmate）
- **Devin CLI 本机状态：** `devin` 已装、已登录（Max）；Herdr 能识别进程。模型例：`kimi-k3-max`、`swe-2-max`、`fusion-claude-fable-5-1-medium-sidekick-swe-2-medium`。
- **`harness=devin` 可直接派工**（本仓库提交 `3425fcb5` 起为已验证船员/侦察适配；AGENTS.md §4 已列入）。仅限船员与侦察，**不可**作 secondmate。
- 计划 Fusion 默认模型 id（Devin 侧）：`fusion-claude-fable-5-1-medium-sidekick-swe-2-medium`
- 部署/SW2：`swe-2-max`（TPS 低时少派）

### 文档船员前置条件（agy）

- 个人订阅 **不能** 再走旧 `@google/gemini-cli` 的 Code Assist 登录（官方要求迁 Antigravity）。
- CLI：`agy` 在 PATH（从 https://antigravity.google 安装）。
- 登录：在 `agy` 里完成 Google 登录（无弹窗后才能派工）。
- 模型：默认 `gemini-3.8-flash-high`；以 `agy models` 为准可改。
- 未就绪：文档任务改 Fable medium，并报告缺 `agy`/未登录。
