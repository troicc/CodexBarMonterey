# CodexBar Monterey 项目记忆 / Agent Handoff

> ⚠️ **记忆漂移提醒：本文件只是 2026-08-01 的人工快照，不是事实源。** 分支、HEAD、工作树、上游能力、依赖版本、CI 和发布状态都可能在下一次对话前改变。每次开始分析、修改、发布或接手任务时，必须先读取本文件，再用 `git status --short --branch`、`git log -5 --oneline --decorate`、`git branch -vv` 和当前代码/测试重新验证。发生冲突时，以工作树、代码、测试、CI 和 Git 历史为准，并在同一轮改动中同步修正本文件；不得仅凭模型记忆或本文件里的旧结论继续操作。

## 1. 当前状态速览

| 项目 | 当前值 |
| --- | --- |
| GitHub 仓库 | troicc/CodexBarMonterey |
| origin | https://github.com/troicc/CodexBarMonterey.git |
| 分支快照 | 2026-08-01 本轮从 `main@1e5f1b9` 开始原生状态菜单重构；实际分支必须运行 Git 命令确认 |
| 重构基线 | 1e5f1b9 — docs: record v0.7.0 install exception；本轮 UI/功能重构位于其后的工作树 |
| 工作树期望 | 本轮记录时包含尚未提交的原生菜单重构；接手时必须用 Git 重新确认归属，不能盲目覆盖 |
| 上游引擎常量 | ENGINE_VERSION = v0.46.0 |
| 当前正式 tag | 本轮开始时为 v0.7.0；用户已明确要求把当前超大重构发布为 v0.10.0，最终状态须以 Git/GitHub 复核 |
| 下一版本规则 | 当前发布目标为 v0.10.0；应用版本来自 tag，仍不得修改 ENGINE_VERSION |
| 最低系统 | macOS 12 Monterey |
| 架构 | Universal 2：arm64 + x86_64 |
| UI 技术 | AppKit 菜单栏壳 + SwiftUI 内容视图 |
| 发布入口 | .github/workflows/release.yml，由 v* tag push 触发 |

v0.7.0 原生 dashboard 重构从 `main@bed623c` 开始并已进入 `main`。本轮更接近上游的原生状态菜单/账号/状态告警重构从 `main@1e5f1b9` 开始；是否已提交、进入分支、通过 CI、打 tag 或正式发布，都必须通过 GitHub/Git 现状确认，不能从本快照推断。

## 2. 项目定位

这是一个面向 macOS 12 Monterey 的 CodexBar 兼容版本/移植版本。核心目标是：

- 在较旧 macOS 上保留菜单栏常驻、原生状态菜单、可选 dashboard、设置、状态页和登录启动能力；
- 复用或打包上游 CodexBarCLI 的 provider 数据引擎，而不是在 UI 中重复实现 provider API；
- 通过 Sparkle 2.9.4 提供整包更新；
- 产出 Apple Silicon 与 Intel 均可运行的 Universal 2 应用。

它不是上游 SwiftUI 产品的逐像素回移植。README 已明确接受以下取舍：不保证完整保留上游的 WidgetKit、全部 provider-specific 登录界面、所有 SwiftUI 设置细节和定制动画。

产品体验可以概括为：本项目偏“多 provider 的财务/用量总览”，上游 steipete/CodexBar 偏“provider 原生配额、状态与账号监控器”。

## 3. 代码架构与数据流

### 主链路

~~~text
菜单栏状态项
  -> MenuController / NativeMenuViews（默认原生 NSMenu）
  -> DashboardStore / CLIClient
  -> bundled CodexBarCLI --format json --json-only --status
  -> DashboardParser / typed provider payloads
  -> NativeMenuViews / DashboardViews
~~~

原则：UI 不直接请求 Codex、DeepSeek、z.ai 等 provider endpoint；所有 provider 访问、认证和状态采集尽量由 CLI 完成。修改数据字段时，优先确认 CLI JSON contract、patch 和 parser 是否同时更新。

### 关键文件

- Sources/CodexBarMonterey/MenuController.swift：菜单栏状态项、原生菜单、刷新调度、动作路由与运行时 UI smoke。
- Sources/CodexBarMonterey/NativeMenuViews.swift：跟随系统外观的菜单内 Overview、Provider 指标/额度/状态 hosted rows。
- Sources/CodexBarMonterey/ProviderAlertController.swift：服务故障/恢复和 quota 阈值的本地通知去重。
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
- Scripts/engine_source_fingerprint.py：对 ENGINE_VERSION、fetch/patch 脚本和 patch 文件做确定性指纹，防止本地打包复用旧 provider engine。
- Scripts/generate_appcast.sh：使用 Sparkle 工具生成带签名的 appcast.xml。
- .github/workflows/release.yml：完整 release pipeline，发布 zip、checksum、可选 appcast/notarization。
- Tests/CodexBarMontereyTests/CoreBehaviorTests.swift：SwiftPM 行为测试；CI 以 release 配置运行。

### 当前数据能力

- Codex / Claude：可使用官方 cost/history 数据。
- DeepSeek / Moonshot / MiMo：支持 prepaid balance delta 方式的本地花费估算。
- Kimi、z.ai、Qwen、Qwen Cloud、Alibaba 变体：主要是 quota/balance-only，不能假设有官方历史成本。
- z.ai：live usage payload 优先；没有 live 数据时，可用 LocalQuotaTrendStore 的本地采样回退。
- DeepSeek / z.ai / Moonshot 的 provider dashboard 已包含在当前 v0.6.0 基线中。
- LocalSpendHistoryStore 的数值应标为 estimate；它是余额差估算，不等于 provider 官方账单。
- 本地历史按 snapshot account ID 隔离；长离线间隔或跨午夜余额下降标记为 unassigned，不计入当天/30 天估算。
- provider cost 命令没有 account selector；同一 provider 同时出现多个账号时，DashboardStore 会抑制 provider 级 supplemental cost，避免把同一份账单展示到多个账号。

## 4. 当前 UI 事实

代码对应的主要交互如下：

- 状态项直接绑定原生 `NSMenu`，左键/右键都采用系统菜单跟踪；不再把固定深色 popover 作为默认入口。
- 合并模式显示系统外观的 Overview hosted row、可配置 3/6/9/12 个 Provider/账号摘要，以及包含全部账号的 Providers 子菜单。
- 每个 Provider 子菜单显示服务状态、连接错误、最多四个菜单内指标、最多四条菜单内 quota、已用/剩余百分比、重置时间和 pace；完整指标与 quota 不再在 parser 层截断。
- 原 328×520 多 Provider dashboard 与 All Providers 窗口继续作为可选入口；“Open Detailed Dashboard” 已改为直接锚定状态栏图标、跟随系统外观的单 Provider `NSPopover`，不再新建浮动窗口。
- 状态项可选 usage meter、已用百分比、剩余百分比或 provider 图标；支持合并/每账号分离。
- Settings 改为 General、Menu Bar、Notifications、Providers、Advanced 侧边栏；可控制刷新、菜单信息密度、账号名、状态、quota 表达和通知阈值。
- 刷新支持 Manual、固定间隔与 Adaptive；Adaptive 在最近打开菜单后为 2 分钟、warm 为 5 分钟、idle 为 15 分钟、低电量为 30 分钟，并可打开菜单时刷新。
- Provider status 已进入 dashboard/header/menu/status-item tooltip；incident、恢复和 quota 阈值可发送 opt-in 本地通知，首次刷新只建立 baseline。
- DeepSeek/Venice tokenAccounts 可在设置中新增并事务验证、查看、切换和确认删除；设置还显示真实 snapshot 的账号、来源、套餐、quota 和连接/服务状态。
- DashboardActionRow 继续绑定真实的 ⌘R、⌘,、⌘Q；单 Provider 详情 popover 观察共享 DashboardStore，刷新失败保留旧数据，刷新请求继续 coalesce。

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
- 原生 NSMenu 已成为默认交互，同时保留适合财务/趋势查看的独立 dashboard；旧系统不必在两者中二选一。
- Token Account 的 Save & Verify、切换和删除均有完整配置回滚，避免半写入凭据。

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

## 6. 2026-08-01 原生体验重构完整记录

这一节记录从 `main@bed623c` 开始的整轮改动。后续若代码与本节不一致，仍以代码、测试和 Git 历史为准，并立即更新本节。

### 6.1 原生 macOS 交互与窗口

- `MenuController` 现在区分左键与右键/Control-click：左键打开 SwiftUI popover，右键显示原生 `NSMenu`；应用主菜单提供 About、Settings、Refresh、Check for Updates 和 Quit，并绑定真实的 ⌘,、⌘R、⌘Q。
- 状态栏项目按 snapshot/account 使用稳定 autosave ID；tooltip、accessibility label/value 包含账号、刷新和错误状态。任何入口触发刷新后都会重建并重绘状态栏项目，避免分离图标模式出现旧账号项目。
- `DashboardViews` 增加 hover/pressed 反馈、真实 keyboard shortcuts、VoiceOver 描述、百分比/负数防御性 clamp、滚动详情，以及刷新失败时“保留旧数据 + 最后成功时间 + Retry”的 stale banner。
- provider switcher 仅在同一 provider 出现多账号时显示账号副标题；header、详情窗和状态栏 tooltip 都显示账号身份。
- `ProviderDetailPanelController` 改为观察共享 `DashboardStore` 的实时详情，不再保存打开瞬间的静态 dashboard；账号被禁用后显示明确空状态。
- Settings、All Providers 和 Provider Detail 窗口均使用 frame autosave；首次详情窗仍定位到屏幕右上方。
- 删除已无调用的 `ProviderMenuView.swift`、`QuotaBarView.swift`，以及旧 text/cost/detail/copy JSON 死代码，避免两套 UI 状态继续漂移。

### 6.2 刷新状态、竞态和多账户隔离

- `ProviderSnapshot.id` 现在综合 provider、usage identity/account email、顶层 account 和 organization，并统一大小写，避免同一 provider 的不同账号共用 dashboard/cache/status item。
- `DashboardStore` 只使用精确 snapshot ID 保存 dashboard，不再写入 provider ID 别名；排序按 provider、账号和稳定 ID 进行。
- 刷新期间的新请求通过 `refreshPending` 合并为下一轮，不再静默丢弃；失败时保留上次成功数据、`lastSuccessfulRefresh` 和错误状态。
- supplemental enrichment 使用 `snapshotGeneration` 与按 generation 标记的 loading 状态，旧异步结果不能覆盖新刷新；富化开始时会重新解析当前代 snapshot，避免旧账号对象进入新代 dashboard。
- 每次刷新会清理已消失账号/provider 的 supplemental cache。上游 `cost --provider` 没有 account selector，因此同一 provider 出现多个账号时主动禁用 provider 级 cost enrichment，防止一份账单复制到多个账号。

### 6.3 本地额度与消费数据可信度

- `LocalQuotaTrendStore` 升级到 `zai-five-hour-trend-v3.json`，按 provider + account hash 隔离；目录/文件权限为 0700/0600，忽略重复或倒序时间，统一排序、30 天清理并限制每账号 240 个样本。
- z.ai 趋势继续只选择语义上的 300 分钟窗口，不会把 MCP/月度或最大百分比误当五小时 quota。
- `LocalSpendHistoryStore` 使用共享稳定 hash 按 provider/account/currency 建账。五分钟内快速刷新不再替换原始基线，因此不会吞掉首次余额下降。
- 超过两小时或跨午夜的余额下降无法诚实归属到某一天，改为 `unattributedIntervals` 并从 today/30-day estimate 排除；UI subtitle 会明确显示 uncertain interval unassigned。
- spend ledger 使用 0700 目录、0600 文件，保留 180 天；余额增加、充值、退款或赠送额度变化继续作为 adjustment 排除，不写成负消费。

### 6.4 Provider 配置事务与设置体验

- `CodexBarConfigStore` 新增完整文件 backup/restore：原文件按原内容原子恢复并设为 0600；事务前不存在的配置在回滚时会删除，未知 root/provider 字段仍保留。
- `CLIClient.saveCredential` 将写入、`config validate`、provider probe 合并为单一事务；任何阶段失败都会恢复旧配置，回滚失败会返回组合错误。日志只记录 provider ID，不输出凭据。
- Settings 的 Save & Verify 只有在整个事务成功后才清空字段和广播刷新；busy 状态在创建 Task 前同步设置，防止双击并发。
- provider reload 做合并保护；清浏览器缓存后会刷新 dashboard；清空凭据时同步关闭 reveal；设置与 provider 控件在操作期间禁用。
- 原本指向不存在日志目录的按钮改为打开 Console.app，并提示搜索 `CodexBarMonterey`；dashboard 刷新失败使用 unified logging/`NSLog` 记录诊断。

### 6.5 构建、Universal 2 与发布链路

- `Scripts/engine_source_fingerprint.py` 对 `ENGINE_VERSION`、自身、fetch/patch 脚本、MontereyCompat 和所有 patch 做确定性 SHA-256 指纹。
- `fetch_engine.sh` 写入 `.engine-version` 和 `.source-fingerprint`；`build_engine.sh` 检测版本/指纹不一致时重新拉取 vendor；`build_app.sh` 每次都运行增量 engine build，不再静默复用陈旧 helper。
- `build_universal.sh` 会检查 arm64/x86_64 两边所有 Mach-O 组件是否一一对应，并在签名前递归验证输出 bundle 的每个 Mach-O 都同时包含 arm64 与 x86_64。
- `smoke_test_app.sh` 同样递归检查全部 framework/XPC/updater/helper，而不只检查主程序和 CLI。
- `appcast.xml` 从 `.gitignore` 移除，确保 Sparkle feed 能提交到 `main`；release workflow 使用 `git add --force` 保证生成产物可追踪。
- release workflow 验证 tag commit 属于 `origin/main`，用 concurrency 串行化 appcast 发布，使用独立 `mktemp` worktree，并在 push appcast 前 rebase 最新 main。
- build/release workflows 均运行 release contract 与 `swift test -c release`；release 仍从 tag 推导应用版本，不能为了 App release 修改 `ENGINE_VERSION`。

### 6.6 新增与扩展的测试、文档

- `Package.swift` 新增 `Tests/CodexBarMontereyTests/CoreBehaviorTests.swift`，覆盖账号身份、快速采样/长间隔不确定性和配置备份恢复。
- 新增 `Scripts/local_spend_history_regression.swift`，覆盖快速刷新基线、多账号隔离、长间隔、跨午夜和 0600 权限。
- quota/provider config 回归扩展到多账号、重载隔离、倒序时间、未知字段保留、旧配置恢复和新配置删除。
- 新增 `Scripts/test_release_contract.py`，约束 appcast、tag/main、release concurrency、Universal 全组件验证以及 engine version/fingerprint。
- Swift 回归 shell 和 patcher 使用临时 ModuleCache，可在本机 Swift 5.6 下运行；README 中英文版已说明本机轻量验证与 GitHub Swift 6.2 完整构建的边界。
- `PROJECT_MEMORY.md` 本身加入本节和顶部防漂移警告；以后任何 materially changed architecture/release behavior 都应与代码在同一提交里更新记忆。

### 6.7 本轮验证基线

- 已通过 UI、release、offline smoke contract；Monterey patcher 完成 38 项变换并通过 Core/CLI semantic regression 与 API 扫描。
- 已通过 typed cost parser、z.ai quota、local spend、provider auth/config 和 66-provider catalog audit。
- 已通过 Shell/Python/YAML/Swift parse、`git diff --check`，以及 Swift 5.6 + macOS 12 SDK 的 dashboard/core typecheck。
- GitHub Actions branch run `30693628097` 已在提交 `b9ad530` 上完整成功，包含 Swift package tests、Universal build、最低系统检查、offline smoke 和 artifact upload；用户随后已自行安装该 branch artifact。
- `v0.7.0` tag 已推送并触发 Release run `30694411624`。用户明确要求本次只记录流程，不继续跟踪该 Release，也不重复下载、替换或启动应用；后续 agent 不得把下面的标准安装 runbook 误当成本次遗留任务。
- 本机没有执行完整 SwiftPM 6.2、Sparkle 依赖解析和双架构 bundle；GitHub Actions 中的 `swift test -c release`、preflight、Universal build、codesign/compat/offline smoke 才是最终构建门禁。

## 7. 已知风险、文档差异和不要误判的地方

1. 图形化详情页只映射 dashboard parser 支持的字段；parser 已不再固定截断 4 metrics/8 quota，但未识别的 provider-specific 语义仍需通过 bundled CLI 查看。
2. release workflow 会验证 tag commit 属于 `origin/main`，并串行化 appcast 发布；`appcast.xml` 必须保持可追踪，不能重新加入 `.gitignore`。
3. 没有 SPARKLE_PUBLIC_KEY / SPARKLE_PRIVATE_KEY 时，zip/checksum 仍可能发布，但不会生成签名 appcast，Sparkle 自动更新链路不完整。本轮用户明确暂缓建立安全自动更新链路；不要把 UI/功能重构误写成已经修复该问题。
4. 没有 Developer ID 签名和 Apple notarization secrets 时，workflow 会使用 ad-hoc signing；公开分发时会遇到 Gatekeeper 信任/安装体验问题。
5. 本机 Swift 5.6 不能读取 `swift-tools-version: 6.2` manifest；轻量 Swift 回归脚本与 patcher 已使用临时 ModuleCache，可本地运行，但完整 App/Sparkle 编译仍以 macOS 26 CI 为 release gate。
6. 原生菜单为保持可读性只预览前四个 metrics/quota，但完整模型和详情页保留全部已解析字段；如果新增 provider 字段，先检查 parser 的 typed path、generic fallback 和菜单/详情两级展示是否都合理。
7. 本地 spend history 是余额差估算，不应在 UI 或 release note 中写成 provider 官方账单。
8. 通知只对刷新后的状态转移/阈值跨越触发，首次成功刷新只建立 baseline；不要改成每次启动重放当前 incident/quota，否则会制造通知风暴。
9. Token Account 删除会先显示确认框；配置变更通过 backup/validate/probe（切换）或 backup/validate（删除）事务执行。不得在 UI 中读取或回显 token 明文。
10. `UpdaterController` 在未链接 Sparkle 的直接本地构建中有明确的手工更新 fallback，正式 SwiftPM bundle 仍使用 Sparkle；这只是为了本机 UI 运行验证，不代表签名 appcast 已完成。
11. `Scripts/build_local_validation.sh` 只直接编译当前 UI shell，并从指定模板 App 复制 helper/Sparkle；它可以证明 UI、双架构主程序和实际菜单/popover 路径，但不能证明 pinned engine、正式 Sparkle linkage、notarization 或 Release archive。

## 8. 验证命令

低成本静态检查：

~~~bash
python3 Scripts/test_ui_contract.py
python3 Scripts/test_release_contract.py
python3 Scripts/test_monterey_patcher.py
Scripts/test_cost_history_parser.sh
Scripts/test_provider_auth.sh
bash -n Scripts/*.sh
~~~

Swift 5.6 本机 UI/交互验证包：

~~~bash
CODEXBAR_LOCAL_TEMPLATE_APP="/Applications/CodexBar Monterey.app" \
CODEXBAR_LOCAL_VERSION="0.10.0" \
Scripts/build_local_validation.sh
~~~

需要运行时菜单/popover smoke 时先退出已运行实例，并增加 `CODEXBAR_LOCAL_RUN_UI_SMOKE=1`。接受产物后使用 `Scripts/install_local.sh "/absolute/path/to/app"`；安装器会保留可恢复的旧 App 备份。

release workflow 还会执行：

~~~bash
python3 Scripts/test_monterey_patcher.py
python3 Scripts/test_smoke_contract.py
python3 Scripts/test_ui_contract.py
python3 Scripts/test_release_contract.py
bash Scripts/test_cost_history_parser.sh
bash Scripts/test_provider_auth.sh
python3 Scripts/validate_provider_auth_catalog.py
swiftc -typecheck -target arm64-apple-macosx12.0 \
  Patches/MontereyCompat.swift
~~~

配置构建后，CI 还会运行 `swift test -c release`、menu target preflight、`Scripts/build_universal.sh`、macOS 12 compatibility/codesign 检查和离线 bundle smoke test。不要只因为某个 Python contract test 通过就认为 Universal app 可运行。

## 9. 下一版本 release runbook

### 9.1 项目版本规则

- Git tag 永远带 `v` 前缀，例如 `v0.7.0`；应用和 GitHub Release 显示版本为 `0.7.0`。
- 小版本优化、修复、测试或文档增强增加个位数（patch）：`0.7.0 → 0.7.1 → 0.7.2`。
- 较大的功能或架构重构增加十位数（minor），并把个位数归零：`0.7.x → 0.8.0`。
- 2026-08-01 这轮原生体验、多账户、数据可信度和发布链路重构命名为 `0.7.0`，对应 tag `v0.7.0`。
- `ENGINE_VERSION` 只代表 bundled upstream provider engine，不能拿它充当 App 版本，也不能为了 App release 修改它。

### 9.2 发布前确认

~~~bash
git status --short --branch
git fetch origin
git log --oneline origin/main..HEAD
git diff --stat origin/main...HEAD
~~~

确认：

- 下一版本代码已经提交并位于 `main` 的目标 release commit；
- 不要为了应用 release 改 `ENGINE_VERSION`；它只代表 bundled upstream engine 版本；
- 不需要把 `Config/build.env.example` 的 `APP_VERSION` 改成 release 版本；workflow 会从 tag 推导，并在 CI 临时替换 build.env；
- 不提交真实的 Config/build.env、Sparkle 私钥或签名证书。

### 9.3 发布型 push 必须完成的闭环

用户明确要求发布时，push 分支不是终点，必须在同一轮完成并核验以下链路：

1. 工作分支提交并 push；
2. 在该分支手动触发 `build.yml`，等待 Swift tests、Universal build、macOS 12 compatibility 和 offline smoke 全部成功；
3. 把验证过的提交合并/快进到 `main` 并 push；
4. 在同一个 main release commit 上创建版本 tag 并 push，立即触发 `release.yml`；
5. 等待 GitHub Release、zip 和 SHA256SUMS 完成；
6. 下载正式 Release 资产、校验、替换 `/Applications` 中的应用并启动验证。

也就是说，对于发布型交付，“push + release + download/install verification”是一项完整任务，不能像普通 WIP 分支那样只推代码就结束。若用户只明确要求保存 WIP 分支，则不要擅自 release。

本次 `v0.7.0` 是明确例外：用户已经自行安装 branch artifact，随后要求只把未来流程写入记忆，并明确不需要继续追踪 Release 或再次安装。因此本次不得执行第 5/6 步；Release run 是否最终成功留待未来有实际需要时再检查。

本次 `v0.10.0` 是另一项明确例外：用户要求完成分支 build、main、tag 和 GitHub Release 核验，但明确“不用下载”Release 资产；本机安装改用精确源码生成并通过 runtime smoke 的本地 Universal 2 验证包。不得在完成后又下载 Release zip 覆盖本机。

以 `v0.7.0` 为例：

~~~bash
git switch main
git pull --ff-only origin main
git merge --ff-only codex/native-experience-refactor
git status --short
git push origin main
git tag -a v0.7.0 -m "CodexBar Monterey 0.7.0"
git push origin v0.7.0
~~~

如果仓库保护规则要求 PR，先合并，再在合并后的 `main` 提交上创建 tag。workflow 会直接拒绝不属于 `origin/main` 的 release tag。

tag 必须以 `v` 开头并符合语义版本，例如 `v0.7.0`，不能只推 `0.7.0`。

### 9.4 GitHub Actions 配置

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

- releases/CodexBar-Monterey-X.Y.Z.zip
- releases/SHA256SUMS.txt
- 配置完整 Sparkle keys 时额外生成并发布 appcast.xml，然后更新 main 上的 appcast。

### 9.5 下载、校验并替换本机应用

正式安装优先使用 tag workflow 生成的 GitHub Release zip，不要把普通 branch build artifact 当作最终发布包。下载后先校验 checksum 和解压内容，再停止旧进程与删除旧 App；删除目标必须始终是完整、显式路径 `/Applications/CodexBar Monterey.app`。

以下命令是**未来 release 的标准模板，不是本次待执行任务**。本次 `v0.7.0` 用户已直接安装，除非用户再次明确要求，不得重复运行这些安装/删除命令。

以 `v0.7.0` 为例：

~~~bash
INSTALL_TMP="$(mktemp -d /private/tmp/codexbar-release-XXXXXX)"
gh release download v0.7.0 \
  --pattern "CodexBar-Monterey-0.7.0.zip" \
  --pattern "SHA256SUMS.txt" \
  --dir "$INSTALL_TMP"

cd "$INSTALL_TMP"
shasum -a 256 -c SHA256SUMS.txt
mkdir -p "$INSTALL_TMP/unpacked"
ditto -x -k "CodexBar-Monterey-0.7.0.zip" "$INSTALL_TMP/unpacked"
ls -ld "$INSTALL_TMP/unpacked/CodexBar Monterey.app"

pkill -x CodexBarMonterey 2>/dev/null || true
rm -rf "/Applications/CodexBar Monterey.app"
ditto "$INSTALL_TMP/unpacked/CodexBar Monterey.app" "/Applications/CodexBar Monterey.app"
xattr -dr com.apple.quarantine "/Applications/CodexBar Monterey.app"
open "/Applications/CodexBar Monterey.app"
~~~

安装后检查 `/Applications/CodexBar Monterey.app/Contents/Info.plist` 的版本、codesign、arm64/x86_64 slices 和进程状态；确认新版本能打开并刷新 provider 后，临时下载目录才可删除。

### 9.6 发布后验证

~~~bash
git ls-remote --tags origin vX.Y.Z
~~~

然后在 Actions 中确认 Publish GitHub Release 成功，检查 GitHub Release 的 zip/checksum/appcast 资产。下载 zip 后至少验证：

- Apple Silicon 和 Intel 机器均能打开；
- macOS 12 Monterey 能启动菜单栏应用；
- provider 配置、Refresh、Settings、Status Page、Usage Dashboard 正常；
- Codex、DeepSeek、z.ai、Moonshot 的当前 dashboard 数据不崩溃；
- 若配置 Sparkle，appcast URL、签名和升级链路可用；
- 若 ad-hoc，明确在 release note 中说明不是 notarized build。

### 9.7 常见失败处理

- contract/test 失败：先看 Actions 失败步骤；不要跳过测试直接重发。
- build/codesign 失败：确认 bundle 内 arm64/x86_64、Developer ID secrets 和证书密码；没有签名条件时应接受 ad-hoc 或补齐 secrets。
- notarization 失败：检查 Apple ID、Team ID、app-specific password 是否对应同一开发者账号；这不一定意味着编译失败。
- appcast 失败：先确认两个 Sparkle secrets、origin/main 可读写、workflow 的 GitHub token 有 contents write；GitHub Release 资产可能已经存在，修复后优先 rerun workflow，避免盲目重复创建同一 tag。
- 完整本地 SwiftPM 构建失败：先确认 Xcode/Swift 是否达到 6.2；Swift 5.6 只运行轻量回归，完整验证交给 CI。不要用清理整个用户目录等破坏性操作解决。

## 10. 后续 agent 的工作方式

1. 每次都先把本文件视为“可能已漂移”，再读本文件并检查 git status、git log -5、git branch -vv；不要假设快照中的 branch、HEAD、CI、tag 或发布状态仍然成立，也不要仅凭历史对话继续操作。
2. 修改 provider 数据时沿着 CLI → patch/env → CLIClient → parser → view → contract tests 全链路核对。
3. 修改 UI 时优先保持默认原生 NSMenu、可选 fixed-size dashboard、AppKit 生命周期和 accessibility；不要未经确认引入 macOS 14-only API。
4. 修改发布逻辑时先读完整 .github/workflows/release.yml、Scripts/build_universal.sh 和 Scripts/generate_appcast.sh。
5. 任何涉及真实发布、tag push、GitHub Release、证书或 notarization 的操作，都先给出将要触发的外部效果；除非用户明确要求，不要代替用户 push/tag。
6. 架构、数据 contract、关键交互、验证门禁或 release runbook 发生实质变化时，必须在同一提交更新本文件；不能把“以后再补记忆”留给下一次对话。

## 11. 2026-08-01 原生状态菜单与功能完善重构

本节记录从 `main@1e5f1b9` 开始、最终由用户指定为 v0.10.0 的大型重构。用户明确把“可工作的安全自动更新链路”移出本轮范围；本轮完成标准是更接近上游的原生菜单、信息展示、菜单栏、账号认证和状态告警，并证明应用可编译、启动和使用真实 helper 构建菜单。

### 11.1 默认交互与信息展示

- `NSStatusItem.menu` 现在直接挂接动态 `NSMenu`；`MenuController` 实现 `NSMenuDelegate`，菜单打开前按最新 store 状态重建，不再通过左键 action 默认打开 popover。
- 合并模式使用 `NativeMenuHeaderView` + `NativeMenuOverviewView`，默认展示 6 个账号快照，可配置 3/6/9/12；全部账号继续位于 Providers 原生子菜单。
- Provider 子菜单使用 `NativeMenuProviderCardView`，展示账号、来源、连接错误、Provider status、metrics、quota、reset 和 pace，并提供详细 popover、旧多 Provider popover、Usage Dashboard、Status Page、Authentication & Accounts、Refresh、Settings 等原生动作。
- 菜单内 hosted rows 跟随系统明暗外观；旧多 Provider `DashboardViews` 继续固定深色，而单 Provider 详情已改为系统外观 popover。
- `DashboardParser` 不再在模型层执行 metrics `prefix(4)` 或 quota `prefix(8)`；菜单预览前四项，详细 Provider 面板展示完整已解析数组。
- `DashboardQuotaLane` 保留 `resetsAt/windowMinutes`，可计算 remaining、reserve、on pace、over pace 和预计提前耗尽时间。

### 11.2 菜单栏与刷新灵活度

- `MenuBarDisplayStyle`：meter、used percentage、remaining percentage、provider icon；所有样式在 incident/connection error 时显示注意标记。
- `MenuQuotaPresentation`：菜单统一切换 used/remaining；账号名、summary metrics、reset/pace、service status、Overview 行数均可独立开关。
- `RefreshMode`：Manual、Fixed、Adaptive。Adaptive 当前策略为 recent menu 2m、warm 5m、idle 15m、Low Power Mode 30m；`refreshOnMenuOpen` 默认开启且 60 秒内不会重复刷新。
- 旧 `showPercentage` preference 保留兼容迁移，但新代码使用 `menuBarDisplayStyle`。

### 11.3 账号认证和 Provider 设置

- Settings 从顶部分段控件改为 General、Menu Bar、Notifications、Providers、Advanced 左侧导航，并增加 Provider 搜索。
- Providers 的 Connection & service 区域直接观察共享 `DashboardStore`，显示已连接账号、source、plan、quota、错误和 status，不再只显示通用认证说明。
- `CodexBarConfigStore` 能以不暴露 token 的 `ConfiguredProviderAccount` 列出 tokenAccounts，并支持切换 activeIndex、删除指定账号、保持未知字段和 0600 权限。
- `CLIClient.activateConfiguredAccount` 使用 backup → mutate → validate → provider probe → rollback；删除使用 backup → mutate → validate → rollback。UI 删除前必须经 `NSAlert` 确认。
- DeepSeek/Venice 的设置页显示 Saved token accounts，可新增（沿用 Save & Verify）、切换和删除。

### 11.4 Provider 状态与本地通知

- `ProviderServiceHealth` 把 Statuspage 风格的 none/minor/major/critical 和描述归一化为 operational/degraded/outage/unknown。
- status 进入原生菜单 header/Overview/Provider card、旧 dashboard header/incident banner、status-item tooltip/accessibility。
- `ProviderAlertController` 使用 `UNUserNotificationCenter`，支持服务异常、恢复和 quota 阈值；默认关闭，开启时请求系统权限。
- alert 状态以 snapshot ID 隔离；首次刷新只记录 baseline，后续只在状态转移或阈值从下向上跨越时通知。quota 使用完整 parsed dashboard lanes 的最大值，不只看 primary/secondary/tertiary。

### 11.5 本机编译和真实运行验证

- 本机 Apple Swift 5.6.1 已对全部 `Sources/CodexBarMonterey/*.swift` 执行 macOS 12 typecheck，并直接链接 AppKit/SwiftUI/UserNotifications 分别生成 arm64 与 x86_64 可执行文件；两者已用 `lipo` 合成 Universal 2 主程序。仅有既存 AppKit protocol actor warning 和 `@preconcurrency` remark，无 type error。
- `UpdaterController` 使用 `#if canImport(Sparkle)`：SwiftPM 正式构建继续链接 Sparkle；不解析 SwiftPM/Sparkle 的直接本地构建显示“手工更新”提示，从而可以独立验证 UI。本 fallback 不建立或声称建立安全更新链路。
- 临时测试 bundle 复制了当前 `/Applications/CodexBar Monterey.app` 的真实 bundled helper，替换为本轮直接编译的 UI binary 并 ad-hoc 重签。普通启动后进程持续存活，系统日志没有 crash/runtime exception。
- 该临时 bundle 的 helper 来自已安装应用，不是本轮重新从 `ENGINE_VERSION` 构建，因此它打印的 app/helper 版本和 65-provider registry 不能证明当前 vendor engine 构建结果；正式 CI 仍必须重新构建 pinned engine。源码认证 catalog 的独立审计结果为 66 explicit profiles。
- 最终临时 bundle 的主程序、CodexBarCLI 和全部 Sparkle Mach-O 都包含 `x86_64 arm64`，`Scripts/check_macos12_compat.sh` 完整通过，主程序两 slice 的 `minos` 均为 12.0。`Scripts/smoke_test_app.sh` 的 bundle/codesign/architecture/deployment/registry 阶段均通过；最后 live provider probe 因沙箱网络返回 `Operation not permitted` 而退出 1，不能把它记成网络数据验证成功。
- `CODEXBAR_MONTEREY_UI_SMOKE_OUTPUT=/private/tmp/...` 会在应用内等待真实 provider refresh、构建 Overview 和 Provider 原生菜单、检查 hosted row 尺寸、Providers 子菜单、认证动作、状态项 menu 与 Settings hierarchy，然后写一行结果并自动退出。本轮主体实现的真实运行结果：`PASS | snapshots=3 overviewItems=11`。随后只修改了 hosted-row smoke 尺寸断言、alert 最大 quota 取值、状态分类边界、SwiftUI binding 写法和文档；最终精确源码已重新 link 成功，但再次启动请求因外部执行额度限制被环境拒绝，不能把该拒绝写成代码运行失败，也不能声称精确末版完成了第二次 GUI 启动。
- System Events 没有系统辅助功能授权，因此没有通过 AppleScript 模拟点击；应用内 smoke 检查的是同一 `populateOverviewMenu/populateProviderMenu` 生产路径，不是复制的测试实现。

### 11.6 本轮验证基线

- `python3 -B Scripts/test_ui_contract.py`
- `python3 -B Scripts/test_release_contract.py`
- `python3 -B Scripts/validate_provider_auth_catalog.py`（66 explicit providers）
- `bash Scripts/test_provider_auth.sh`（包含多 token account 列出/切换/删除和 status classification）
- `bash Scripts/test_cost_history_parser.sh`
- `xcrun swiftc -typecheck -target arm64-apple-macosx12.0 ... Sources/CodexBarMonterey/*.swift`
- 直接 arm64 AppKit/SwiftUI/UserNotifications link build
- 直接 x86_64 link build、lipo Universal 2、临时 bundle macOS 12/codesign/全 Mach-O architecture validation
- 临时 `.app` 普通启动 + 真实 helper 内置 UI runtime smoke PASS

SwiftPM 6.2 tests、Universal 2、Sparkle framework、Intel slice 和最终 bundle smoke 仍必须由新版 Xcode/GitHub Actions 证明；本机 Swift 5.6 的成功不能替代这些门禁。用户本轮没有授权 push/tag/release，也没有要求覆盖 `/Applications` 中的现有安装，因此不得把临时测试 bundle 误记为正式安装或发布。

### 11.7 2026-08-01 实机反馈修正

- `ProviderSnapshot.headlineQuotaWindow` 为紧凑 UI 定义单一代表额度：z.ai 按 `windowMinutes == 300` 选择 5h 窗口，旧 payload 只回退到 `usage.primary`；MCP/月度即使百分比更高也不会抢占 Overview、状态项、tooltip、Provider 标题或 switcher 的主值。
- z.ai Overview 会明确显示 `5h` 标签；完整 Provider 卡仍展示所有 quota，并把 5h lane 排在前面。通知阈值仍检查所有额度的最大值，避免遗漏 MCP/月度告警。
- `ProviderDetailPopoverController` 以 transient `NSPopover` 锚定最近打开菜单的 `NSStatusBarButton`；详情使用系统明暗外观、完整 metrics/quota、刷新、网页 dashboard、状态页和设置入口，不再创建单独的浮动 `NSPanel`。
- `DashboardHistoryContext` 区分 daily usage、hourly usage、daily estimated spend 和本地 5h quota samples。Codex/DeepSeek 等同时有 tokens/cost 时，上方柱图明确为 `Daily tokens`，下方折线明确为 `Daily cost`，各自独立缩放；只有一种序列时只画一张图，不再重复同一数据。
- 本次反馈修正已通过 Swift 5.6 + macOS 12 arm64 全源码 typecheck、UI/release/provider-auth contract、cost history、z.ai 5h trend、local spend、66-provider catalog audit 和 `git diff --check`。
- 精确末版已分别直接链接 arm64/x86_64 并合成临时包 `/private/tmp/codexbar-zai-popover.ekYC0y/CodexBar Monterey 5h Popover Test.app`；主程序及 bundle 内全部 Mach-O 均为 Universal 2，ad-hoc codesign、macOS 12 compatibility 和 offline smoke 通过。内置 UI runtime smoke 已实际 show/close provider detail popover，并返回 `PASS | snapshots=3 overviewItems=11`。该包仍复用已安装 App 的旧 helper/Sparkle，只适合本机 UI/交互验证，不等同于 CI 正式产物。

### 11.8 v0.10.0 本机构建与发布要求

- 新增 `Scripts/build_local_validation.sh`，把此前手工执行的 Swift 5.6 双架构 UI link、`lipo`、模板 bundle 复制、版本写入、ad-hoc 重签、macOS 12 检查和 offline smoke 固化为可重复入口；可选 `CODEXBAR_LOCAL_RUN_UI_SMOKE=1` 会运行真实菜单和详情 popover smoke。
- `Scripts/install_local.sh` 现在接受任意已验签 App 的绝对路径；替换 `/Applications/CodexBar Monterey.app` 前先把旧 App 移到 `/private/tmp/codexbar-install-backup.*`，复制或验签失败会自动恢复。
- 本地验证包只更新 UI 主程序，helper/Sparkle/Info 基础来自模板，不能作为 release provenance。完整 `v0.10.0` 仍必须经过分支 `build.yml`、main、tag `release.yml` 和 GitHub Release 资产存在性核验。
- `Scripts/build_local_validation.sh` 已从精确工作树生成 `/private/tmp/codexbar-local-validation.hTvb8O/CodexBar Monterey.app`：显示版本 0.10.0、`x86_64 arm64`、ad-hoc codesign、macOS 12/offline smoke 和真实菜单/详情 popover runtime smoke 均通过，后者返回 `PASS | snapshots=3 overviewItems=11`。
- 上述本地包已安装为 `/Applications/CodexBar Monterey.app` 并成功启动（验证时 PID 98661）；被替换的 0.1.0 App 可从 `/private/tmp/codexbar-install-backup.Irp3tx/CodexBar Monterey.app` 恢复。安装包仍继承模板 helper/Sparkle，不能误记为 GitHub Release 资产。
- 用户明确要求发布 `v0.10.0`，本次不下载 GitHub Release 资产。最终 commit、Actions run 和 Release 状态须在完成后补记。
