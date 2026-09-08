import Foundation
import Testing
@testable import AIHotNews

nonisolated struct APIContractTests {
    @Test func endpointDefaultsAndPaths() throws {
        let items = try APIEndpoint<ItemsResponse>.items()
        #expect(items.url.path == "/api/v1/items")
        #expect(query(items.url) == ["mode": "selected", "window": "24h", "by": "timeline", "limit": "50"])
        #expect(items.defaultFreshness == 60)
        #expect(items.cacheRetention == 604800)
        #expect(items.persistResponse)
        let hot = APIEndpoint<HotTopicsResponse>.hotTopics()
        #expect(hot.url.absoluteString == "https://aihot.news/api/v1/hot-topics")
        #expect(hot.defaultFreshness == 300)
        #expect(hot.persistResponse)
        let story = try APIEndpoint<StoryResponse>.story(publicID: "returned-id_1")
        #expect(story.url.path == "/api/v1/stories/returned-id_1")
        #expect(story.persistResponse)
        let dailies = try APIEndpoint<DailiesResponse>.dailies()
        #expect(dailies.url.path == "/api/v1/dailies")
        #expect(query(dailies.url) == ["limit": "30"])
        #expect(dailies.persistResponse)
        #expect(APIEndpoint<DailyResponse>.latestDaily().url.path == "/api/v1/dailies/latest")
        let daily = try APIEndpoint<DailyResponse>.daily(date: "2024-02-29")
        #expect(daily.url.path == "/api/v1/dailies/2024-02-29")
        #expect(daily.persistResponse)
        #expect(daily.cacheRetention > items.cacheRetention)
        let snapshot = try APIEndpoint<SnapshotResponse>.snapshot()
        #expect(snapshot.url.path == "/api/v1/selected/snapshot")
        #expect(query(snapshot.url) == ["fields": "default", "limit": "500"])
        #expect(!snapshot.persistResponse)
        let changes = try APIEndpoint<ChangesResponse>.changes(cursor: "opaque")
        #expect(changes.url.path == "/api/v1/selected/changes")
        #expect(query(changes.url) == ["cursor": "opaque", "limit": "100"])
        #expect(!changes.persistResponse)
        for url in [items.url, hot.url, story.url, dailies.url, daily.url, snapshot.url, changes.url] {
            #expect(url.scheme == "https")
            #expect(url.host == "aihot.news")
        }
    }

    @Test func queryValuesAndOpaqueCursorsRoundTrip() throws {
        let cursor = "opaque+/&=a?b#c%20 中文"
        var filter = ItemsQuery()
        filter.mode = .all
        filter.window = .week
        filter.by = .published
        filter.category = "future-category"
        filter.q = " \n AI & agents + / \t"
        filter.limit = 100
        #expect(Set([filter, filter]).count == 1)
        let items = try APIEndpoint<ItemsResponse>.items(filter, cursor: cursor)
        #expect(query(items.url) == [
            "mode": "all", "window": "7d", "by": "published", "category": "future-category",
            "q": "AI & agents + /", "limit": "100", "cursor": cursor
        ])
        #expect(items.url.absoluteString.contains("%2B"))
        #expect(!items.persistResponse)
        let snapshot = try APIEndpoint<SnapshotResponse>.snapshot(fields: .minimal, limit: 1000, page: cursor)
        #expect(query(snapshot.url) == ["fields": "minimal", "limit": "1000", "page": cursor])
        let changes = try APIEndpoint<ChangesResponse>.changes(cursor: cursor, limit: 1)
        #expect(query(changes.url) == ["cursor": cursor, "limit": "1"])
        #expect(query(changes.url)["fields"] == nil)
    }

    @Test(arguments: ["", " ", "\n\t", "a", "你", String(repeating: "a", count: 201)])
    func rejectsInvalidSearch(_ text: String) {
        #expect(throws: RequestValidationError.invalidSearchLength) {
            try APIEndpoint<ItemsResponse>.items(ItemsQuery(q: text))
        }
    }

    @Test func searchCountsScalarsNotGraphemesOrUTF16() throws {
        let combining = "e\u{301}"
        #expect(combining.count == 1)
        #expect(try query(APIEndpoint<ItemsResponse>.items(ItemsQuery(q: combining)).url)["q"] == combining)
        let supplementary = String(repeating: "\u{10400}", count: 200)
        #expect(try query(APIEndpoint<ItemsResponse>.items(ItemsQuery(q: supplementary)).url)["q"] == supplementary)
        #expect(throws: RequestValidationError.invalidSearchLength) {
            try APIEndpoint<ItemsResponse>.items(ItemsQuery(q: String(repeating: combining, count: 101)))
        }
        #expect(try query(APIEndpoint<ItemsResponse>.items(ItemsQuery(q: " \n中文 \t")).url)["q"] == "中文")
    }

    @Test func allLimitBounds() throws {
        for limit in [1, 100] {
            _ = try APIEndpoint<ItemsResponse>.items(ItemsQuery(limit: limit))
            _ = try APIEndpoint<ChangesResponse>.changes(cursor: "opaque", limit: limit)
        }
        for limit in [1, 180] { _ = try APIEndpoint<DailiesResponse>.dailies(limit: limit) }
        for limit in [1, 1000] { _ = try APIEndpoint<SnapshotResponse>.snapshot(limit: limit) }
        for limit in [Int.min, -1, 0, 101, Int.max] {
            #expect(throws: RequestValidationError.self) { try APIEndpoint<ItemsResponse>.items(ItemsQuery(limit: limit)) }
            #expect(throws: RequestValidationError.self) { try APIEndpoint<ChangesResponse>.changes(cursor: "opaque", limit: limit) }
        }
        for limit in [-1, 0, 181, Int.max] {
            #expect(throws: RequestValidationError.self) { try APIEndpoint<DailiesResponse>.dailies(limit: limit) }
        }
        for limit in [-1, 0, 1001, Int.max] {
            #expect(throws: RequestValidationError.self) { try APIEndpoint<SnapshotResponse>.snapshot(limit: limit) }
        }
        #expect(throws: RequestValidationError.emptyCursor) { try APIEndpoint<ItemsResponse>.items(cursor: "") }
        #expect(throws: RequestValidationError.emptyCursor) { try APIEndpoint<SnapshotResponse>.snapshot(page: "") }
        #expect(throws: RequestValidationError.emptyCursor) { try APIEndpoint<ChangesResponse>.changes(cursor: "") }
    }

    @Test(arguments: ["2025-02-29", "1900-02-29", "2024-04-31", "2024-13-01", "2024-00-01", "2024-01-00", "2024-01-32", "2024-2-01", "0000-01-01", "2024-01-01/x", " 2024-01-01", "２０２４-01-01"])
    func rejectsInvalidCalendarDates(_ date: String) {
        #expect(throws: RequestValidationError.invalidDate) { try APIEndpoint<DailyResponse>.daily(date: date) }
    }

    @Test(arguments: ["2000-02-29", "2024-02-29", "2025-12-31", "2026-01-01"])
    func acceptsValidCalendarDates(_ date: String) throws {
        #expect(try APIEndpoint<DailyResponse>.daily(date: date).url.lastPathComponent == date)
    }

    @Test(arguments: ["", ".", "..", "a/b", "a\\b", "a?x=1", "a#fragment", "%2F", "%252e", "a b", String(repeating: "a", count: 129)])
    func rejectsUnsafePublicIDs(_ id: String) {
        #expect(throws: RequestValidationError.invalidPublicID) { try APIEndpoint<StoryResponse>.story(publicID: id) }
    }

    @Test func trustedStoryLinks() throws {
        let id = String(repeating: "a", count: 128)
        #expect(try APIEndpoint<StoryResponse>.story(publicID: id).url.lastPathComponent == id)
        #expect(try StoryLink.publicID(from: URL(string: "https://aihot.news/stories/server-returned-id/?ref=hot#top")!) == "server-returned-id")
        #expect(try StoryLink.publicID(from: URL(string: "https://aihot.news/story/real-id")!) == "real-id")
        let returnedLink = URL(string: "https://aihot.virxact.com/story/0aae4e4a-8436-422f-8277-d105655302a5")!
        let returnedID = try StoryLink.publicID(from: returnedLink)
        #expect(returnedID == "0aae4e4a-8436-422f-8277-d105655302a5")
        #expect(try APIEndpoint<StoryResponse>.story(publicID: returnedID).url.host == "aihot.news")
        #expect(try StoryLink.publicID(from: URL(string: "https://example.com/localized/events/server-id/")!) == "server-id")
        for value in [
            "javascript:alert(1)", "https://user@aihot.news/stories/id", "https://aihot.news/",
            "https://aihot.news/stories/a%2Fb", "https://aihot.news/stories/%2e%2e"
        ] {
            #expect(throws: RequestValidationError.self) { try StoryLink.publicID(from: URL(string: value)!) }
        }
    }

    @Test func decodesItemsAndPreservesAttribution() throws {
        let response: ItemsResponse = try decode("""
        {"schemaVersion":1,"query":{"mode":"future-mode","category":"future-category","window":"future-window","q":null,"by":"future-order","ordering":"future-ordering"},"items":[\(fullItem)],"page":{"count":1,"hasMore":true,"nextCursor":"next+/&"},"future":true}
        """)
        let item = try #require(response.items.first)
        #expect(item.category == "future-category")
        #expect(item.score == 91.5)
        #expect(item.originalTitle == nil)
        #expect(item.publishedAt == nil)
        #expect(item.summary == "摘要")
        #expect(item.reason == "推荐理由")
        #expect(item.links.original.absoluteString == "https://example.com/original")
        #expect(item.attribution?.name == "AIHOT")
        #expect(item.attribution?.url.absoluteString == "https://aihot.news")
        #expect(response.page.nextCursor == "next+/&")
        #expect(response.query.mode == "future-mode")
        let encoded = try JSONEncoder().encode(item)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let attribution = try #require(object["attribution"] as? [String: String])
        #expect(attribution == ["name": "AIHOT", "url": "https://aihot.news"])
    }

    @Test func decodesHotTopicsWithAndWithoutStoryLinks() throws {
        let response: HotTopicsResponse = try decode("""
        {"schemaVersion":1,"count":2,"items":[
        {"rank":1,"id":"hot-1","title":"热点","source":{"name":"来源"},"links":{"aihot":"https://aihot.news/items/hot-1","original":"https://example.com/1","story":"https://aihot.news/stories/story-1"},"sourceCount":2,"signalCount":0,"sourceNames":["甲","乙"],"latestAt":"2026-06-11T01:02:03Z"},
        {"rank":2,"id":"hot-2","title":"热点二","source":{"name":"来源"},"links":{"aihot":"https://aihot.news/items/hot-2","original":"https://example.com/2"},"sourceCount":1,"signalCount":1,"sourceNames":["来源"],"latestAt":"2026-06-11T01:02:03.456Z"}]}
        """)
        #expect(response.items.count == 2)
        #expect(response.items[0].rank == 1)
        #expect(response.items[1].links.story == nil)
        #expect(response.items[1].latestAt > response.items[0].latestAt)
    }

    @Test func decodesStoryReportsAndNeighbors() throws {
        let response: StoryResponse = try decode("""
        {"schemaVersion":1,"story":{"publicId":"story-1","title":"事件","status":"future-status","sourceCount":1,"reportCount":1,"firstReportAt":"2026-06-11T00:00:00Z","latestAt":"2026-06-11T01:00:00+00:00","latest":"最新进展","digest":null,"digestUpdatedAt":null,"links":{"aihot":"https://aihot.news/stories/story-1"},"reports":[{"id":"report-1","title":"报道","summary":null,"source":{"name":"当事方","firstParty":true},"publishedAt":"2026-06-11T00:30:00Z","links":{"aihot":"https://aihot.news/items/report-1"}}],"storyline":[{"publicId":"story-2","title":"相邻事件","relation":"future-relation","links":{"aihot":"https://aihot.news/stories/story-2","api":"https://aihot.news/api/v1/stories/story-2"}}],"related":[]}}
        """)
        #expect(response.story.publicId == "story-1")
        #expect(response.story.status == "future-status")
        #expect(response.story.digest == nil)
        #expect(response.story.digestUpdatedAt == nil)
        #expect(response.story.reports[0].source.firstParty)
        #expect(response.story.reports[0].links.original == nil)
        #expect(response.story.storyline[0].relation == "future-relation")
        #expect(response.story.storyline[0].links.api.path == "/api/v1/stories/story-2")
    }

    @Test func decodesDailyIndexAndReportNullability() throws {
        let index: DailiesResponse = try decode("""
        {"schemaVersion":1,"count":1,"items":[{"date":"2026-06-11","generatedAt":"2026-06-11T08:00:00+08:00","leadTitle":null,"leadParagraph":null,"links":{"aihot":"https://aihot.news/daily/2026-06-11"},"attribution":\(attribution)}]}
        """)
        #expect(index.items[0].leadTitle == nil)
        #expect(index.items[0].attribution?.name == "AIHOT")
        let report: DailyResponse = try decode("""
        {"schemaVersion":1,"report":{"date":"2026-06-11","generatedAt":"2026-06-11T08:00:00+08:00","windowStart":"2026-06-10T00:00:00Z","windowEnd":"2026-06-11T00:00:00Z","links":{"aihot":"https://aihot.news/daily/2026-06-11"},"attribution":\(attribution),"lead":null,"sections":[{"label":"行业动态","items":[{"title":"分组条目","summary":"摘要","source":{"name":"原始来源"},"links":{"aihot":null,"original":"https://example.com/section"},"attribution":\(attribution)}]}],"flashes":[{"title":"快讯","source":{"name":"快讯来源"},"links":{"aihot":null,"original":"https://example.com/flash"},"publishedAt":"2026-06-11T00:00:00Z","attribution":\(attribution)}]}}
        """)
        #expect(report.report.date == index.items[0].date)
        #expect(report.report.lead == nil)
        #expect(report.report.sections[0].items[0].links.aihot == nil)
        #expect(report.report.sections[0].items[0].attribution?.name == "AIHOT")
        #expect(report.report.flashes[0].attribution?.name == "AIHOT")
        #expect(report.report.attribution?.name == "AIHOT")
        let encoded = try APIJSON.encoder().encode(report)
        let roundTrip = try APIJSON.decoder().decode(DailyResponse.self, from: encoded)
        #expect(roundTrip.report.date == report.report.date)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let reportObject = try #require(object["report"] as? [String: Any])
        #expect(reportObject["date"] as? String == "2026-06-11")
        let lead: DailyLead = try decode("""
        {"title":"头题","leadParagraph":"导语"}
        """)
        #expect(lead.leadParagraph == "导语")
    }

    @Test func snapshotFieldsSelectTheCorrectItemSchema() throws {
        let full: SnapshotResponse = try decode(snapshot(fields: "default", item: fullItem))
        guard case .full(let item) = try #require(full.items.first) else {
            Issue.record("default 快照必须解码为完整条目")
            return
        }
        #expect(item.links.original.absoluteString == "https://example.com/original")
        let minimal: SnapshotResponse = try decode(snapshot(fields: "minimal", item: minimalItem))
        guard case .minimal(let minimalNews) = try #require(minimal.items.first) else {
            Issue.record("minimal 快照必须解码为精简条目")
            return
        }
        #expect(minimalNews.id == "minimal-1")
        #expect(minimal.cursor == "watermark+/&")
        #expect(minimal.nextPage == "page+/&")
        let encoded = try JSONEncoder().encode(minimal)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let items = try #require(object["items"] as? [[String: Any]])
        let links = try #require(items[0]["links"] as? [String: Any])
        #expect(links["original"] == nil)
        #expect(items[0]["summary"] == nil)
        #expect(items[0]["originalTitle"] == nil)
        #expect(throws: DecodingError.self) {
            let _: SnapshotResponse = try decode(snapshot(fields: "default", item: minimalItem))
        }
        let future: SnapshotResponse = try decode(snapshot(fields: "future-fields", item: "{\"new\":true}"))
        guard case .unknown = future.items[0] else {
            Issue.record("未知 fields 应保留原始条目")
            return
        }
    }

    @Test(arguments: ["default", "minimal"])
    func decodesPolymorphicChanges(_ fields: String) throws {
        let response: ChangesResponse = try decode("""
        {"schemaVersion":1,"fields":"\(fields)","cursor":"next+/&","count":3,"hasMore":false,"changes":[{"op":"upsert","changedAt":"2026-06-11T00:00:00Z","item":\(fields == "default" ? fullItem : minimalItem)},{"op":"remove","changedAt":"2026-06-11T00:01:00Z","id":"removed-id"},{"op":"future-op","payload":{"retain":true}}]}
        """)
        guard case .upsert(_, let item) = response.changes[0],
              case .remove(_, let removedID) = response.changes[1],
              case .unknown(let op, let payload) = response.changes[2] else {
            Issue.record("changes 应根据 op 解码")
            return
        }
        #expect(removedID == "removed-id")
        #expect(op == "future-op")
        #expect(payload == .object(["op": .string("future-op"), "payload": .object(["retain": .bool(true)])]))
        switch (fields, item) {
        case ("default", .full(let news)): #expect(news.id == "item-1")
        case ("minimal", .minimal(let news)): #expect(news.id == "minimal-1")
        default: Issue.record("upsert 条目必须匹配响应 fields")
        }
        let encoded = try JSONEncoder().encode(response)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let changes = try #require(object["changes"] as? [[String: Any]])
        #expect(changes[0]["op"] as? String == "upsert")
        #expect(changes[1]["id"] as? String == "removed-id")
        #expect(changes[1]["item"] == nil)
        #expect(changes[2]["op"] as? String == "future-op")
        #expect(changes[2]["payload"] as? [String: Bool] == ["retain": true])
    }

    @Test func decodesProblemDetails() throws {
        let problem: APIProblem = try decode("""
        {"type":"https://aihot.news/problems/invalid-cursor","title":"Invalid cursor","status":400,"detail":"Restart from first page","code":"future_code","requestId":"request-1"}
        """)
        #expect(problem.code == "future_code")
        #expect(problem.status == 400)
        #expect(problem.requestId == "request-1")
    }

    private func query(_ url: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try APIJSON.decoder().decode(T.self, from: Data(json.utf8))
    }

    private var attribution: String {
        """
        {"name":"AIHOT","url":"https://aihot.news"}
        """
    }

    private var fullItem: String {
        """
        {"id":"item-1","title":"标题","originalTitle":null,"summary":"摘要","source":{"name":"来源"},"links":{"aihot":"https://aihot.news/items/item-1","original":"https://example.com/original"},"publishedAt":null,"discoveredAt":"2026-06-11T01:02:03.456Z","category":"future-category","score":91.5,"selected":true,"reason":"推荐理由","attribution":\(attribution)}
        """
    }

    private var minimalItem: String {
        """
        {"id":"minimal-1","title":"精简标题","source":{"name":"来源"},"links":{"aihot":"https://aihot.news/items/minimal-1"},"publishedAt":null,"discoveredAt":"2026-06-11T01:02:03Z","category":null,"score":null,"selected":true}
        """
    }

    private func snapshot(fields: String, item: String) -> String {
        """
        {"schemaVersion":1,"asOf":"2026-06-11T00:00:00Z","fields":"\(fields)","cursor":"watermark+/&","count":1,"hasMore":true,"nextPage":"page+/&","items":[\(item)]}
        """
    }
}
