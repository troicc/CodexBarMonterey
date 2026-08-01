# CodexBar Monterey Full

这是面向 **macOS 12 Monterey** 的 CodexBar 兼容工程。目标不是只支持 Codex，而是保留上游 CodexBar 的完整 provider 数据引擎和自动更新能力，只替换无法在 Monterey 上运行的 macOS 14 UI 层。

当前固定的上游引擎版本见 `ENGINE_VERSION`。构建时会拉取该 tag 的 `CodexBarCore + CodexBarCLI`，因此 provider 列表、抓取器、解析器、认证来源、状态探针和配置结构都由上游维护，而不是在本项目里手工复制一份 provider 清单。

## 交付范围

### 保留

- 上游 tag 注册的全部 provider，以及未来新增 provider 的自动跟进机制。
- Web Cookie、CLI/RPC/PTY、OAuth、本地文件/数据库、API key、云凭据和状态页等上游数据来源。
- 与上游相同的 provider 启用/禁用、配置文件和 API key 存储命令。
- 浏览器 Cookie 刷新和缓存清理入口；刷新失败时由上游保证不覆盖原有有效缓存。
- 合并菜单栏图标或每 provider 独立图标。
- Session/weekly/extra quota、重置时间、credits、状态、账号、套餐和错误信息。
- 紧凑的图形化 provider 总览与详情页；数据仍来自上游 CLI JSON，原始输出可直接通过内置 helper 查询。
- macOS 原生应用菜单、右键菜单、真实的 ⌘R / ⌘, / ⌘Q、滚动详情和 VoiceOver 描述。
- 账户隔离的本地 quota/余额差历史；无法可靠归属的长间隔不会冒充当天消费。
- Claude、Codex、Cursor 等上游支持的 cost 详情。
- Sparkle 2.9.4 整包自动更新：AppKit shell、`CodexBarCLI`、Sparkle.framework 同步替换，不会出现 UI 与 provider 引擎版本错配。
- Universal 2：Intel 与 Apple Silicon。
- LaunchAgent 登录启动，避免依赖 macOS 13 的 `SMAppService`。
- 每日检查 CodexBar 上游 release，自动创建升级 PR。

### 不伪装成已经完全复刻

- 原版 SwiftUI 设置页、confetti、全部专属动画和每个 provider 的专属登录视图没有逐像素搬运。
- WidgetKit 桌面小组件不移植；它属于新系统 target，不是 macOS 12 可实现的同等功能。
- 某些 provider 的复杂账户管理或设备流仍需按上游文档在相应 CLI、浏览器或配置文件中完成。数据抓取能力保留，但并非所有专属登录 UI 都在这个 AppKit shell 内重做。

换句话说：**全部 provider 数据能力与自动更新是核心兼容目标；新系统专属视觉组件不是。**

## 架构

```text
CodexBar Monterey.app
├── Contents/MacOS/CodexBarMonterey       AppKit 菜单栏 shell，最低 macOS 12
├── Contents/Helpers/CodexBarCLI          上游完整 provider 引擎
└── Contents/Frameworks/Sparkle.framework 整包自动更新
```

刷新时 AppKit shell 默认执行：

```bash
CodexBarCLI --format json --json-only --status
```

这只查询配置中已启用的 provider，不会用 `--provider all` 强行同时访问几十个未配置服务。App 使用容错 parser 生成图形化 dashboard；如需查看尚未映射到卡片的原始 provider 字段，可直接运行内置 `CodexBarCLI`。

## 最快落地：用 GitHub Actions 构建

你的 Monterey 机器不需要升级，也不需要安装 Swift 6.2。编译发生在 GitHub 的 macOS 26 runner（Swift 6.2+），产物明确设置 `MACOSX_DEPLOYMENT_TARGET=12.0`，并用 `vtool` 检查 app bundle 内每个 Mach-O，包括 Sparkle 的 XPC/updater。

### 1. 建立你自己的公开仓库

默认的 GitHub Raw appcast 与 Release 下载不携带认证，因此仓库必须公开；私有仓库需要改用你自己的公开 HTTPS appcast/下载服务器。

解压后在目录内执行：

```bash
git init
git add .
git commit -m "Initial Monterey compatibility build"
git branch -M main
git remote add origin https://github.com/<你的账号>/<你的仓库>.git
git push -u origin main
```

### 2. 生成 Sparkle EdDSA 密钥

在工程目录直接执行（脚本优先使用 `gh`，没有时自动改用 macOS 自带的 `curl`）：

```bash
Scripts/setup_sparkle_keys.sh
```

脚本会：

1. 下载 Sparkle 2.9.4 官方工具（不依赖 Homebrew）；
2. 在登录钥匙串生成 EdDSA 密钥；
3. 输出 `SUPublicEDKey`；
4. 把私钥导出到 `~/.config/codexbar-monterey/sparkle-private-key`，权限为 `0600`。

私钥绝不能提交到仓库。

### 3. 配置 GitHub 仓库

在 GitHub 仓库的 **Settings → Secrets and variables → Actions** 中设置：

| 类型 | 名称 | 内容 |
|---|---|---|
| Repository variable | `BUNDLE_ID` | 例如 `com.yourname.codexbar.monterey` |
| Repository secret | `SPARKLE_PUBLIC_KEY` | `generate_keys` 输出的 `SUPublicEDKey` |
| Repository secret | `SPARKLE_PRIVATE_KEY` | 私钥文件的完整内容 |

没有 Apple Developer 账号也能构建个人使用的 ad-hoc 版本。正式公开分发再添加：

| Secret | 内容 |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | Developer ID Application 证书 P12 的 Base64 |
| `DEVELOPER_ID_P12_PASSWORD` | P12 密码 |
| `CODE_SIGN_IDENTITY` | 完整 Developer ID Application identity |
| `APPLE_ID` | notarization Apple ID |
| `APPLE_TEAM_ID` | Team ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password |

release workflow 在证书齐全时使用 hardened runtime、secure timestamp、notarization 和 stapling；否则明确发布 ad-hoc 构建。手工签名脚本按 Sparkle 官方要求由内到外重签 Installer/Downloader XPC、Autoupdate、Updater.app 和 framework，并保留 Downloader 的 entitlement。

### 4. 取得第一版应用

推送 `main` 后，打开 GitHub **Actions → Build Monterey Compatibility App**。成功后下载 artifact：

```text
CodexBar-Monterey.zip
```

解压并把 `CodexBar Monterey.app` 放入 `/Applications`。首次打开 ad-hoc 构建时，可能需要在 Finder 中右键 → Open；正式 Developer ID + notarized 版本没有这类自签名摩擦。

### 5. 发布自动更新

在 `main` 上准备好发布提交后，推送一个未使用过的语义版本 tag（例如 `v0.7.0`）。release workflow 会拒绝不属于 `origin/main` 的 tag：

```bash
git tag -a v0.7.0 -m "CodexBar Monterey 0.7.0"
git push origin v0.7.0
```

`release.yml` 会自动：

1. 构建 arm64 与 x86_64；
2. 递归合并 app 内所有 Mach-O，而不仅是主程序；
3. 验证最低系统版本；
4. 签名，并在凭据齐全时 notarize/staple；
5. 发布 GitHub Release ZIP；
6. 通过 stdin 把 Sparkle 私钥交给 `generate_appcast`；
7. 验证 appcast 中存在 EdDSA 签名；
8. 自动把 `appcast.xml` 提交到 `main`。

以后每次发布只需要在 `main` 的目标提交上提高版本并推送新 tag，例如：

```bash
git tag -a v0.7.1 -m "CodexBar Monterey 0.7.1"
git push origin v0.7.1
```

应用会按 `SUFeedURL` 自动检查、后台下载并安装完整新 bundle。

## Provider 配置

打开菜单栏 → **Settings → Providers**：

- 勾选或取消任意 provider；
- `Save & Verify` 以 `0600` 权限原子写入上游配置，再执行结构校验和 provider 实际探测；任一步失败都会恢复原配置；
- `Refresh browser session…` 调用上游 Cookie importer，并允许用户主动确认 Keychain 提示；
- `Clear browser cache` 只清理选定 provider 的缓存；
- `Open config file` 打开上游共用配置；
- `Provider docs` 打开上游文档。

配置路径：

```text
~/.config/codexbar/config.json
~/.codexbar/config.json   # 旧安装兼容
```

常用的 base URL、workspace、region、token account 和 manual cookie 可在设置中配置；更复杂的 organization/AWS 等字段继续使用上游 config schema。也可在内置 helper 上直接运行上游 CLI：

```bash
HELPER="/Applications/CodexBar Monterey.app/Contents/Helpers/CodexBarCLI"

"$HELPER" config providers --json --pretty
"$HELPER" config enable --provider grok
"$HELPER" config disable --provider cursor
printf '%s' "$OPENROUTER_API_KEY" | \
  "$HELPER" config set-api-key --provider openrouter --stdin
"$HELPER" config validate --format json --pretty
```

浏览器 provider：

```bash
"$HELPER" cookie refresh --provider cursor --allow-keychain-prompt
"$HELPER" cache clear --cookies --provider cursor
```

## 跟随上游 provider 更新

`ENGINE_VERSION` 固定到一个明确的 CodexBar release tag。`upstream-sync.yml` 每天查询上游最新 release：

- 有新 tag：更新 `ENGINE_VERSION` 并创建 PR；
- PR 自动运行 universal build 与 Monterey deployment-target 检查；
- 只有兼容构建通过才合并；
- 合并后推送你自己的 release tag，即通过 Sparkle 发给 Monterey 用户。

`fetch_engine.sh` 还会读取该 CodexBar tag 实际依赖的 SweetCookieKit 和 Commander 版本，而不是硬编码。Commander 本身在 0.2.1 的 manifest 中声明 macOS 14，因此脚本会把它固定到本地 checkout、改写上游依赖并与 CodexBar、SweetCookieKit 一起降到 macOS 12。脚本支持：

```text
Patches/CodexBar.patch
Patches/SweetCookieKit.patch
Patches/Commander.patch
```

如果未来上游在 Core/CLI 中引入 macOS 13/14-only API，CI 会直接失败；修复应写进对应版本化 patch，而不是静默发布坏包。

本地增量构建会对 `ENGINE_VERSION`、fetch/patch 脚本和所有兼容 patch 计算指纹。任一输入变化时会重新获取 vendor tree；即使已有 `build/engine/<arch>/CodexBarCLI`，打包也会重新走 Swift 的增量构建并复制当前引擎，避免 UI 与 helper 版本错配。

## 本地构建

完整 App 构建需要新版本 Xcode/Swift 6.2，但目标产物仍是 macOS 12。本机只有 Swift 5.6 时，可把 GitHub Actions 作为正式构建门禁，并先运行不依赖 SwiftPM 6.2 manifest 的轻量回归：

```bash
python3 Scripts/test_monterey_patcher.py
python3 Scripts/test_ui_contract.py
python3 Scripts/test_release_contract.py
Scripts/test_cost_history_parser.sh
Scripts/test_provider_auth.sh
```

使用 Swift 6.2 的完整本地构建：

```bash
cp Config/build.env.example Config/build.env
# 编辑 BUNDLE_ID、APPCAST_URL、SPARKLE_PUBLIC_KEY

Scripts/fetch_engine.sh
Scripts/build_universal.sh
Scripts/check_macos12_compat.sh "dist/universal/CodexBar Monterey.app"
Scripts/install_local.sh
```

## Monterey 真机验收

在 Intel 和 Apple Silicon 的 macOS 12.6.x 各执行一次：

```bash
Scripts/smoke_test_app.sh "/Applications/CodexBar Monterey.app"
```

脚本检查：

- `LSMinimumSystemVersion`；
- app 内全部 Mach-O 的 `minos`；
- app 内每个 Mach-O 都同时包含 Intel/Apple Silicon 架构；
- code signature；
- helper 版本；
- provider registry；
- 默认 enabled-provider JSON probe。

还应手工检查：

- Chrome/Firefox Cookie 解密；
- Safari Full Disk Access；
- Codex/Claude CLI、PTY 与 OAuth；
- Copilot/device-flow 或 token 配置；
- 登录启动；
- 从旧 tag 通过 Sparkle 升级；
- 更新后 config、Keychain cache 和历史数据不丢失。

## 当前验证状态

此交付包已完成：

- 所有 shell 脚本 `bash -n`；
- Python 脚本编译检查；
- GitHub Actions YAML 解析；
- 全部 Swift 文件语法解析，核心模型与 CLI 客户端通过独立类型检查；
- build/release workflow 均执行隔离配置的离线 provider registry/JSON 冒烟测试；
- universal 构建脚本按架构的确定输出路径取二进制；
- 递归合并整个 app bundle 内的 Mach-O；
- release 的 EdDSA appcast、Developer ID、notarization 与 stapling 链路。

最终发布门槛是：GitHub macOS build workflow（Swift 6.2）通过，并在 macOS 12 Intel 与 Apple Silicon 上运行 `smoke_test_app.sh` 和上述认证测试。本机 Swift 5.6 的轻量回归通过不能替代完整 SwiftPM/Sparkle 构建。

## Monterey 源码兼容层

构建脚本不再只是把上游 `Package.swift` 的最低版本改成 macOS 12。下载固定的
CodexBar provider engine 后，`Scripts/patch_upstream.py` 会自动回移植日志中已确认的
macOS 13/14 API，包括 Swift Clock/Duration、现代锁、Swift Regex、新版 URL/String API
和 WebKit data store。随后执行残留 API 扫描；若上游源码仍有已知的不兼容调用，构建会
在 Swift 编译前显示具体文件和模式并终止。

可在本地先运行补丁回归测试：

```bash
python3 Scripts/test_monterey_patcher.py
swiftc -typecheck Patches/MontereyCompat.swift
```
