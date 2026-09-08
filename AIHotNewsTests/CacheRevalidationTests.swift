import Foundation
import Testing
@testable import AIHotNews

struct CacheRevalidationTests {
    @Test func revalidationPreservesBrowsedPagesAcrossOfflineRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = snapshotClock()
        let query = ItemsQuery(q: "C++")
        let first = try APIEndpoint<ItemsResponse>.items(query)
        let second = try APIEndpoint<ItemsResponse>.items(query, cursor: "second+/=")
        let third = try APIEndpoint<ItemsResponse>.items(query, cursor: "third")
        let transport = StubTransport([
            .response(200, ["ETag": "first-tag"], try body(["a"], cursor: "second+/=", query: query)),
            .response(200, ["ETag": "second-tag"], try body(["b"], cursor: "third", query: query)),
            .response(200, [:], try body(["c"], cursor: nil, query: query)),
            .response(304, [:], Data()),
            .response(304, [:], Data())
        ])
        let cache = try ResponseCache(directory: directory)
        let client = APIClient(cache: cache, transport: transport, now: { clock.now })
        _ = try await client.fetch(first)
        clock.advance(1)
        _ = try await client.fetch(second)
        clock.advance(1)
        _ = try await client.fetch(third)
        clock.advance(61)
        _ = try await client.fetch(second, policy: .reload)
        clock.advance(1)
        let refreshed = try await client.fetch(first, policy: .reload)
        #expect(refreshed.source == .revalidated)
        #expect(refreshed.value.items.map(\.id) == ["a"])
        #expect(refreshed.value.page.nextCursor == "second+/=")

        let restored = try ResponseCache(directory: directory)
        let offlineTransport = StubTransport([.failure(.notConnectedToInternet)])
        let offline = APIClient(cache: restored, transport: offlineTransport, now: { clock.now })
        let result = try await offline.fetch(first)
        #expect(result.source == .offline)
        #expect(result.value.items.map(\.id) == ["a", "b", "c"])
        #expect(result.value.page.count == 3)
        #expect(!result.value.page.hasMore)
        #expect(result.value.page.nextCursor == nil)
        #expect(await restored.value(for: first.url, now: clock.now)?.etag == nil)
        #expect(await restored.value(for: second.url, now: clock.now) == nil)
        #expect(await restored.value(for: third.url, now: clock.now) == nil)
        #expect(await offlineTransport.requests.first?.value(forHTTPHeaderField: "If-None-Match") == nil)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("responses-v1.json"))) as? [String: Any]
        #expect(Set(saved?.keys.map { $0 } ?? []) == [first.url.absoluteString])
    }

    @Test(arguments: [true, false])
    func firstPageReplacementOnlyDropsPagesWhenContentChanges(changesItems: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = snapshotClock()
        let first = try APIEndpoint<ItemsResponse>.items()
        let second = try APIEndpoint<ItemsResponse>.items(cursor: "second")
        let replacement = try JSONSerialization.data(
            withJSONObject: JSONSerialization.jsonObject(with: body(changesItems ? ["new"] : ["a"], cursor: "second")),
            options: [.prettyPrinted, .sortedKeys]
        )
        let client = APIClient(cache: try ResponseCache(directory: directory), transport: StubTransport([
            .response(200, [:], try body(["a"], cursor: "second")),
            .response(200, [:], try body(["b"], cursor: nil)),
            .response(200, [:], replacement)
        ]), now: { clock.now })
        _ = try await client.fetch(first)
        _ = try await client.fetch(second)
        _ = try await client.fetch(first, policy: .reload)
        let restored = APIClient(cache: try ResponseCache(directory: directory), now: { clock.now })
        let expected = changesItems ? ["new"] : ["a", "b"]
        #expect(try await restored.fetch(first, policy: .cacheOnly).value.items.map(\.id) == expected)
    }

    @Test func latePageFromPreviousListDoesNotJoinReplacementList() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = snapshotClock()
        let first = try APIEndpoint<ItemsResponse>.items()
        let second = try APIEndpoint<ItemsResponse>.items(cursor: "second")
        let cache = try ResponseCache(directory: directory)
        let old = entry(try body(["a"], cursor: "second"), url: first.url, now: clock.now)
        try await cache.insert(old, for: first.url, persist: true)
        let previousRevision = try #require(await cache.listRevision(for: second.url, now: clock.now))
        let updated = entry(try body(["new"], cursor: "second"), url: first.url, now: clock.now)
        try await cache.insert(updated, for: first.url, persist: true)
        let late = entry(try body(["old-page"], cursor: nil), url: second.url, now: clock.now)
        try await cache.store(late, urls: [second.url], persist: false, generation: 0, listRevision: previousRevision)
        let restored = APIClient(cache: try ResponseCache(directory: directory), now: { clock.now })
        #expect(try await restored.fetch(first, policy: .cacheOnly).value.items.map(\.id) == ["new"])
    }

    @Test func identicalCursorsFromDifferentQueriesKeepSeparateSnapshots() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = snapshotClock()
        let selected = try APIEndpoint<ItemsResponse>.items()
        let allQuery = ItemsQuery(mode: .all)
        let all = try APIEndpoint<ItemsResponse>.items(allQuery)
        let allSecond = try APIEndpoint<ItemsResponse>.items(allQuery, cursor: "shared")
        let client = APIClient(cache: try ResponseCache(directory: directory), transport: StubTransport([
            .response(200, [:], try body(["selected"], cursor: "shared")),
            .response(200, [:], try body(["all-first"], cursor: "shared", query: allQuery)),
            .response(200, [:], try body(["all-second"], cursor: nil, query: allQuery)),
            .response(304, [:], Data())
        ]), now: { clock.now })
        _ = try await client.fetch(selected)
        _ = try await client.fetch(all)
        _ = try await client.fetch(allSecond)
        clock.advance(61)
        _ = try await client.fetch(selected, policy: .reload)
        let restored = APIClient(cache: try ResponseCache(directory: directory), now: { clock.now })
        #expect(try await restored.fetch(selected, policy: .cacheOnly).value.items.map(\.id) == ["selected"])
        #expect(try await restored.fetch(all, policy: .cacheOnly).value.items.map(\.id) == ["all-first", "all-second"])
    }

    @Test func nextShanghaiDayStartsNewListEvenWhenBodyIsIdentical() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = snapshotClock()
        let first = try APIEndpoint<ItemsResponse>.items()
        let second = try APIEndpoint<ItemsResponse>.items(cursor: "second")
        let firstBody = try body(["a"], cursor: "second")
        let transport = StubTransport([
            .response(200, ["ETag": "first-tag"], firstBody),
            .response(200, [:], try body(["yesterday-page"], cursor: nil)),
            .response(200, ["ETag": "first-tag"], firstBody)
        ])
        let client = APIClient(cache: try ResponseCache(directory: directory), transport: transport, now: { clock.now })
        _ = try await client.fetch(first)
        _ = try await client.fetch(second)
        clock.advance(24 * 60 * 60)
        _ = try await client.fetch(first, policy: .reload)
        #expect(await transport.requests.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
        let restored = APIClient(cache: try ResponseCache(directory: directory), now: { clock.now })
        #expect(try await restored.fetch(first, policy: .cacheOnly).value.items.map(\.id) == ["a"])
    }

    private func snapshotClock() -> TestClock {
        let clock = TestClock()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let tomorrowNoon = calendar.startOfDay(for: clock.now).addingTimeInterval(36 * 60 * 60)
        clock.advance(tomorrowNoon.timeIntervalSince(clock.now))
        return clock
    }

    private func body(_ ids: [String], cursor: String?, query: ItemsQuery = .init()) throws -> Data {
        let items = ids.map { id in
            NewsItem(id: id, title: id, originalTitle: nil, summary: nil, source: NewsSource(name: "Test"),
                     links: NewsLinks(aihot: URL(string: "https://aihot.news/items/\(id)")!,
                                      original: URL(string: "https://example.com/\(id)")!),
                     publishedAt: nil, discoveredAt: Date(timeIntervalSince1970: 1_700_000_000),
                     category: nil, score: nil, selected: true, reason: nil, attribution: nil)
        }
        let response = ItemsResponse(schemaVersion: 1,
                                     query: ItemsQueryEcho(mode: query.mode.rawValue, category: query.category,
                                                           window: query.window.rawValue, q: query.q,
                                                           by: query.by.rawValue, ordering: "timelineDesc"),
                                     items: items, page: Page(count: items.count, hasMore: cursor != nil, nextCursor: cursor))
        return try APIJSON.encoder().encode(response)
    }

    private func entry(_ body: Data, url: URL, now: Date) -> CachedResponse {
        CachedResponse(body: body, etag: "tag", validatedAt: now, freshUntil: now.addingTimeInterval(60),
                       expiresAt: now.addingTimeInterval(7 * 24 * 60 * 60), cacheControl: "", resolvedURL: url)
    }
}
