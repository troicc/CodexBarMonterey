# CodexBar Monterey 项目记忆 / Agent Handoff

> 这是一份给后续对话和 agent 的项目上下文。开始分析、修改或发布前先读本文件。内容是 2026-08-01 的快照；涉及分支、提交、上游能力和依赖版本时，先重新检查当前仓库状态。

## 1. 当前状态速览

| 项目 | 当前值 |
| --- | --- |
| GitHub 仓库 | troicc/CodexBarMonterey |
| origin | https://github.com/troicc/CodexBarMonterey.git |
| 当前分支 | fix/deepseek-zai-dashboard |
| 当前 HEAD | 02c9df9 — Fix Moonshot finance provider patch context |
| 工作树 | 记录时干净 |
| 上游引擎常量 | ENGINE_VERSION = v0.46.0 |
| 当前正式 tag | v0.5.0（同时存在 v0.4.0 指向同一旧提交） |
| 目标发布 | v0.6.0 / 应用版本 0.6.0 |
| 最低系统 | macOS 12 Monterey |
| 架构 | Universal 2：arm64 + x86_64 |
| UI 技术 | AppKit 菜单栏壳 + SwiftUI 内容视图 |
| 发布入口 | .github/workflows/release.yml，由 v* tag push 触发 |

当前 feature 分支包含在 origin/main 之后的 DeepSeek、z.ai、Moonshot 等 dashboard/finance 改动；发布 0.6.0 前应先确认这些提交已经合入 main。不要把“当前分支有代码”误认为“main 已经包含代码”。

## 2. 项目定位

这是一个面向 macOS 12 Monterey 的 CodexBar 兼容版本/移植版本。核心目标是：

- 在较旧 macOS 上保留菜单栏常驻、弹出 dashboard、设置、状态页和登录启动能力；
- 复用或打包上游 CodexBarCLI 的 provider 数据引擎，而不是在 UI 中重复实现 provider API；
- 通过 Sparkle 2.9.4 提供整包更新；
- 产出 Apple Silicon 与 Intel 均可运行的 Universal 2 应用。

它不是上游 SwiftUI 产品的逐像素回移植。README 已明确接受以下取舍：不保证完整保留上游的 WidgetKit、全部 provider-specific 登录界面、所有 SwiftUI 设置细节和定制动画。

产品体验可以概括为：本项目偏“多 provider 的财务/用量总览”，上游 steipete/CodexBar 偏“provider 原生配额、状态与账号监控器”。

## 3. 代码架构与数据流

### 主链路

~~~text
菜单栏状态项
  -> MenuController
  -> DashboardStore / CLIClient
  -> bundled CodexBarCLI --format json --json-only --status
  -> DashboardParser / typed provider payloads
  -> DashboardViews
~~~

原则：UI 不直接请求 Codex、DeepSeek、z.ai 等 provider endpoint；所有 provider 访问、认证和状态采集尽量由 CLI 完成。修改数据字段时，优先确认 CLI JSON contract、patch 和 parser 是否同时更新。

### 关键文件

- Sources/CodexBarMonterey/MenuController.swift：菜单栏状态项、popover、动作路由。
- Sources/CodexBarMonterey/DashboardStore.swift：刷新、状态缓存和 dashboard 状态。
- Sources/CodexBarMonterey/CLIClient.swift：启动 bundled CLI、传入 provider/环境变量、读取 JSON/text。
- Sources/CodexBarMonterey/DashboardParser.swift：兼容多种 provider payload，生成 UI 模型。
- Sources/CodexBarMonterey/DashboardViews.swift：popover、provider switcher、summary card、quota lanes、动作行。
- Sources/CodexBarMonterey/SettingsWindowController.swift：AppKit 设置窗口与 SwiftUI 设置内容桥接。
- Sources/CodexBarMonterey/ProviderAuthentication.swift：认证方式与 provider 配置目录。
- Sources/CodexBarMonterey/CodexBarConfigStore.swift：读取/写入 CodexBar 配置；保留未知字段；配置文件权限为 0600。
- Sources/CodexBarMonterey/ProviderFinance.swift：provider 余额、成本和 finance 能力分类。
- Sources/CodexBarMonterey/LocalSpendHistoryStore.swift：按 account hash/currency 保存本地余额变化估算。
- Sources/CodexBarMonterey/LocalQuotaTrendStore.swift：保存 z.ai 五小时 quota 样本并生成本地趋势。
- Patches/CodexBarLiveUsage.patch：为 z.ai、DeepSeek 增加 live JSON payload；由环境变量控制。
- Scripts/build_universal.sh：arm64/x86_64 构建、合并 bundle 内 Mach-O、签名和 zip。
- Scripts/generate_appcast.sh：使用 Sparkle 工具生成带签名的 appcast.xml。
- .github/workflows/release.yml：完整 release pipeline，发布 zip、checksum、可选 appcast/notarization。

### 当前数据能力

- Codex / Claude：可使用官方 cost/history 数据。
- DeepSeek / Moonshot / MiMo：支持 prepaid balance delta 方式的本地花费估算。
- Kimi、z.ai、Qwen、Qwen Cloud、Alibaba 变体：主要是 quota/balance-only，不能假设有官方历史成本。
- z.ai：live usage payload 优先；没有 live 数据时，可用 LocalQuotaTrendStore 的本地采样回退。
- DeepSeek / z.ai / Moonshot 的 provider dashboard 改动已经是当前 0.6.0 候选版本的重要内容。
- LocalSpendHistoryStore 的数值应标为 estimate；它是余额差估算，不等于 provider 官方账单。

## 4. 当前 UI 事实

截图和代码对应的主要交互如下：

- DashboardTheme.popoverWidth = 328，popover 高度约 520。
- 顶部是四列 provider switcher：Overview、Codex、DeepSeek、z.ai；项目当前还有其他 provider 数据，但不一定在顶部固定展示。
- Overview tile 会打开独立的全量详情窗口（AllProvidersDashboardView），不是在 popover 内展开。
- provider summary card 最多展示四个 metrics、mini history chart、history summary、top model；下面是 quota lanes。
- 底部动作：Usage Dashboard、Status Page、Refresh、Settings、About CodexBar、Quit。
- 当前 DashboardActionRow 的 ⌘R、⌘,、⌘Q 主要是可见快捷键提示；代码中没有为这些 row 完成对应的 .keyboardShortcut 绑定，这是潜在体验问题。
- 菜单栏图标是自绘的简化 meter/percentage 图标；没有上游那种丰富的 provider-specific 图标布局。
- 左键和右键状态项目前都走同一套 popover 行为。

## 5. 与上游 steipete/CodexBar 的对比结论

参考上游仓库及文档：

- CodexBar：https://github.com/steipete/CodexBar
- CHANGELOG：https://github.com/steipete/CodexBar/blob/main/CHANGELOG.md
- Providers：https://github.com/steipete/CodexBar/blob/main/docs/providers.md
- UI：https://github.com/steipete/CodexBar/blob/main/docs/ui.md
- Refresh loop：https://github.com/steipete/CodexBar/blob/main/docs/refresh-loop.md
- Widgets：https://github.com/steipete/CodexBar/blob/main/docs/widgets.md
- Configuration：https://github.com/steipete/CodexBar/blob/main/docs/configuration.md

### 本项目更强的地方

- 支持 macOS 12 Monterey；对旧系统用户是明显的可用性优势。
- 使用固定尺寸、信息密度高的 dashboard，打开后能快速看到今日/30 天 tokens、成本、趋势和 top model。
- 已把 DeepSeek、z.ai、Moonshot 等 provider 的 finance/quota 数据压进统一 dashboard。
- 继续使用上游 CLI 数据引擎，provider 覆盖和认证基础不会完全从零维护。

### 上游更强的地方

- 上游面向 macOS 14+，provider-specific UI、来源策略和字段呈现更完整。
- 有更丰富的 reset countdown、pace、warning、incident/status polling、账号切换和 provider 原生卡片。
- 有 Manual/固定间隔/Adaptive/Agent-aware Adaptive 刷新策略以及后台 coalescing。
- 有 Switcher、Usage、History、Metric、Burn Down、Combined Burn Down 等 Widget。
- 设置、Keychain access control、storage scan、hooks、账号管理、本地化、更新渠道和安装/升级体验更成熟。
- 上游官方发布渠道（GitHub Release、Homebrew、CLI tarball）更完整；本项目发布依赖自己的 GitHub Actions 配置。

### 选择建议

- macOS 12：优先使用本项目；这是本项目最明确的产品价值。
- macOS 14+ 且追求完整 provider/status/widget/更新体验：优先上游。
- 本项目适合“每天看消费和整体趋势”；上游适合“长期监控配额重置、状态、账号和后台刷新”。

## 6. 已知风险、文档差异和不要误判的地方

1. README 中仍有“upstream native text details”一类描述，但当前 DetailsWindowController.showCost 实际调用 showUsage / AllProvidersDashboardView；CLIClient.detailedText 和 costText 方法存在，但没有发现调用点。修改详情页前要以当前代码为准，并考虑同步 README。
2. 当前 branch 是 feature branch，不是 main；release workflow 的 appcast 发布阶段会把临时 worktree 建在 origin/main 上并推送 appcast.xml 到 main。
3. 没有 SPARKLE_PUBLIC_KEY / SPARKLE_PRIVATE_KEY 时，zip/checksum 仍可能发布，但不会生成签名 appcast，Sparkle 自动更新链路不完整。
4. 没有 Developer ID 签名和 Apple notarization secrets 时，workflow 会使用 ad-hoc signing；公开分发时会遇到 Gatekeeper 信任/安装体验问题。
5. 本地 Swift 校验曾因当前机器的 Swift/Clang ModuleCache 无法加载 macOS 12 标准库而失败，不应把这个环境问题当成代码已验证成功或代码必然失败。CI（macOS 26 runner）是 release gate。
6. 自定义 dashboard 对丰富 provider 字段做了压缩；如果新增 provider 字段，先检查 parser 的 typed path、generic fallback、metrics 上限 4、quota lane 上限 8 是否会丢信息。
7. 本地 spend history 是余额差估算，不应在 UI 或 release note 中写成 provider 官方账单。

## 7. 验证命令

低成本静态检查：

~~~bash
python3 Scripts/test_ui_contract.py
bash -n Scripts/*.sh
~~~

release workflow 还会执行：

~~~bash
python3 Scripts/test_monterey_patcher.py
python3 Scripts/test_smoke_contract.py
python3 Scripts/test_ui_contract.py
bash Scripts/test_cost_history_parser.sh
bash Scripts/test_provider_auth.sh
python3 Scripts/validate_provider_auth_catalog.py
swiftc -typecheck -target arm64-apple-macosx12.0 \
  Sources/CodexBarMonterey/MontereyCompat.swift \
  Patches/MontereyCompat.swift
~~~

之后会运行 menu target preflight、Scripts/build_universal.sh、macOS 12 compatibility/codesign 检查和离线 bundle smoke test。不要只因为某个 Python contract test 通过就认为 Universal app 可运行。

## 8. 0.6.0 release runbook

### 8.1 发布前确认

~~~bash
git status --short --branch
git fetch origin
git log --oneline origin/main..HEAD
git diff --stat origin/main...HEAD
~~~

确认：

- 所有 0.6.0 代码已经提交并推送到当前 feature branch；
- 不把 ENGINE_VERSION 从 v0.46.0 改成 0.6.0；它代表 bundled upstream engine 版本；
- 不需要把 Config/build.env.example 的 APP_VERSION=0.1.0 改成 0.6.0；workflow 会从 tag 推导版本，并在 CI 临时替换 build.env；
- 不提交真实的 Config/build.env、Sparkle 私钥或签名证书。

### 8.2 推荐的 Git 操作

当前 feature 分支的提交是 origin/main 的线性后续时，可用：

~~~bash
git switch main
git pull --ff-only origin main
git merge --ff-only origin/fix/deepseek-zai-dashboard
git push origin main

git tag -a v0.6.0 -m "CodexBar Monterey 0.6.0"
git push origin v0.6.0
~~~

如果仓库保护规则不允许直接推送 main，先通过 GitHub PR 合并 feature branch，再在合并后的 main 提交上创建 tag。不要在未合入 main 的 feature commit 上直接发布，除非你明确接受 appcast 阶段和正式分支不一致的风险。

tag 必须是 v0.6.0，不能只推 0.6.0：workflow 使用 v* trigger，并会将 v 去掉后设置 APP_VERSION=0.6.0。

### 8.3 GitHub Actions 配置

在仓库 Settings → Secrets and variables → Actions 配置：

必需/推荐：

- Repository variable BUNDLE_ID：正式 bundle identifier，例如 com.yourname.codexbar.monterey；
- Secret SPARKLE_PUBLIC_KEY；
- Secret SPARKLE_PRIVATE_KEY。

公开分发推荐再配置：

- DEVELOPER_ID_P12_BASE64
- DEVELOPER_ID_P12_PASSWORD
- CODE_SIGN_IDENTITY
- APPLE_ID
- APPLE_TEAM_ID
- APPLE_APP_SPECIFIC_PASSWORD

只有前三项会签名，只有后三项会 notarize；六项完整时才是面向普通用户的完整 Developer ID + notarization 路径。没有这些 secrets 时 workflow 仍可能完成 ad-hoc release，但安装时需要用户手动处理 Gatekeeper。

release.yml 会生成：

- releases/CodexBar-Monterey-0.6.0.zip
- releases/SHA256SUMS.txt
- 配置完整 Sparkle keys 时额外生成并发布 appcast.xml，然后更新 main 上的 appcast。

### 8.4 发布后验证

~~~bash
git ls-remote --tags origin v0.6.0
~~~

然后在 Actions 中确认 Publish GitHub Release 成功，检查 GitHub Release 的 zip/checksum/appcast 资产。下载 zip 后至少验证：

- Apple Silicon 和 Intel 机器均能打开；
- macOS 12 Monterey 能启动菜单栏应用；
- provider 配置、Refresh、Settings、Status Page、Usage Dashboard 正常；
- Codex、DeepSeek、z.ai、Moonshot 的当前 dashboard 数据不崩溃；
- 若配置 Sparkle，appcast URL、签名和升级链路可用；
- 若 ad-hoc，明确在 release note 中说明不是 notarized build。

### 8.5 常见失败处理

- contract/test 失败：先看 Actions 失败步骤；不要跳过测试直接重发。
- build/codesign 失败：确认 bundle 内 arm64/x86_64、Developer ID secrets 和证书密码；没有签名条件时应接受 ad-hoc 或补齐 secrets。
- notarization 失败：检查 Apple ID、Team ID、app-specific password 是否对应同一开发者账号；这不一定意味着编译失败。
- appcast 失败：先确认两个 Sparkle secrets、origin/main 可读写、workflow 的 GitHub token 有 contents write；GitHub Release 资产可能已经存在，修复后优先 rerun workflow，避免盲目重复创建同一 tag。
- 本地 Swift ModuleCache 失败：换到 CI/macOS SDK 验证；不要用清理整个用户目录等破坏性操作解决。

## 9. 后续 agent 的工作方式

1. 先读本文件，再检查 git status、git log -5、git branch -vv；不要假设快照中的 HEAD 仍然是当前 HEAD。
2. 修改 provider 数据时沿着 CLI → patch/env → CLIClient → parser → view → contract tests 全链路核对。
3. 修改 UI 时优先保持 Monterey 的 fixed-size popover、AppKit 生命周期和 accessibility；不要未经确认引入 macOS 14-only API。
4. 修改发布逻辑时先读完整 .github/workflows/release.yml、Scripts/build_universal.sh 和 Scripts/generate_appcast.sh。
5. 任何涉及真实发布、tag push、GitHub Release、证书或 notarization 的操作，都先给出将要触发的外部效果；除非用户明确要求，不要代替用户 push/tag。

