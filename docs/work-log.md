# 工作日志

## 2026-09-09

### 审查问题修复
- 通过三个智能体分别修复首页 304 丢失内存分页、重新验证丢失续页离线副本、搜索深链缺失。
- 首页正文未变的缓存读取或 304 保留分页；正文变化、跨日及失效游标仍重建。磁盘聚合使用内存中的首页版本标识及实际游标链，标识和游标均不落盘。
- 搜索深链使用结构化查询解析，校验唯一 q 和 Unicode 码点长度，返回精选根页并显示搜索框。
- 新增 13 个单元测试函数 / 35 次测试运行及一个跨设备 UI 流程。macOS 全量 127 次单元测试、iPhone/iPad 搜索与导航回归、iOS Release 构建均通过。

### 界面与数据闭环
- 在既有未提交界面实现上完成 LibraryStore 根环境注入，接通外观设置、收藏与已读，修复启动崩溃。
- 统一四 Tab 和大屏阅读路由，加入深链、事件引用跳转、308 后的收藏和已读迁移。
- 完成前后台刷新、可见页面限流重试、已翻页列表保留和不含游标的离线列表快照。
- 最新日报同时写入返回日期缓存；日报索引和 latest 在上海 08:00 重新检查。
- 收紧 iOS 布局，补齐原生图标、中文日期、深色和最大辅助功能字号、小屏与横屏阅读。
- 新增 SwiftData、分页重启、缓存边界测试和隔离 UI 测试；真实原文链接已验证使用 SFSafariViewController。
- 修复 Release 优化器在 ResourceViewModel 隐式隔离泛型析构上的崩溃，未降低优化或修改签名、Sandbox。

验证与边界以 [项目状态](status.md) 为准；架构说明见 [数据加载与本机存储](DATA_LOADING.md)。

## 2026-09-08

### 今日目标
完成 AI 圈速览 Apple 客户端基础结构与完整网络层实现，确保能读取公开 API、通过编译并覆盖核心 PRD 约束。

### 已完成
- **工程分层**：App/AppContainer、Core/Networking、Data/Models 与 Repository、Features 视图与状态。
- **OpenAPI 模型与端点**：按 `openapi-v1.json` 1.2.0 实现所有 8 个 GET 端点，支持可空字段与未知字符串。
- **网络层**：ETag 条件请求/304 复用、共享缓存、离线回退、429/503 Retry-After、Problem JSON、308 事件跳转、分页失效恢复、并发合并。
- **基础 UI**：iPhone 四 Tab、iPad/Mac 侧栏；精选搜索与筛选、热点事件、日报归档与详情、关于页。
- **测试**：新增 `APIContractTests`、`NetworkingTests`、`FeatureStateTests`、`LiveAPITests` 共 82 次有效测试（52 个测试函数），macOS 与 iPhone 模拟器均通过。
- **真实接口联调**：精选、热点、事件、日报请求均成功，热点 story 链接解析已兼容 `aihot.virxact.com` 返回的 HTML URL。

### 关键修复
- 修正 `DailyEntry`/`DailyReport` 日历日期按上海时区解析。
- 修正故事 308 跳转后，规范 URL 缓存与重验证使用同一规范 URL。
- 修正非 `aihot.news` 事件 HTML 链接的信任提取规则。

### 遇到的问题
- 模拟器首次加载需要较长数据迁移时间，但后续构建与测试稳定。
- Swift 默认 MainActor 隔离使 Codable 实现与部分协议方法需要显式 `nonisolated`。

### 未开始
- 收藏/已读 UI 与业务逻辑、深链、后台刷新、iPad 三栏详情、模型榜/周报等网页入口。
