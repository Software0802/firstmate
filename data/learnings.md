# Learnings

<!-- 只记易忘、易踩坑的操作事实；分活偏好以 captain.md 为准，这里不重复长路由表 -->

- 额度：`quota-axi --tui` 或 Pi `/quota`；Fable 分项看 `model:fable`。
- Claude 项目入口：`CLAUDE.md` → 常 `@AGENTS.md`。
- 部署 skill 只给 Devin 用（`Software0802/skills/aliyun-ecs`），不要装进本机各 harness 全局 skills。
- Claude Code：`~/.claude/settings.json` 里 `autoCompactWindow: 50000`。
- SW2 Max 近 TPS 偏低，非必要少派；要测速再单开。
- 文档船员：**agy 1.2.7** 已装且登录可用；探测 `agy -p … --model gemini-3.8-flash-high` → `AGY_OK`。模型 id 自带 high/medium/low，与 `--effort` 同传会冲突。
- 视图评审：`lavish-axi` 在 PATH；复杂视觉交付用 Lavish，舰队板用 `/bearings lavish`。
- 用户全局 skill 枢纽：`~/.agents/skills`（Claude/Codex/Pi 目录软链到此）。Firstmate 内部 skill 不共享给工人。
- UI 优先级：Cursor `kimi-k3-max[context=20k]` → Fable medium → Devin `kimi-k3-max`。
- Devin CLI 本机已登录 Max；卡点是 Firstmate **无已验证 devin 船员适配**，不是没装 CLI。Fusion 例：`fusion-claude-fable-5-1-medium-sidekick-swe-2-medium`；SW2：`swe-2-max`。
