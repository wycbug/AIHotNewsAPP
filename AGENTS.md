# Repository Guidelines

## 项目概览与规范依据

使用中文回复。AIHotNews（AI 圈速览）是免费、无广告、无登录的原生阅读器，支持 iOS/iPadOS 26+、macOS 26+。使用 Xcode 26.6、SwiftUI、Observation、SwiftData 和 Foundation URLSession，无第三方依赖。

产品约束以 `docs/PRD.md` 为准，接口契约以根目录 `openapi-v1.json` 为准；数据加载、缓存和深链行为见 `docs/DATA_LOADING.md`。修改相关行为时同步维护对应文档。

## 项目结构与模块职责

- `AIHotNews/App/`：依赖装配、导航、后台刷新及 DEBUG 测试入口。
- `AIHotNews/Features/`：SwiftUI 页面、主题、共享视图、ViewModel 和收藏状态。
- `AIHotNews/Core/Networking/`：端点构造、HTTP 请求、条件验证和响应缓存。
- `AIHotNews/Data/Models/`、`Data/Repositories/`：API/存储模型与数据访问。
- `AIHotNews/Assets.xcassets/`：颜色及应用图标；图标生成脚本在 `scripts/generate-app-icon.swift`。
- `AIHotNewsTests/`：离线单元测试与可选真实接口测试；`AIHotNewsUITests/`：导航、阅读和持久化流程测试。
- `Configuration/Info.plist`：应用配置；`AIHotNews.xcodeproj/`：工程与构建设置。

Xcode 使用文件系统同步分组；`AIHotNews/` 和 `AIHotNewsTests/` 下的 Swift 文件自动加入对应 target，无需手工登记 Sources。

## 构建、运行与验证

在 Xcode 打开 `AIHotNews.xcodeproj`，选择 `AIHotNews` scheme 和 Mac 或模拟器，通过 Run 本地运行。以下命令均在仓库根目录执行。

macOS 离线单元测试：

```sh
xcodebuild -quiet -scheme AIHotNews -destination 'platform=macOS,arch=arm64' -only-testing:AIHotNewsTests CODE_SIGNING_ALLOWED=NO test
```

iOS 模拟器编译（不运行测试）：

```sh
xcodebuild -quiet -scheme AIHotNews -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

模拟器单元测试：先运行 `xcrun simctl list devices available`，再替换设备 UUID：

```sh
xcodebuild -quiet -scheme AIHotNews -destination 'platform=iOS Simulator,id=<设备 UUID>' -only-testing:AIHotNewsTests CODE_SIGNING_ALLOWED=NO test
```

运行 UI 测试时，将上述 `-only-testing:AIHotNewsTests` 改为 `-only-testing:AIHotNewsUITests`。模拟器测试建议增加 `-parallel-testing-enabled NO`，避免并行克隆设备启动失败。

可选真实接口冒烟测试（访问公开接口，默认跳过）：

```sh
AIHOT_LIVE_API_TESTS=1 TEST_RUNNER_AIHOT_LIVE_API_TESTS=1 xcodebuild -quiet -scheme AIHotNews -destination 'platform=macOS,arch=arm64' -only-testing:AIHotNewsTests/LiveAPITests CODE_SIGNING_ALLOWED=NO test
```

提交前执行 `git diff --check`。并行跑不同平台构建时使用不同 `-derivedDataPath`，避免构建数据库锁冲突。不要为通过构建关闭 App Sandbox 或修改签名团队。

## 编码风格与并发隔离

- 使用四空格缩进，遵循现有 Swift 排版；类型使用 `UpperCamelCase`，方法和属性使用 `lowerCamelCase`，文件按主要类型命名，如 `FeedViewModel.swift`。
- 页面以 `View`、功能状态以 `ViewModel` 命名；复用现有主题、共享视图和数据访问层。仓库未配置独立格式化或 lint 工具，使用 Xcode 格式化并检查差异。
- App/Features 的状态使用 `@MainActor`，可观察状态采用 Observation；网络与缓存沿用 actor 隔离。
- Core/Networking 和 Data/Models 的跨隔离值类型、Codable 实现与 extension 工厂方法显式标记 `nonisolated`，避免默认 MainActor 隔离影响网络解码。
- 异步任务须处理取消及过期结果，防止旧查询覆盖新状态；SwiftData 保存失败应回滚并显示错误，不重置用户数据库。

## 接口与缓存约束

- JSON API 请求固定发送至 `https://aihot.news/api/v1/`。事件网页链接可能使用不同域名（实测 `aihot.virxact.com`）；只从 API 返回的链接末段提取 ID，再调用固定 JSON API，不请求网页获得正文，不猜造单篇正文端点。
- 容忍未知 JSON 字段和未来分类字符串；保留来源、原文链接及 `attribution`。应用不冒充官方产品，不增加账号、广告或付费墙。
- 按完整 URL 缓存 ETag；304 沿用已有正文，遵守 `s-maxage`、`Retry-After` 和 `no-store`，不进行密集重试。
- 游标是不透明字符串，只在同查询、同上海日历日的内存状态中续用。磁盘列表缓存不保留 `nextCursor`/ETag；重启后重新验证首页。`invalid_cursor` 按原筛选重载首页，不扩大查询范围。
- `snapshot/changes` 不落盘、不进行后台全量同步。网络缓存与收藏、已读独立管理，清除缓存不能删除收藏和已读。

## 测试规范

单元测试使用 Swift Testing（`@Test`、`#expect`），文件和套件按领域命名为 `*Tests`，方法描述行为，如 `conditionalRequestReusesBodyOn304`。UI 测试使用 XCTest/XCUIApplication，方法以 `test` 开头。

默认测试保持离线，复用 `StubTransport`、可控时钟和独立存储。UI 测试用 `--ui-test-session <UUID>` 隔离数据，用 `--ui-offline` 模拟断网。仓库未规定覆盖率百分比；行为修复应补充有意义的回归用例，重点覆盖分页、取消、304、限流、离线恢复和持久化失败。界面变更检查 iPhone 与 iPad/Mac 自适应布局、深色模式及辅助功能大字号，并保留截图附件。

## 提交与 Pull Request

近期历史采用简短的英文祈使句，如 `Expand unit and UI test coverage for reading flows and edge cases`，未采用强制的 Conventional Commits 前缀。每次提交聚焦一个改动，避免混入 Xcode 用户数据、构建输出或无关格式变更。

PR 描述应说明问题、变更后行为、关联 issue（如有）及实际执行的验证命令与结果；界面改动附截图，接口或存储改动说明兼容性影响。明确标注未运行的检查。保留工作区中与本任务无关的现有修改。
