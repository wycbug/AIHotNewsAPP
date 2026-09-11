import Foundation
import SwiftData
import Testing
@testable import AIHotNews

@MainActor
struct LibraryTests {
    private func storage() throws -> ModelContainer {
        try ModelContainer(for: Bookmark.self, ReadRecord.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func bookmarksAndReadMarksSurviveNewContext() throws {
        let container = try storage()
        let library = LibraryStore(context: ModelContext(container))
        let article = ArticleSnapshot(id: "entry", title: "模型更新", summary: "摘要", reason: "推荐理由", source: "来源",
                                      originalURL: URL(string: "https://example.com/read"))
        library.toggleArticle(article)
        library.markRead(kind: "item", id: article.id)
        let restored = LibraryStore(context: ModelContext(container))
        #expect(restored.article(id: article.id) == article)
        #expect(restored.isRead(kind: "item", id: article.id))
        restored.clearRead()
        #expect(restored.isSaved(kind: "item", id: article.id))
        #expect(restored.readKeys.isEmpty)
        restored.toggleArticle(article)
        #expect(restored.bookmarks.isEmpty)
    }

    @Test func failedSaveRollsBackAndReportsFailure() throws {
        let container = try storage()
        let library = LibraryStore(context: ModelContext(container), saveChanges: { _ in throw CocoaError(.fileWriteNoPermission) })
        library.toggleArticle(ArticleSnapshot(id: "a", title: "标题", source: "来源"))
        #expect(library.bookmarks.isEmpty)
        #expect(library.errorMessage != nil)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Bookmark>()) == 0)
    }

    @Test func storyMergeMovesBookmarkAndReadKeyAtomically() throws {
        let container = try storage()
        let library = LibraryStore(context: ModelContext(container))
        let old = try story("old")
        let canonical = try story("canonical")
        library.toggleStory(old)
        let savedAt = try #require(library.bookmarks.first?.savedAt)
        library.markRead(kind: "story", id: old.publicId)
        library.reconcileStory(previousID: old.publicId, story: canonical)
        #expect(library.bookmarks.count == 1)
        #expect(!library.isSaved(kind: "story", id: "old"))
        #expect(library.isSaved(kind: "story", id: "canonical"))
        #expect(library.bookmark(forKey: "story:old")?.publicID == "canonical")
        #expect(library.bookmarks.first?.savedAt == savedAt)
        #expect(library.isRead(kind: "story", id: "canonical"))
        #expect(!library.isRead(kind: "story", id: "old"))
        #expect(library.decode(Story.self, from: library.bookmarks[0]) == canonical)
    }

    @Test func clearingNetworkCachePreservesOfflineLibrary() async throws {
        let container = try storage()
        let library = LibraryStore(context: ModelContext(container))
        let article = ArticleSnapshot(id: "a", title: "标题", summary: "离线摘要", source: "来源")
        library.toggleArticle(article)
        let repository = NewsRepository(client: APIClient(transport: StubTransport([])))
        try await repository.clearCache()
        #expect(library.article(id: "a")?.summary == "离线摘要")
    }

    @Test func deepLinksValidateRoutesAndRejectAmbiguousInputs() throws {
        #expect(ReaderDeepLink(url: URL(string: "aihotnews://feed")!) == .feed)
        #expect(ReaderDeepLink(url: URL(string: "aihotnews://item/abc-123")!) == .item("abc-123"))
        #expect(ReaderDeepLink(url: URL(string: "aihotnews://daily/2024-02-29")!) == .daily("2024-02-29"))
        for value in ["https://aihot.news/items/a", "aihotnews://daily/2025-02-29", "aihotnews://item/a/b",
                      "aihotnews://story/a?target=other", "aihotnews://item/%2Fsecret", "aihotnews://unknown"] {
            #expect(ReaderDeepLink(url: URL(string: value)!) == nil)
        }
    }

    @Test(arguments: [
        ("aihotnews://search?q=OpenAI", "OpenAI"),
        ("aihotnews://search?q=%20%0A%E6%A8%A1%E5%9E%8B%20", "模型"),
        ("aihotnews://search/?q=C%2B%2B%20%26%20AI", "C++ & AI"),
        ("aihotnews://search?q=C++", "C++"),
        ("aihotnews://search?q=e%CC%81", "e\u{301}")
    ])
    func searchDeepLinksDecodeAndNormalizeQuery(value: String, expected: String) {
        #expect(ReaderDeepLink(url: URL(string: value)!) == .search(expected))
    }

    @Test(arguments: [
        "aihotnews://search", "aihotnews://search?q", "aihotnews://search?q=",
        "aihotnews://search?q=%20%0A", "aihotnews://search?q=a", "aihotnews://search?q=%F0%9F%9A%80",
        "aihotnews://search?q=OpenAI&q=OpenAI", "aihotnews://search?q=OpenAI&%71=other",
        "aihotnews://search?q=OpenAI&window=7d", "aihotnews://search?Q=OpenAI",
        "aihotnews://search/extra?q=OpenAI", "aihotnews://search//?q=OpenAI",
        "aihotnews://search?q=OpenAI#other", "aihotnews://user@search?q=OpenAI",
        "aihotnews://search:123?q=OpenAI", "aihotnews://feed?q=OpenAI",
        "aihotnews://daily/2024-02-29?q=OpenAI"
    ])
    func searchDeepLinksRejectInvalidOrAmbiguousQueries(value: String) {
        #expect(ReaderDeepLink(url: URL(string: value)!) == nil)
    }

    @Test func listSummaryLineLimitsFollowReadingSurfaceAndKeepFullText() {
        let original = URL(string: "https://example.com/a")!
        let aihot = URL(string: "https://aihot.news/items/a")!
        let summary = String(repeating: "摘要段落。", count: 12)
        let item = NewsItem(
            id: "a", title: "标题", originalTitle: nil, summary: summary,
            source: NewsSource(name: "来源"), links: NewsLinks(aihot: aihot, original: original),
            publishedAt: nil, discoveredAt: Date(), category: nil, score: nil, selected: true,
            reason: "推荐理由", attribution: nil
        )
        let news = ArticleSnapshot(item: item)
        let daily = ArticleSnapshot(item: DailySectionItem(
            title: "日报条目", summary: summary, source: NewsSource(name: "来源"),
            links: DailyContentLinks(aihot: aihot, original: original), attribution: nil
        ))
        let report = ArticleSnapshot(report: StoryReport(
            id: "r", title: "报道", summary: summary,
            source: StoryReportSource(name: "来源", firstParty: false),
            publishedAt: Date(), links: StoryReportLinks(aihot: aihot, original: original)
        ))
        #expect(news.summary == summary)
        #expect(daily.summary == summary)
        #expect(report.summary == summary)
        #expect(news.listSummaryLineLimit(isAccessibilitySize: false) == 2)
        #expect(daily.listSummaryLineLimit(isAccessibilitySize: false) == nil)
        #expect(report.listSummaryLineLimit(isAccessibilitySize: false) == 3)
        #expect([news, daily, report].allSatisfy { $0.listSummaryLineLimit(isAccessibilitySize: true) == nil })
    }

    @Test func searchDeepLinkLengthUsesUnicodeCodePoints() throws {
        var components = URLComponents(string: "aihotnews://search")!
        let boundary = String(repeating: "e\u{301}", count: 100)
        components.queryItems = [URLQueryItem(name: "q", value: boundary)]
        #expect(ReaderDeepLink(url: try #require(components.url)) == .search(boundary))
        components.queryItems = [URLQueryItem(name: "q", value: boundary + "a")]
        #expect(ReaderDeepLink(url: try #require(components.url)) == nil)
    }

    @Test func deepLinksCoverTabAndContentRoutes() {
        #expect(ReaderDeepLink(url: URL(string: "aihotnews://hot")!) == .hot)
        #expect(ReaderDeepLink(url: URL(string: "aihotnews://daily")!) == .dailyHome)
        #expect(ReaderDeepLink(url: URL(string: "aihotnews://my")!) == .personal)
        #expect(ReaderDeepLink(url: URL(string: "aihotnews://story/abc-1")!) == .story("abc-1"))
        for value in ["aihotnews://item", "aihotnews://story/", "aihotnews://feed/extra",
                      "aihotnews://my/1", "aihotnews://daily/2024-02-30", "aihotnews://daily/2024-1-01"] {
            #expect(ReaderDeepLink(url: URL(string: value)!) == nil, "应拒绝 \(value)")
        }
    }

    @Test func libraryKeysCanonicalizeArticleKindAndFormatShanghaiDates() {
        #expect(LibraryKey.canonicalKind("article") == "item")
        #expect(LibraryKey.canonicalKind("item") == "item")
        #expect(LibraryKey.canonicalKind("story") == "story")
        #expect(LibraryKey.make(kind: "article", id: "x") == "item:x")
        let formatter = ISO8601DateFormatter()
        let before = formatter.date(from: "2026-09-08T15:59:59Z")!
        let after = formatter.date(from: "2026-09-08T16:00:00Z")!
        #expect(LibraryKey.dailyID(before) == "2026-09-08")
        #expect(LibraryKey.dailyID(after) == "2026-09-09")
    }

    @Test func bookmarkCanonicalizesKindAndReadKeySharing() throws {
        let container = try storage()
        let context = ModelContext(container)
        context.insert(Bookmark(kind: "article", publicID: "a", title: "t", payload: Data("null".utf8)))
        try context.save()
        let library = LibraryStore(context: context)
        #expect(library.isSaved(kind: "article", id: "a"))
        #expect(library.isSaved(kind: "item", id: "a"))
        #expect(library.bookmarks.first?.kind == "item")
        #expect(library.bookmarks.first?.key == "item:a")
    }

    @Test func dailyBookmarkUsesShanghaiDateAndLeadTitle() throws {
        let container = try storage()
        let library = LibraryStore(context: ModelContext(container))
        let withLead = try dailyReport(lead: true)
        library.toggleDaily(withLead)
        #expect(library.isSaved(kind: "daily", id: "2026-09-08"))
        #expect(library.bookmarks.first?.title == "头题")
        #expect(library.bookmarks.first?.key == "daily:2026-09-08")
        library.toggleDaily(withLead)
        #expect(library.bookmarks.isEmpty)
        let bare = try dailyReport(lead: false)
        library.toggleDaily(bare)
        #expect(library.bookmarks.first?.title == "AI 日报 · 2026-09-08")
    }

    @Test func markReadIsIdempotentAndRemoveKeepsReadMark() throws {
        let container = try storage()
        let library = LibraryStore(context: ModelContext(container))
        library.markRead(kind: "item", id: "a")
        library.markRead(kind: "item", id: "a")
        #expect(library.readKeys == ["item:a"])
        let article = ArticleSnapshot(id: "a", title: "t", source: "s")
        library.toggleArticle(article)
        let bookmark = try #require(library.bookmarks.first)
        library.remove(bookmark)
        #expect(library.bookmarks.isEmpty)
        #expect(!library.isSaved(kind: "item", id: "a"))
        #expect(library.isRead(kind: "item", id: "a"))
    }

    @Test func storyAliasChainFollowsSequentialMerges() throws {
        let container = try storage()
        let library = LibraryStore(context: ModelContext(container))
        library.toggleStory(try story("v1"))
        library.reconcileStory(previousID: "v1", story: try story("v2"))
        library.reconcileStory(previousID: "v2", story: try story("v3"))
        #expect(library.bookmarks.count == 1)
        #expect(library.bookmark(forKey: "story:v1")?.publicID == "v3")
        #expect(library.bookmark(forKey: "story:v2")?.publicID == "v3")
        #expect(library.isSaved(kind: "story", id: "v3"))
        library.reconcileStory(previousID: "v3", story: try story("v3"))
        #expect(library.bookmarks.count == 1)
    }

    @Test func corruptBookmarkPayloadReportsDecodeFailure() throws {
        let container = try storage()
        let context = ModelContext(container)
        context.insert(Bookmark(kind: "item", publicID: "bad", title: "坏副本", payload: Data("not json".utf8)))
        try context.save()
        let library = LibraryStore(context: context)
        let bookmark = try #require(library.bookmarks.first)
        #expect(library.decode(ArticleSnapshot.self, from: bookmark) == nil)
        #expect(library.errorMessage != nil)
    }

    private func story(_ id: String) throws -> Story {
        let body = Data("""
        {"schemaVersion":1,"story":{"publicId":"\(id)","title":"事件","status":"active","sourceCount":1,"reportCount":1,"firstReportAt":"2026-09-08T00:00:00Z","latestAt":"2026-09-08T01:00:00Z","latest":"进展","digest":"综述","digestUpdatedAt":null,"links":{"aihot":"https://aihot.news/story/\(id)"},"reports":[],"storyline":[],"related":[]}}
        """.utf8)
        return try APIJSON.decoder().decode(StoryResponse.self, from: body).story
    }

    private func dailyReport(lead: Bool) throws -> DailyReport {
        let leadJSON = lead ? #"{"title":"头题","leadParagraph":"导语"}"# : "null"
        let body = Data("""
        {"schemaVersion":1,"report":{"date":"2026-09-08","generatedAt":"2026-09-08T00:00:00Z","windowStart":"2026-09-07T00:00:00Z","windowEnd":"2026-09-08T00:00:00Z","links":{"aihot":"https://aihot.news/daily/2026-09-08"},"lead":\(leadJSON),"sections":[],"flashes":[]}}
        """.utf8)
        return try APIJSON.decoder().decode(DailyResponse.self, from: body).report
    }
}
