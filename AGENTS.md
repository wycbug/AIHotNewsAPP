# 工程约定

- 使用中文回复。产品约束以 `docs/PRD.md` 为准，接口契约以根目录 `openapi-v1.json` 为准。
- 工程使用 Xcode 26.6、SwiftUI、Observation、SwiftData 和 Foundation URLSession，无第三方依赖。支持 iOS/iPadOS 17+、macOS 14+。
- Xcode 使用文件系统同步分组；`AIHotNews/` 和 `AIHotNewsTests/` 下的 Swift 文件自动加入对应 target，无需手工登记 Sources。
- App/Features 的状态使用 MainActor；Core/Networking 和 Data/Models 的跨隔离值类型、Codable 实现与 extension 工厂方法显式标记 `nonisolated`，避免默认 MainActor 隔离影响网络解码。
- JSON API 请求固定发送至 `https://aihot.news/api/v1/`。事件网页链接可能使用不同域名（实测 `aihot.virxact.com`）；只从 API 返回的链接末段提取 ID，再调用固定 JSON API，不直接请求网页获得正文。
- 游标是不透明字符串，只在同查询、同上海日历日的内存状态中续用；磁盘列表缓存不保留 nextCursor/ETag，重启后重新验证首页。snapshot/changes 不落盘、不进行后台全量同步。

# 验证命令

在仓库根目录执行：

- macOS 离线单元测试：`xcodebuild -quiet -scheme AIHotNews -destination 'platform=macOS,arch=arm64' -only-testing:AIHotNewsTests CODE_SIGNING_ALLOWED=NO test`
- iOS 模拟器编译：`xcodebuild -quiet -scheme AIHotNews -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
- 模拟器单元测试：先用 `xcrun simctl list devices available` 选择设备，再执行 `xcodebuild -quiet -scheme AIHotNews -destination 'platform=iOS Simulator,id=<设备 UUID>' -only-testing:AIHotNewsTests CODE_SIGNING_ALLOWED=NO test`。
- 可选真实接口冒烟测试（会访问公开接口，默认跳过）：`AIHOT_LIVE_API_TESTS=1 TEST_RUNNER_AIHOT_LIVE_API_TESTS=1 xcodebuild -quiet -scheme AIHotNews -destination 'platform=macOS,arch=arm64' -only-testing:AIHotNewsTests/LiveAPITests CODE_SIGNING_ALLOWED=NO test`
- 差异检查：`git diff --check`。
- 并行跑不同平台构建时使用不同 `-derivedDataPath`，避免 Xcode build database 锁冲突。不要为通过构建关闭 App Sandbox 或修改签名团队。
