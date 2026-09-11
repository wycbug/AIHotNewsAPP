import Foundation
import Testing
@testable import AIHotNews

nonisolated struct APIModelTests {
    @Test func apiErrorMetadataAndOfflineFallbackEligibility() {
        let retryAt = Date(timeIntervalSince1970: 1_700_000_000)
        let problem = APIProblem(type: "about:blank", title: "T", status: 429,
                                 detail: "稍后重试", code: "rate_limited", requestId: "req-1")
        let limited = APIError.problem(problem, retryAt: retryAt)
        #expect(limited.errorDescription == "稍后重试")
        #expect(limited.retryAt == retryAt)
        #expect(limited.requestID == "req-1")
        #expect(limited.permitsOfflineFallback)
        #expect(!limited.isNotFound)

        let emptyID = APIProblem(type: "", title: "", status: 503, detail: "", code: "", requestId: "")
        #expect(APIError.problem(emptyID, retryAt: nil).requestID == nil)
        #expect(APIError.problem(emptyID, retryAt: nil).permitsOfflineFallback)
        let serverProblem = APIProblem(type: "", title: "", status: 500, detail: "", code: "", requestId: "")
        #expect(!APIError.problem(serverProblem, retryAt: nil).permitsOfflineFallback)
        #expect(APIError.problem(APIProblem(type: "", title: "", status: 404, detail: "", code: "", requestId: ""), retryAt: nil).isNotFound)

        #expect(APIError.http(status: 404, requestID: "req-2", retryAt: nil).isNotFound)
        #expect(APIError.http(status: 404, requestID: "req-2", retryAt: nil).requestID == "req-2")
        #expect(!APIError.http(status: 404, requestID: nil, retryAt: nil).permitsOfflineFallback)
        #expect(APIError.http(status: 503, requestID: nil, retryAt: retryAt).permitsOfflineFallback)
        #expect(APIError.http(status: 503, requestID: nil, retryAt: retryAt).retryAt == retryAt)
        #expect(APIError.http(status: 503, requestID: nil, retryAt: nil).errorDescription == "服务暂时不可用（HTTP 503），请稍后重试。")

        #expect(APIError.transport(.notConnectedToInternet).permitsOfflineFallback)
        #expect(!APIError.transport(.cancelled).permitsOfflineFallback)
        #expect(APIError.rateLimited(until: retryAt).permitsOfflineFallback)
        #expect(APIError.rateLimited(until: retryAt).retryAt == retryAt)

        for error in [APIError.invalidResponse, .decoding, .cacheMiss, .invalidRedirect] {
            #expect(error.retryAt == nil)
            #expect(error.requestID == nil)
            #expect(!error.isNotFound)
            #expect(!error.permitsOfflineFallback)
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test func userAgentIncludesVersionPlatformAndOptionalActor() {
        #expect(APIUserAgent.make(version: "2.5", platform: "iPadOS") == "AIHotNews/2.5 (iPadOS)")
        let id = try! #require(UUID(uuidString: "0AAE4E4A-8436-422F-8277-D105655302A5"))
        #expect(APIUserAgent.make(version: "1.0", platform: "macOS", actorID: id)
            == "AIHotNews/1.0 (macOS) aihot-actor/0aae4e4a-8436-422f-8277-d105655302a5")
    }

    private struct DateBox: Codable { let value: APICalendarDate }

    @Test func calendarDateRoundTripsAndRejectsImpossibleDates() throws {
        let decoder = APIJSON.decoder()
        let box = try decoder.decode(DateBox.self, from: Data(#"{"value":"2026-02-28"}"#.utf8))
        #expect(String(data: try APIJSON.encoder().encode(box), encoding: .utf8) == #"{"value":"2026-02-28"}"#)
        for invalid in ["2025-02-29", "2026-13-01", "2026-00-10", "2026-01-32", "2026-1-01", "2026/01/01", " 2026-01-01", ""] {
            #expect(throws: DecodingError.self, "应拒绝 \(invalid.debugDescription)") {
                try decoder.decode(DateBox.self, from: Data("{\"value\":\"\(invalid)\"}".utf8))
            }
        }
    }

    @Test func jsonValueRoundTripsNestedStructures() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"list":[1,"two",true,null,{"k":2.5}],"n":null}"#.utf8))
        guard case .object(let root) = value, case .array(let list) = root["list"] else {
            Issue.record("JSONValue 应解码嵌套结构")
            return
        }
        #expect(list == [.number(1), .string("two"), .bool(true), .null, .object(["k": .number(2.5)])])
        #expect(root["n"] == .null)
        let encoded = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(JSONValue.self, from: encoded) == value)
    }

    @Test func articleSnapshotStableIDsAndTopicMerge() {
        let original = URL(string: "https://example.com/daily-1")!
        let aihot = URL(string: "https://aihot.news/items/daily-1")!
        let sectionItem = DailySectionItem(title: "t", summary: "s", source: NewsSource(name: "src"),
                                         links: DailyContentLinks(aihot: aihot, original: original), attribution: nil)
        #expect(ArticleSnapshot(item: sectionItem).id == "daily-1")
        let noAihot = DailySectionItem(title: "t", summary: "s", source: NewsSource(name: "src"),
                                       links: DailyContentLinks(aihot: nil, original: original), attribution: nil)
        #expect(ArticleSnapshot(item: noAihot).id == original.absoluteString)
        let flash = DailyFlash(title: "f", source: NewsSource(name: "src"),
                               links: DailyContentLinks(aihot: nil, original: original),
                               publishedAt: Date(), attribution: nil)
        #expect(ArticleSnapshot(flash: flash).id == original.absoluteString)
        #expect(ArticleSnapshot(flash: flash).publishedAt == flash.publishedAt)

        let cached = NewsItem(id: "hot-1", title: "缓存标题", originalTitle: "orig", summary: "缓存摘要",
                              source: NewsSource(name: "来源"), links: NewsLinks(aihot: aihot, original: original),
                              publishedAt: Date(timeIntervalSince1970: 1), discoveredAt: Date(timeIntervalSince1970: 2),
                              category: "paper", score: 88, selected: true, reason: "理由", attribution: nil)
        let topic = HotTopic(rank: 1, id: "hot-1", title: "热点标题", source: NewsSource(name: "热点来源"),
                             links: HotTopicLinks(aihot: aihot, original: original, story: nil),
                             sourceCount: 3, signalCount: 1, sourceNames: ["a"], latestAt: Date(timeIntervalSince1970: 3))
        let merged = ArticleSnapshot(topic: topic, cachedItem: cached)
        #expect(merged.id == "hot-1")
        #expect(merged.title == "热点标题")
        #expect(merged.summary == "缓存摘要")
        #expect(merged.originalTitle == "orig")
        #expect(merged.category == "paper")
        #expect(merged.source == "热点来源")
        #expect(merged.score == 88)
        #expect(merged.origin == .topic(topic))
        let bare = ArticleSnapshot(topic: topic)
        #expect(bare.summary == nil && bare.category == nil && bare.reason == nil)
    }
}
