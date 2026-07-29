# Excluded Features（明确不迁移）

macOS Athlon Agent **不包含**以下 Windows 能力：

| 功能 | 说明 |
|------|------|
| ImpSSO / SSO 启动门 | 无企业 SSO 登录门禁；应用可直接启动 |
| 左栏 SSO 身份条 | 无账号条 / 登出 SSO |
| License / 注册 | 无 `license.lic`、注册码、试用门 |
| Velopack 自动更新 | 不使用 Velopack；见 `packaging.md` |

其余 Agent / MCP / Knowledge / Schedule 等以本仓库 `parity-checklist.md` 为准。
