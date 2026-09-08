# AIHOT 网页数据与 Open API 覆盖核查

核查日期：2026-09-08，Asia/Shanghai。数据源：[aihot.news](https://aihot.news/)。契约：OpenAPI 3.1，API 文档版本 `1.2.0`。

## 1. 结论与核查范围

**AIHOT 网页展示的数据没有全部通过正式 Open API 提供。** v1 覆盖近期资讯的主要文本、当前热点排名、事件综述与报道、结构化日报，以及当前精选集合的快照与变更。模型榜、主题、周报、月报没有对应 v1 端点；资讯媒体与标签、观点筛选、热度曲线、部分来源信息和统计也存在缺口。

已通过用户指定的浏览器标签页进入 [Agent 接入页](https://aihot.news/agent?tab=api)，检查网站主导航、日报中的周/月报入口、模型榜各来源标签和代表性详情页，并结合浏览器网络请求、线上契约与匿名 HTTP 请求核对字段。网站公开内容及接口无需账号登录或 API Key。

本次核查覆盖公开页面的**数据类型、字段与查询能力**，没有逐条遍历全站历史记录，也没有检查未公开的管理后台。文中的新闻、模型名称和分数只作为页面样本，不代表对其外部事实作出验证。随时间变化的数量和热度均为核查时观察值。

获取方式按以下证据等级标记：

| 标记 | 含义 |
| --- | --- |
| 正式 API | 线上 `openapi-v1.json` 已定义的接口或字段 |
| 已实测网页 JSON | 浏览器实际调用、且无 Cookie 的 HTTP 请求复现成功；没有 v1 契约保障 |
| 已核查页面 | 页面及相关交互已打开，可从呈现的内容读取；没有确认稳定的 JSON 数据接口 |
| 文档确认 | 服务方接入说明已列出，但本次未执行该通道的端到端调用 |
| 可派生 | 可由已有响应计算；需要明确统计口径，不等于服务方提供了相应字段 |

## 2. 正式 API 清单

基址固定为 `https://aihot.news`，以下均为匿名 `GET`。根目录的 [openapi-v1.json](../openapi-v1.json) 与当天下载的线上契约经 JSON 结构比较完全一致。

| 端点 | 已提供的数据 | 本次验证 |
| --- | --- | --- |
| `/api/v1/items` | 精选/公开池，24 小时或 7 天窗口；标题、原始标题、摘要、来源名、链接、发布时间、收录时间、分类、精选分、精选状态、推荐理由 | selected/all 请求均 HTTP 200；`opinion` 筛选 HTTP 400 |
| `/api/v1/hot-topics` | 当前排名、代表条目、来源数、信号数、来源名、更新时间、可选事件链接 | HTTP 200，返回 3 个事件 |
| `/api/v1/stories/{publicId}` | 事件标题、状态、时间范围、综述、报道列表、官方来源标记、故事线、相关事件 | HTTP 200，抽查事件与网页主要文本一致 |
| `/api/v1/dailies` | 日报索引、日期、生成时间、导语标题与链接 | HTTP 200，`limit=180` 返回 140 期 |
| `/api/v1/dailies/latest` | 最新日报的导语、分区内容、快讯与来源链接 | HTTP 200，与指定当天日期响应一致 |
| `/api/v1/dailies/{date}` | 指定日期的结构化日报 | 抽查 2026-09-08、2026-09-04，均 HTTP 200 |
| `/api/v1/selected/snapshot` | 跨时间的当前精选集合，支持分页和轻量字段模式 | `fields=default&limit=1` HTTP 200；未全量下载 |
| `/api/v1/selected/changes` | 精选集合的新增、更新、移除事件 | 仅核查契约，未执行完整快照与增量同步 |

需要保留的边界：

- `items` 最长只有滚动 7 天；`mode=all` 是公开池，不是网站全库，契约排除了 `mp_hot`、未审、低相关及已合并重复条目等数据。
- 当前分类只有 `ai-models`、`ai-products`、`industry`、`paper`、`tip`。网页额外提供独立的 `opinion` 分类。
- `reason` 在 `items` 中提供，允许为 null；契约明确说明 snapshot/changes 暂不提供此字段。`fields=minimal` 还主动省略摘要等字段，应与真正的接口缺口区分。
- snapshot 覆盖的是跨时间的**当前精选集合**，不等于所有历史资讯或所有历史版本。按文档分页保留第一页同步游标，再接 changes，属于接口能力说明；本次未执行该流程。
- `hot-topics.rank` 是名次，`items.score` 是精选分，都不是网页的事件热度；榜单也不保证一定有 10 条。
- 事件 ID 应取自实际返回的 `links.story`，再请求固定基址的 v1 接口。有些网页链接仍可能使用旧域名，不能将网页 URL 当作 JSON 接口，也不能用资讯 ID 猜事件 ID。

## 3. 页面覆盖对照

| 页面/数据区域 | v1 已覆盖 | 缺失或不能等价复现的数据 | 补充获取方式 |
| --- | --- | --- | --- |
| 精选 `/`、全部动态 `/all` | 近期主要文本、推荐理由、来源名、时间、精选状态及分数 | AI 标签、作者与账号、头像、引用推文、图片/视频预览、同内容其他来源、关联精选条目、来源 ID/类型 | 网页 JSON，见 4.1 |
| 分类与来源筛选 | 五个分类、selected/all | 独立观点分类、一手信源/资讯/推文渠道筛选、渠道总条数 | 已验证旧 feed 的观点与一手信源查询；网页渠道菜单及统计，见 4.1 |
| 搜索 | 最近 7 天 `q` 搜索，timeline/published 排序 | 历史全库搜索、全文相关度排序、命中总数、标签筛选 | 网页搜索路由；相关度查询当次遇到繁忙页，见 4.2 |
| 单篇阅读 `/items/{id}` | 列表可取得摘要、推荐理由及原文链接 | 单篇按 ID 获取、全文/中文翻译/原文切换、完整媒体和标签、单篇关联事件等 | 原文或站内页导航；白名单 RSS 全文仅部分覆盖，见 4.3 |
| 热点榜 `/hot`、首页热点 | 名次、来源数、信号数、事件链接 | 热度数值、涨跌比例、阶段徽标、迷你趋势图 | 网页可见数据，见 4.4 |
| 事件 `/story/{publicId}` | 综述、最新报道、时间线、相关事件、`reports[].source.firstParty` | 历史热度点、峰值与峰值时间、趋势状态、每条报道的精选徽标、完整事件目录 | 热度交互；精选状态可部分关联；无完整事件枚举接口，见 4.4 |
| 日报 `/daily`、`/daily/{date}` | 主要正文、分区、快讯、来源名、链接 | 来源分类标签、准确官方来源统计、网页阅读时长等辅助统计 | 部分由 API 派生，其余读取网页，见 4.5 |
| 日报归档 `/daily/archive` | 当前所有可见日期、导语标题、链接 | 索引不直接带每期事件数；超过索引上限后的完整日期发现能力 | 事件数可读单期计算；历史日期沿网页链接发现，见 4.5 |
| 周报 `/weekly`、月报 `/monthly` | 无对应端点 | 期刊目录、周期、标题、导语、专题综述、精选/日报/事件统计、来源链接 | 网页正文及归档链接，见 4.6 |
| 主题 `/topics`、`/topics/{slug}` | 无对应端点 | 主题分组、slug、描述、总量/精选数、更新时间、近 14 天焦点、关联主题、主题分页 | 网页；旧 feed 标签仅部分补充，见 4.7 |
| 模型榜 `/leaderboard` | 无对应端点 | 排名、模型和厂商、发布日期、价格、覆盖率、共识分、证据置信度及说明 | 网页表格，见 4.8 |
| 模型详情及方法说明 | 无对应端点 | 原始榜单排名/分数/别名、未测标记、评测配置、置信区间、来源与更新日期、汇率/计费依据 | 详情/方法页及上游入口，见 4.8 |
| 收藏 `/starred`、已读、主题设置 | 无用户同步接口 | 当前浏览器的收藏、已读状态及偏好 | 浏览器本地状态；应用需自行保存，见 4.9 |
| 关于、更新日志、接入说明 | 无通用内容或状态端点 | 作者资料、二维码、更新日志、接入版本/服务状态等 | 静态或服务端呈现页面；API 版本可读契约元数据 |
| 反馈 `/feedback` | 无公开反馈读取端点 | 页面是提交表单，未展示公共反馈数据列表 | 不属于缺失的公开数据列表；本次未提交或上传 |

## 4. 缺失数据的获取方式

### 4.1 网页内部资讯 JSON：已实测

在 `/all?channel=firstParty&page=1` 向下滚动触发加载时，浏览器发出以下请求，响应为 HTTP 200、`application/json`。随后使用不带 Cookie 的 HTTP 请求复现成功：

```http
GET https://aihot.news/api/public/feed?mode=all&channel=firstParty&cursorAt=1788494500944&cursorId=cmtmfg63x011irogcsntx6bpy
```

另外两个起始查询也已实测成功：

```bash
curl --fail --silent --show-error 'https://aihot.news/api/public/feed?mode=all'
curl --fail --silent --show-error 'https://aihot.news/api/public/feed?mode=all&category=opinion'
```

观点查询前 5 条 ID 与浏览器 `/all?category=opinion&page=1` 一致，并与不带分类的查询不同，确认该参数实际参与筛选。`channel=firstParty` 已在真实滚动请求中验证；其他渠道的参数值应从菜单对应的实际请求读取，不能根据中文名称猜测。

响应顶层字段为 `items`、`hasNext`、`nextCursor`、`q`、`searchOrder`、`tag`。本次每页返回 40 条，续页方式如下：

1. 使用同一组 mode、分类、渠道等筛选条件。
2. `hasNext=true` 时，读取响应中的 `nextCursor.at` 和 `nextCursor.id`。
3. 分别作为下一次请求的 `cursorAt` 与 `cursorId`，直至 `hasNext=false`。本次未遍历到历史末页，不能据此保证可取全库。

观察到的游标结构：

```json
{
  "hasNext": true,
  "nextCursor": {
    "at": 1788408110199,
    "id": "cmtl00ivm0c0eroalg6gdvk0e"
  }
}
```

以上游标只是现场证据，复现应从新的响应获取，不能长期硬编码；旧 feed 的两个游标参数与 v1 的不透明 `cursor` 不通用。顶层出现 `searchOrder`、`tag` 不代表同名查询参数已验证。

| 缺失数据 | 旧 feed 中观察到的字段 | 解释/限制 |
| --- | --- | --- |
| 多标签 | `aiTags[].tag` | 可获得条目标签；不包含完整主题目录和统计 |
| 来源标识与类型 | `source.id`、`source.name`、`source.kind` | `kind` 是采集类型，例如 `json_list`；不能直接等同官方来源标记 |
| 作者与推文展示 | `author`、`xDisplay.authorName`、`screenName`、`originalText`、`titleText`、`bodyText`、`useBodyMode` | 字段可为空；并非所有条目都是推文 |
| 引用推文 | `xDisplay.quotedTweet` | 保留实际返回结构；v1 的摘要不能代替它 |
| 头像 | `xAvatarProxied` | 使用响应给出的代理地址 |
| 图片/视频预览 | `xMediaProxied[].src/fullSrc/type/width/height` | 视频类型不保证返回可播放视频，原始播放仍可能需要跳转原帖 |
| 同内容其他来源 | `duplicateCount`、`duplicateSources` | 表示其他/重复来源信息，不能直接等同事件级 `sourceCount` |
| 关联精选代表条目 | `linkedPrimary.id/title` | 可为空；实测非精选重复报道指向另一个代表条目 |
| 精选内部展示标记与理由 | `aiSelected`、`publicSelectedVisible`、`aiSelectedReason`、`finalScore` | 不应未经口径确认就与 v1 各字段机械互换 |
| 网页日期分组 | `dateKey`、`dateLabel`、`timeLabel` | 网页展示值；不代替规范时间字段 |

媒体地址形如 `/api/img-proxy?...&mode=thumb/full/avatar&exp=...&sig=...`，是带到期时间和签名的 URL。应将响应中的相对地址按 `https://aihot.news` 解析，保留参数，过期后重新取得；不自行生成签名或把一次返回值当永久链接。旧 feed 没有通用的文章全文 HTML 字段。

**稳定性限制：** 该端点没有列入 OpenAPI，属于网页正在使用的内部旧接口。接入页明确公告 `/api/public/*` 将于 **2026-12-31** 停服；未找到 `/api/public/feed` 例外说明或后继契约。因此这里记录的是当前可复现的获取方式，不是可长期依赖的正式替代接口。

### 4.2 历史搜索、标签和渠道统计

已观察到的页面入口：

| 数据 | 页面/查询 | 验证状态 |
| --- | --- | --- |
| 历史关键词搜索、总命中数 | [`/all?q=OpenAI&page=1`](https://aihot.news/all?q=OpenAI&page=1) | 页面显示 5969 条命中；v1 `page.count` 只是本页条数 |
| 全文相关度模式 | [`/all?q=OpenAI&tab=relevance`](https://aihot.news/all?q=OpenAI&tab=relevance) | 点击产生真实请求，但当次进入 `search-busy` 页面，提示 5 秒后重试；未验证成功结果与排序 |
| 标签筛选 | [`/all?tag=OpenAI&page=1`](https://aihot.news/all?tag=OpenAI&page=1) | 观察到标签链接；标签属于服务方分类，不等同关键词匹配 |
| 一手信源统计 | [`/all?channel=firstParty&page=1`](https://aihot.news/all?channel=firstParty&page=1) | 页面显示 4931 条；相同渠道的滚动 JSON 已实测 |

获取总数和搜索模式应读取页面呈现的统计、排序导航及分页链接。全文相关度模式需要在服务恢复后按页面入口复查，遵守页面退避提示。这里没有确认稳定的全文搜索 JSON 契约，也没有确认旧 feed 支持与网页完全相同的所有搜索模式。

### 4.3 单篇全文与富媒体

抽查 [`/items/cmts9dr2m029hrobq86wrny37`](https://aihot.news/items/cmts9dr2m029hrobq86wrny37)：网页展示完整中文翻译、原文切换、标签、推荐理由和事件跟进。v1 只提供相应列表条目的摘要等字段，没有 `GET /api/v1/items/{id}` 或通用全文端点。

可用获取途径：

- 对全文阅读，使用正式 API 返回的 `links.original` 或 `links.aihot` 导航至原文/站内阅读页；这能满足阅读，但不是结构化全文 API。
- 接入页文档列出 [`/feed/full.xml`](https://aihot.news/feed/full.xml) 和分类全文 RSS，其 `content:encoded` 只对允许再分发的白名单来源提供全文，不能覆盖全部条目和历史。该能力本次为文档确认，未下载 RSS 验证每篇内容。
- 作者、标签及部分媒体可以用 4.1 的旧 feed 补充，仍受其稳定性与字段空值限制。

服务方接入边界和本仓库 PRD 均不允许以抓取站内 HTML 绕过正文门禁；没有把页面可见全文当作可直接接入本应用的替代正文接口。

### 4.4 热度与事件附加信息

[`/hot`](https://aihot.news/hot) 展示事件热度、阶段徽标与迷你趋势图，首页还展示短周期涨跌幅。抽查的[事件页](https://aihot.news/story/0aae4e4a-8436-422f-8277-d105655302a5)展示了 24 小时热度曲线、当前值、峰值与峰值时间。

实测获取过程：定位可访问名称以“近一周本事件热度变化曲线”开头的图表区域，聚焦后使用左右方向键读取各时点的提示内容。一次左移显示 `9/8 21:42`、热度 `101`、趋势“回落”。交互时没有观察到新增取数请求，说明此次图表交互使用了页面已加载的数据。本次实际呈现的窗口是 24 小时，未验证其他时间窗切换。

页面数字与提示内容可作为补充读取来源，但没有发现稳定的 JSON 热度端点。不得把 SVG 像素位置反推的近似数值冒充真实时序，也不能用 API 排名、精选分或来源数代替热度。若需要完整、稳定的时序数据，需要服务方增加正式能力。

事件中每条报道的“精选”徽标不在 `StoryReport` 内。可用已获得的精选条目 ID 做关联；仅关联最近 7 天会漏掉更早的精选。完整当前精选集合可由 snapshot/changes 获取，但这仍不提供历史时点的精选状态。事件的官方来源标记则已经由 `reports[].source.firstParty` 提供，不应列为全局缺失字段。

现有事件发现入口是 `hot-topics.links.story` 以及已取得事件中的故事线/相关事件引用，没有枚举全部事件的独立 v1 目录端点。网页可沿真实链接发现更多事件，但不保证穷尽。

### 4.5 日报统计与归档

[`2026-09-04 日报`](https://aihot.news/daily/2026-09-04)网页显示 21 个事件、18 个来源、8 个官方来源、8 个新模型、约 9 分钟阅读。API 中四个分区分别有 8、4、1、8 条内容，来源名称去重为 18 个，快讯为空。

| 网页值 | 获取方式 | 能否与网页严格等价 |
| --- | --- | --- |
| 事件数/分区数 | 统计 `report.sections[].items`；有快讯时单独明确计数口径 | 样本一致；不能把包含快讯的任意公式当作已验证规则 |
| 来源数量 | 从分区/快讯的 `source.name` 去重 | 样本一致；没有规范来源 ID，别名可能影响其他日期 |
| 新模型数 | 对应“模型发布/更新”分区计数 | 本次样本为 8；该值更接近该分区事件数，不能解释为独立模型实体数 |
| 官方来源数、来源分类徽标 | 读取网页“官方”“X·KOL”“大咖博客”“综合资讯”“公众号·媒体”等标签 | 日报 API 只有来源名，没有该分类字段；不能用来源名称猜测 |
| 约 N 分钟阅读 | 读取网页展示值；客户端也可自定估算规则 | API 不提供网站算法与精确结果，自算不能声称与网页一致 |
| 每期标题和日期 | 日报索引的 `leadTitle`、`date`、`links` | 当前可用 |
| 归档每期事件数 | 读取对应日期日报并按明确口径计算，或读取归档页展示 | 索引本身不带该统计 |

[`/daily/archive`](https://aihot.news/daily/archive)中提取到 140 个不同日期链接，范围 `2026-04-22` 至 `2026-09-08`；与 `/api/v1/dailies?limit=180` 的返回数量和日期范围一致。因此**本次没有证据表明当前日报日期目录缺失**。

索引契约的 `limit` 上限为 180，且没有分页参数。未来超过上限时，较早日期的自动发现存在限制；已知日期仍可请求 `/api/v1/dailies/{date}`。补充日期入口是归档页中的实际 `/daily/YYYY-MM-DD` 链接。

### 4.6 周报、月报

已核查 [`/weekly`](https://aihot.news/weekly)、[`/weekly/2026-W36`](https://aihot.news/weekly/2026-W36)、[`/monthly`](https://aihot.news/monthly)、[`/monthly/2026-08`](https://aihot.news/monthly/2026-08)。服务方 Skill README 也明确这些内容尚无对应公开端点。

获取方式是从周/月报首页读取当前期链接和归档导航，再进入实际日期页面，按标题、时间范围、统计、导语、专题标题、专题综述、条目及来源链接提取。周报日期标识为观察到的 `2026-W36`，月报为 `2026-08`，不要凭空枚举并假定所有周期均存在。

样本：该周报显示 90 条精选、7 期日报、19 个事件和 5 个主题；该月报显示 356 条精选、31 期日报、21 个事件和 5 个主题。它们包含独立编排的专题叙述，把 7/31 份日报拼接起来不能还原官方周/月报。没有找到周/月报的稳定 JSON、RSS 或 MCP 入口。

### 4.7 主题目录和专题详情

[`/topics`](https://aihot.news/topics)展示 38 个主题，分为公司与模型 15 个、技术方向 14 个、内容类型 9 个。应提取主题分组、标题、slug、描述、精选数量及详情链接。

[`/topics/openai`](https://aihot.news/topics/openai)样本展示 4538 条收录、501 条精选、更新时间、近 14 天焦点、分页精选及关联主题；观察到 [`/topics/openai/page/2`](https://aihot.news/topics/openai/page/2) 和最多第 26 页的导航。可按实际分页链接获取后续内容，不必推测分页参数。

旧 feed 的 `aiTags` 可以补充条目标签，但无法单独还原主题定义、完整统计、焦点排序与关联关系。v1 的 `q=OpenAI` 也不等于该主题的成员集合。未发现独立主题 JSON 端点；目前可获取的完整展示来源是上述页面。

### 4.8 模型榜、详情及上游数据

已检查 [`/leaderboard`](https://aihot.news/leaderboard)、一个[模型详情页](https://aihot.news/leaderboard/claude-fable-5-1)和[方法说明页](https://aihot.news/leaderboard/methodology)，包括七个来源标签、Artificial Analysis 和 Arena 的子榜。

| 页面区域 | 应记录的字段/获取位置 |
| --- | --- |
| 综合榜 | 页面更新时间、名次、模型、厂商、发布日期、评测覆盖、输入/输出价格、共识分、证据置信度 |
| 价格说明 | 币种、每百万 token 单位、官方模型 ID、核对日期、计费假设、汇率来源与日期 |
| 模型详情 | 各基准原始名次、原始分数、原始模型别名、未评测状态、来源链接、模型整体覆盖情况 |
| 方法及原始榜单 | 来源名称、子榜、配置、数据日期、核对日期、排名/分数/区间、融合口径与权重说明 |

DOM 读取应按语义表格提取：综合榜的行实际包括 `a[role="row"]`，详情链接从该行的 `href` 获取，单元格使用 `[role="cell"]`；不能只查传统 `tr/td` 或凭模型显示名拼接 slug。按可见列标题映射字段，价格和置信度附加说明需读取其提示内容。

核查时综合榜为前 30 名、7 个独立来源；方法页展开为 9 个榜单，APEX 又区分 ReAct/Loop，所以模型详情可出现 10 项评估。名次不能用展示的共识分简单降序重建：样本第一名共识分 88.6，第二名 90.6。不同评测口径和证据状态需要保留。

以下是方法页给出的**上游入口**。本次确认了链接及 AIHOT 页面展示，没有对这些外站的完整接口、鉴权、配额或可用数据作端到端验证；它们不能直接当作已验证的 AIHOT API 替代品。

| 来源 | 入口 | 获取类型/限制 |
| --- | --- | --- |
| Artificial Analysis Index | [Data API 文档](https://artificialanalysis.ai/data-api/docs) | API 文档入口；需另行核实鉴权和字段 |
| Artificial Analysis 多语言 | [多语言榜](https://artificialanalysis.ai/models/multilingual) | 网页入口；未验证对应 API |
| LiveBench | [官方榜单](https://livebench.ai/) | 网页入口；未验证下载或 API 契约 |
| Arena 文本/WebDev | [Hugging Face 数据集](https://huggingface.co/datasets/lmarena-ai/leaderboard-dataset) | 数据集入口；需核实文件版本和字段 |
| Mercor APEX | [APEX Agents](https://www.mercor.com/apex/apex-agents-leaderboard/) | 网页入口，保留评测配置区别 |
| Vals | [Finance Agent Benchmark v2](https://www.vals.ai/benchmarks/fabv2) | 网页入口 |
| DeepSWE | [榜单](https://deepswe.datacurve.ai/) | 网页入口 |
| TapTap | [榜单](https://maker.taptap.cn/leaderboard/) | 网页入口 |

直接从上游拿到原始成绩，仍缺少 AIHOT 的模型别名归一、价格口径、共识排名及展示统计。若目标是复现 AIHOT 模型榜，需要服务方提供这部分结构化数据，或者将上游采集明确设计为独立产品数据来源。

### 4.9 本地状态与页面获取的共同限制

收藏页说明收藏保存在当前浏览器，本次没有读取或导入用户的实际收藏数据。匿名 API 不能获取当前浏览器的收藏、已读状态和主题设置；应用可使用自己的本地存储，不能称为与 AIHOT 账号同步。

主题、模型榜、筛选和搜索导航中观察到 `?_rsc=...` 请求，例如 `/topics/openai?_rsc=...`、`/leaderboard?_rsc=...`。这是 Next.js 的页面数据传输，观察到的同类响应类型为 `text/x-component`，不是公开 JSON API。参数和载荷会随构建、路由及框架状态变化，不能固化为长期接口。

页面方式可复核的流程为：打开本节列出的普通页面 URL，按标题、标签、表格和真实链接读取呈现内容；需要增量加载时观察浏览器 Network 中实际 Fetch/XHR。仅把返回 JSON 且已复现的请求记录为“网页 JSON”。本次没有编造主题、模型榜、热度、周/月报的 `/api/v1/*` 路由。

## 5. RSS 与 MCP 是否能补齐

接入页列出的补充通道如下，均为文档确认，未执行 RSS 全量下载或安装 MCP：

| 通道 | 文档中的范围 | 能否补齐上述缺口 |
| --- | --- | --- |
| `/feed.xml` | 最新 50 条精选摘要 | 不补模型榜、主题、周/月报、热度 |
| `/feed/full.xml` | 同一组最新精选；允许的来源才带全文 | 仅部分全文，不是全站正文接口 |
| `/feed/all.xml` | 最近 7 天公开池 | 不提供全历史替代方案 |
| `/feed/daily.xml` | 最近 30 期日报 | 不覆盖周/月报 |
| `/feed/category/{category}.xml`、`/feed/full/category/{category}.xml` | 文档列出的五个分类 | 没有独立 `opinion` 分类的文档承诺 |
| `/api/mcp` | `aihot_get_latest`、`aihot_search`、`aihot_get_hot_topics`、`aihot_get_story`、`aihot_get_daily` | 与现有数据范围一致，没有增加模型榜、主题或周/月报工具 |

## 6. 关键实测证据

| 编号 | 请求或比对 | 结果 |
| --- | --- | --- |
| E01 | 线上 OpenAPI 与仓库契约做 JSON 结构比较 | 相等；共 8 条路径，版本 1.2.0 |
| E02 | `/api/v1/items?mode=selected&window=7d&limit=100` | HTTP 200，99 条，`page.hasMore=false`，条目带 `reason` |
| E03 | `/api/v1/items?mode=selected&category=opinion&window=7d&limit=5` | HTTP 400，明确拒绝 opinion，错误节选如下 |
| E04 | `/api/public/feed?mode=all&category=opinion` | HTTP 200，40 条；前 5 条 ID 与网页观点列表一致 |
| E05 | `/api/v1/selected/snapshot?fields=default&limit=1` | HTTP 200；首条发布时间为 2025-09-30，包含摘要但无 `reason` 键；契约也明确其缺失 |
| E06 | `/api/v1/hot-topics` 与实际链接对应的 `/api/v1/stories/0aae4e4a-8436-422f-8277-d105655302a5` | 均 HTTP 200；支持排名/事件文本，没有热度时序 |
| E07 | `/api/v1/dailies?limit=180` 与 `/daily/archive` | API 返回 140 期，网页提取 140 个不同日期，起止范围一致 |
| E08 | `/api/v1/dailies/2026-09-04` 与同日网页 | API 分区 8+4+1+8=21 条、18 个去重来源；官方分类及阅读时长未提供 |
| E09 | `/all?channel=firstParty&page=1` 滚动加载 | 捕获并复现 4.1 的旧 feed 请求，包含标签、媒体、重复来源等字段 |
| E10 | `/all?q=OpenAI&tab=relevance` | 实际导航进入繁忙页；只确认入口，未确认成功结果 |

E03 的真实错误字段节选：

```json
{
  "type": "/problems/invalid-request",
  "title": "Invalid request",
  "status": 400,
  "detail": "category must be one of: ai-models, ai-products, industry, paper, tip.",
  "code": "invalid_request"
}
```

动态页面与不同缓存周期的响应并非同一时刻快照，例如热点来源数会随报道合并、内容更新而变化。本报告没有把这种时间差当作数据字段缺失，也没有宣称所有接口都完成了端到端验证。

## 7. 对本项目的影响与后续接入顺序

当前 [PRD](PRD.md) 和 [工程约定](../AGENTS.md)限定应用仅接入 v1，并且不抓取站内正文、不使用旧 `/api/public/*`、不做后台全量精选同步。本报告只记录核查结果和获取线索，没有变更这些产品约束或接入应用代码。

1. 现有资讯、热点、事件和日报继续以 v1 为准；对标签、热度、作者、媒体、官方来源统计等没有的数据保留缺失状态，不生成看似与官网一致的值。
2. 如扩展信息流，优先向提供方申请把观点分类、渠道筛选、标签、来源元数据、媒体、引用关系和重复报道关系纳入正式契约；旧 feed 的字段可用作具体需求样本。
3. 如扩展模型榜、主题、周/月报或热度时序，需要相应的正式数据接口及分页/更新时间定义。网页提取入口已记录，可用于验证展示字段；纳入应用需另行调整现有产品边界。
4. 其他值得补充的契约能力包括：snapshot/changes 的推荐理由、按条目 ID 读取已允许公开的摘要、事件目录、日报来源分类与统计、可分页的日报历史索引。这些是建议能力，**当前并不存在对应新增端点**。

实测响应的 `s-maxage`：items、日报索引、最新日报为 60 秒；hot-topics、story、指定日报、snapshot 为 300 秒。实际接入以各响应头为准，使用 ETag/`If-None-Match`，遇 429/503 遵守 `Retry-After`；RSS 文档建议至少 30 分钟间隔。当前没有 SSE、Webhook 或推送通道。

接口可匿名访问不等于允许任意再分发。用途边界以[公开使用规则](https://aihot.news/terms)及书面授权为准；服务方公开联系地址为 `wzglyay@virxact.com`。本次仅做只读核查，未发送反馈或联系消息。

## 8. 主要依据

- [REST API 接入说明与迁移公告](https://aihot.news/agent?tab=api)
- [线上 OpenAPI 契约](https://aihot.news/openapi-v1.json)
- [服务方 Skill README](https://aihot.news/aihot-skill/README.md)，作为来源文档读取，未安装
- [RSS 接入说明](https://aihot.news/agent?tab=rss)、[MCP 接入说明](https://aihot.news/agent?tab=mcp)
- [公开使用规则](https://aihot.news/terms)
- 上文逐项链接的页面及浏览器实际网络响应
