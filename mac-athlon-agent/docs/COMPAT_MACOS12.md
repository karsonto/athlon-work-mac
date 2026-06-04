# macOS 12 兼容分支说明

本分支（`compat/macos-12`）在 `master` 基础上将**最低系统要求**从 macOS 14 降至 **macOS 12 (Monterey)**。

## 构建步骤

### 本地构建

依赖 [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) 官方包声明的最低版本为 macOS 13，且内部使用了 `Task.sleep(for:)`、`RegexBuilder` 等 macOS 13+ API。本分支通过补丁脚本在本地 checkout 中做 backport，**每次 `swift package resolve` 后需重新执行补丁**：

```bash
cd mac-athlon-agent
./Scripts/build-release-macos12.sh
./Scripts/package-macos-app.sh
```

`build-release-macos12.sh` 会 resolve 依赖、打补丁，并构建 **Universal Binary（x86_64 + arm64）**，以支持 Intel 与 Apple Silicon Mac。

### GitHub Actions

推送 `compat/macos-12` 分支或向该分支开 PR 时，会自动运行 [`.github/workflows/build-macos12.yml`](../.github/workflows/build-macos12.yml)：

- 解析依赖 → 执行 macOS 12 补丁 → **Universal 构建（Intel + Apple Silicon）** → 单元测试 → 打包 `.app` / DMG
- 产物名称：`AthlonAgent-macOS12`（可在 Actions 的 Artifacts 中下载）
- 打 tag `v1.0.0-macos12` 等形式（匹配 `v*-macos12`）推送后，会额外创建 GitHub Release
- 也可在 Actions 页手动 **Run workflow**（`workflow_dispatch`）

## 主要改动

| 区域 | 说明 |
|---|---|
| `Package.swift` / `Info.plist` | 部署目标改为 macOS 12 |
| `SwiftUICompatibility.swift` | `onChange` 双参数形式、`scrollContentBackground` 的兼容封装 |
| 各 View 文件 | 使用 `onValueChange` / `hideScrollContentBackgroundIfAvailable` |
| `Scripts/build-release-macos12.sh` | Universal Binary 构建入口（x86_64 + arm64） |
| `Scripts/package-macos-app.sh` | 打包 `.app`，并嵌入 Swift 运行时库 |
| `Scripts/patch-dependencies-macos12.sh` | 降低依赖包平台声明；将 MCP 的 `Task.sleep(for:)` 改为 `nanoseconds`；替换 `Data+Extensions` 中的 RegexBuilder |

## 系统要求

| 项目 | 要求 |
|---|---|
| **macOS 版本** | 12.0 Monterey 或更高 |
| **CPU 架构** | Intel (x86_64) 或 Apple Silicon (arm64)；DMG 为 Universal Binary |
| **构建环境** | Xcode 16+ / Swift 6（无法在 macOS 12 本机编译，需在新系统上交叉构建） |

> **注意：** 早期 CI 产物仅为 arm64，无法在 Intel Mac（如 2016 款 MacBook Pro）上运行。请重新下载包含 `x86_64 arm64` 的最新构建。

## 限制与风险

- 补丁作用于 `.build/checkouts`，**不会被 git 跟踪**；CI 或新机器上必须先 resolve 再 patch。
- MCP SDK 未官方支持 macOS 12，运行时行为需在 Monterey 上实测。
- 构建仍需要 **Xcode 16+ / Swift 6**（MCP SDK 0.12.1 要求），无法在仅含 Xcode 13 的旧系统上从源码编译；可在新 Xcode 上交叉编译后在 macOS 12 上运行。

## 合并建议

若 Monterey 实测通过，可考虑：

1. 向上游 MCP SDK 提交 macOS 12 兼容 PR，消除 patch 脚本；
2. 或将补丁后的 SDK 作为 fork / vendored 依赖固定版本。
