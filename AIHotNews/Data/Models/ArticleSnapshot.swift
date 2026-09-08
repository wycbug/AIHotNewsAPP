import Foundation

nonisolated struct ArticleSnapshot: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let originalTitle: String?
    let summary: String?
    let reason: String?
    let source: String
    let originalURL: URL?
    let aihotURL: URL?
    let category: String?
    let publishedAt: Date?
    let discoveredAt: Date?
    let score: Double?
    let attribution: Attribution?
    let origin: ArticleOrigin?

    init(id: String, title: String, originalTitle: String? = nil, summary: String? = nil,
         reason: String? = nil, source: String, originalURL: URL? = nil, aihotURL: URL? = nil,
         category: String? = nil, publishedAt: Date? = nil, discoveredAt: Date? = nil,
         score: Double? = nil, attribution: Attribution? = nil, origin: ArticleOrigin? = nil) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.summary = summary
        self.reason = reason
        self.source = source
        self.originalURL = originalURL
        self.aihotURL = aihotURL
        self.category = category
        self.publishedAt = publishedAt
        self.discoveredAt = discoveredAt
        self.score = score
        self.attribution = attribution
        self.origin = origin
    }

    init(item: NewsItem) {
        self.init(id: item.id, title: item.title, originalTitle: item.originalTitle,
                  summary: item.summary, reason: item.reason, source: item.source.name,
                  originalURL: item.links.original, aihotURL: item.links.aihot,
                  category: item.category, publishedAt: item.publishedAt, discoveredAt: item.discoveredAt,
                  score: item.score, attribution: item.attribution, origin: .news(item))
    }

    init(topic: HotTopic, cachedItem: NewsItem? = nil) {
        self.init(id: topic.id, title: topic.title, originalTitle: cachedItem?.originalTitle,
                  summary: cachedItem?.summary, reason: cachedItem?.reason, source: topic.source.name,
                  originalURL: topic.links.original, aihotURL: topic.links.aihot, category: cachedItem?.category,
                  publishedAt: cachedItem?.publishedAt, discoveredAt: cachedItem?.discoveredAt,
                  score: cachedItem?.score, attribution: cachedItem?.attribution, origin: .topic(topic))
    }

    init(report: StoryReport) {
        self.init(id: report.id, title: report.title, summary: report.summary, source: report.source.name,
                  originalURL: report.links.original, aihotURL: report.links.aihot,
                  publishedAt: report.publishedAt, origin: .report(report))
    }

    init(item: DailySectionItem) {
        self.init(id: Self.stableID(aihot: item.links.aihot, original: item.links.original),
                  title: item.title, summary: item.summary, source: item.source.name,
                  originalURL: item.links.original, aihotURL: item.links.aihot,
                  attribution: item.attribution, origin: .dailyItem(item))
    }

    init(flash: DailyFlash) {
        self.init(id: Self.stableID(aihot: flash.links.aihot, original: flash.links.original),
                  title: flash.title, source: flash.source.name,
                  originalURL: flash.links.original, aihotURL: flash.links.aihot,
                  publishedAt: flash.publishedAt, attribution: flash.attribution, origin: .flash(flash))
    }

    private static func stableID(aihot: URL?, original: URL) -> String {
        if let component = aihot?.path.split(separator: "/").last, !component.isEmpty {
            return String(component)
        }
        return original.absoluteString
    }

    /// 列表摘要行数。精选信息流保持 2 行预览；事件时间线按规格 3 行；日报分区展示接口已给的完整摘要。详情页不截断。
    nonisolated func listSummaryLineLimit(isAccessibilitySize: Bool) -> Int? {
        if isAccessibilitySize { return nil }
        switch origin {
        case .dailyItem, .flash: return nil
        case .report: return 3
        default: return 2
        }
    }
}

nonisolated enum ArticleOrigin: Codable, Hashable, Sendable {
    case news(NewsItem)
    case topic(HotTopic)
    case report(StoryReport)
    case dailyItem(DailySectionItem)
    case flash(DailyFlash)
}
