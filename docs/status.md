# 项目状态

## 整体进度
基础结构与网络层已实现并通过验证，UI 完成基础四 Tab/侧栏与核心页面。后续功能可在当前脚手架上直接扩展。

## 已实现
| 模块 | 状态 | 备注 |
| --- | --- | --- |
| Xcode 工程配置 | 完成 | 调整为 iOS 17+ / macOS 14+，关闭 visionOS，开启 App Sandbox 与外向网络，设置显示名「AI 圈速览」 |
| 依赖注入（AppContainer） | 完成 | 支持磁盘/内存缓存降级，预加载热点与最新日报 |
| API 模型（Data/Models） | 完成 | 全部 8 个 GET 响应、Problem、Attribution、快照/增量 | 
| 网络客户端（APIClient） | 完成 | ETag、304、缓存、离线、限流、308、分页、并发合并 |
| 端点工厂（APIEndpoint） | 完成 | 查询校验、不透明游标、故事链接 ID 提取 |
| 磁盘缓存（ResponseCache） | 完成 | 容量/字节限制、游标不落盘、日报长期保留 |
| 精选页面（FeedView） | 完成 | 24h/7d、精选/公开池、分类、搜索、分页 |
| 热点页面（HotTopicsView） | 完成 | 排名列表、事件综述/时间线 |
| 日报页面（DailyViews） | 完成 | 最新日报、归档、指定日期详情 |
| 关于页面（AboutView） | 完成 | 非官方声明、清除缓存、功能范围说明 |
| 单元测试 | 完成 | 82 次通过，覆盖网络契约、状态管理、真实接口（可选） |
| AGENTS.md | 完成 | 约定与常用验证命令 |

## 未实现
| 模块 | 计划阶段 | 备注 |
| --- | --- | --- |
| 收藏/已读 UI 与业务 | 后续 | 数据模型 `Bookmark`/`ReadRecord` 已预留 |
| 深链（URL Schemes） | 后续 | `aihotnews://` 协议入口 |
| 后台刷新（BGAppRefresh） | 后续 | 按 s-maxage 刷新首页、热点、日报 |
| iPad 三栏详情 | 后续 | 当前为双栏侧栏 |
| 网页入口（周报/月报/主题/模型榜） | 后续 | 设置中打开对应 aihot.news 网页 |

## 验证状态
- macOS 单元测试：通过
- iPhone 模拟器单元测试：通过
- iPhone 模拟器首页真数据：通过
- git diff --check：无空白错误

## 已知问题
- 事件链接当前信任任何 HTTP/HTTPS URL 的最后一个路径段，已限定为 API 返回的可信链接；仍需保持观察上游是否调整域名或路径。
- `UIDevice.current.userInterfaceIdiom == .pad` 在 Mac Catalyst 或 visionOS 上不会触发，如未来扩展平台需调整 User-Agent 平台识别。
