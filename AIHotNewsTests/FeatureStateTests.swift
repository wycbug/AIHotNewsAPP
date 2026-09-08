import Foundation
import Testing
@testable import AIHotNews

@MainActor
struct FeatureStateTests {
    @Test func freshInMemoryFirstPageKeepsPaginationAfterReturning() async throws {
        let transport = StubTransport([.response(200, ["Cache-Control": "s-maxage=60"], try itemsBody(["a"], cursor: "next"))])
        let model = FeedViewModel(repository: NewsRepository(client: APIClient(transport: transport)))
        await model.load()
        #expect(model.nextCursor == "next")
        await model.load()
        #expect(model.nextCursor == "next")
        #expect(model.items.map(\.id) == ["a"])
        #expect(await transport.requests.count == 1)
    }

    @Test func cachedCursorFromPreviousShanghaiDayIsRejected() async throws {
        let cache = ResponseCache.memory()
        let endpoint = try APIEndpoint<ItemsResponse>.items()
        let now = Date()
        let entry = CachedResponse(body: try itemsBody(["a"], cursor: "old"), etag: "old",
                                   validatedAt: now.addingTimeInterval(-86_400), freshUntil: now.addingTimeInterval(600),
                                   expiresAt: now.addingTimeInterval(600), cacheControl: "s-maxage=60", resolvedURL: endpoint.url)
        try await cache.insert(entry, for: endpoint.url, persist: false)
        let transport = StubTransport([])
        let model = FeedViewModel(repository: NewsRepository(client: APIClient(cache: cache, transport: transport)))
        await model.load()
        #expect(model.items.map(\.id) == ["a"])
        #expect(model.nextCursor == nil)
        #expect(await transport.requests.count == 1)
        #expect(await transport.requests.first?.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func offlinePaginationKeepsCursorAndRowsUntilSuccessfulRetry() async throws {
        let endpoint = try APIEndpoint<ItemsResponse>.items(cursor: "next")
        let transport = StubTransport([
            .response(200, [:], try itemsBody(["cached-page"], cursor: "later")),
            .response(200, [:], try itemsBody(["a"], cursor: "next")),
            .failure(.notConnectedToInternet),
            .response(200, [:], try itemsBody(["a", "b", "b"], cursor: nil))
        ])
        let client = APIClient(transport: transport)
        _ = try await client.fetch(endpoint)
        let model = FeedViewModel(repository: NewsRepository(client: client))
        await model.load()
        await model.loadMore()
        #expect(model.items.map(\.id) == ["a"])
        #expect(model.nextCursor == "next")
        #expect(model.pageError != nil)
        #expect(!model.isPaging)
        await model.loadMore()
        #expect(model.items.map(\.id) == ["a", "b"])
        #expect(model.nextCursor == nil)
        #expect(model.pageError == nil)
        #expect(await transport.requests.count == 4)
    }

    @Test func rateLimitedPaginationKeepsRetryDeadlineAndCursor() async throws {
        let transport = StubTransport([
            .response(200, [:], try itemsBody(["cached-page"], cursor: nil)),
            .response(200, [:], try itemsBody(["a"], cursor: "next")),
            .response(429, ["Retry-After": "120"], problemBody(code: "rate_limited", status: 429))
        ])
        let client = APIClient(transport: transport)
        _ = try await client.fetch(APIEndpoint<ItemsResponse>.items(cursor: "next"))
        let model = FeedViewModel(repository: NewsRepository(client: client))
        await model.load()
        await model.loadMore()
        #expect(model.pageError != nil)
        #expect(model.retryAt.map { $0 > .now } == true)
        #expect(model.nextCursor == "next")
        await model.loadMore()
        await model.load(reload: true)
        #expect(model.nextCursor == "next")
        #expect(model.items.map(\.id) == ["a"])
        #expect(await transport.requests.count == 3)
    }

    @Test func invalidCursorRestartsExactlyTheSameQueryOnce() async throws {
        let transport = StubTransport([
            .response(200, [:], try itemsBody(["a"], cursor: "expired")),
            .response(400, [:], problemBody(code: "invalid_cursor", status: 400)),
            .response(400, [:], problemBody(code: "invalid_cursor", status: 400))
        ])
        let model = FeedViewModel(repository: NewsRepository(client: APIClient(transport: transport)))
        model.query.mode = .all
        model.query.window = .week
        model.query.category = "paper"
        model.searchText = "模型"
        await model.load()
        await model.loadMore()
        let requests = await transport.requests
        #expect(requests.count == 3)
        #expect(requests.first?.url == requests.last?.url)
        #expect(requests.dropFirst().first?.url.flatMap { queryValue("cursor", in: $0) } == "expired")
        #expect(model.nextCursor == nil)
        #expect(model.message != nil)
        #expect(!model.isLoading && !model.isPaging)
    }

    @Test func queryChangeDoesNotReuseCursorAndPagesAreDeduplicated() async throws {
        let transport = StubTransport([
            .response(200, [:], try itemsBody(["old"], cursor: "old-cursor")),
            .response(200, [:], try itemsBody(["a"], cursor: "new-cursor")),
            .response(200, [:], try itemsBody(["a", "b", "b"], cursor: nil))
        ])
        let model = FeedViewModel(repository: NewsRepository(client: APIClient(transport: transport)))
        await model.load()
        model.query.mode = .all
        await model.loadMore()
        #expect(await transport.requests.count == 1)
        await model.load()
        await model.loadMore()
        let requests = await transport.requests
        #expect(requests.count == 3)
        #expect(requests.dropFirst().first?.url.flatMap { queryValue("cursor", in: $0) } == nil)
        #expect(requests.last?.url.flatMap { queryValue("cursor", in: $0) } == "new-cursor")
        #expect(requests.last?.url.flatMap { queryValue("mode", in: $0) } == "all")
        #expect(model.items.map(\.id) == ["a", "b"])
    }

    @Test func lateInvalidCursorDoesNotRestartChangedQuery() async throws {
        let transport = FeatureGateTransport([
            .init(body: try itemsBody(["old"], cursor: "old-cursor")),
            .init(status: 400, body: problemBody(code: "invalid_cursor", status: 400), held: true),
            .init(body: try itemsBody(["new"], cursor: nil))
        ])
        let model = FeedViewModel(repository: NewsRepository(client: APIClient(transport: transport)))
        await model.load()
        let page = Task { await model.loadMore() }
        let started = await transport.waitForRequests(2)
        #expect(started)
        model.query.mode = .all
        await model.load()
        await transport.release(1)
        await page.value
        #expect(await transport.requestCount == 3)
        #expect(model.items.map(\.id) == ["new"])
        #expect(model.pageError == nil)
    }

    @Test func resourceSwitchWhileLoadingRejectsLateOldResponse() async throws {
        let transport = FeatureGateTransport([
            .init(body: dailiesBody(1), held: true),
            .init(body: dailiesBody(2))
        ])
        let model = ResourceViewModel<DailiesResponse>(repository: NewsRepository(client: APIClient(transport: transport)))
        let old = Task { await model.load(try! .dailies(limit: 1)) }
        let started = await transport.waitForRequests(1)
        #expect(started)
        await model.load(try .dailies(limit: 2))
        #expect(model.value?.count == 2)
        #expect(!model.isLoading)
        await transport.release(0)
        await old.value
        #expect(model.value?.count == 2)
        #expect(await transport.requestCount == 2)
    }

    @Test func switchingResourceClearsPreviouslyDisplayedValueBeforeResponse() async throws {
        let transport = FeatureGateTransport([
            .init(body: dailiesBody(1)),
            .init(body: dailiesBody(2), held: true)
        ])
        let model = ResourceViewModel<DailiesResponse>(repository: NewsRepository(client: APIClient(transport: transport)))
        await model.load(try .dailies(limit: 1))
        let next = Task { await model.load(try! .dailies(limit: 2)) }
        let started = await transport.waitForRequests(2)
        #expect(started)
        #expect(model.value == nil)
        #expect(model.isLoading)
        await transport.release(1)
        await next.value
        #expect(model.value?.count == 2)
    }

    @Test func cancellationOfOldResourceDoesNotClearNewLoadingState() async throws {
        let transport = FeatureGateTransport([
            .init(body: dailiesBody(1), held: true),
            .init(body: dailiesBody(2), held: true)
        ])
        let model = ResourceViewModel<DailiesResponse>(repository: NewsRepository(client: APIClient(transport: transport)))
        let old = Task { await model.load(try! .dailies(limit: 1)) }
        let oldStarted = await transport.waitForRequests(1)
        #expect(oldStarted)
        let next = Task { await model.load(try! .dailies(limit: 2)) }
        let nextStarted = await transport.waitForRequests(2)
        #expect(nextStarted)
        old.cancel()
        await transport.release(0)
        await old.value
        #expect(model.isLoading)
        #expect(model.value == nil)
        #expect(model.message == nil)
        await transport.release(1)
        await next.value
        #expect(model.value?.count == 2)
        #expect(!model.isLoading)
    }

    @Test func resourceSwitchHonorsSharedRateLimitedDeadline() async throws {
        let transport = StubTransport([
            .response(429, ["Retry-After": "120"], problemBody(code: "rate_limited", status: 429))
        ])
        let model = ResourceViewModel<DailiesResponse>(repository: NewsRepository(client: APIClient(transport: transport)))
        await model.load(try .dailies(limit: 1))
        let deadline = model.retryAt
        #expect(deadline.map { $0 > .now } == true)
        await model.load(try .dailies(limit: 2))
        #expect(model.retryAt == deadline)
        #expect(model.value == nil)
        #expect(!model.isLoading)
        #expect(await transport.requests.count == 1)
    }

    @Test func sharedClientRateLimitIsVisibleInAnotherResource() async throws {
        let transport = StubTransport([
            .response(429, ["Retry-After": "120"], problemBody(code: "rate_limited", status: 429))
        ])
        let client = APIClient(transport: transport)
        _ = try? await client.fetch(APIEndpoint<HotTopicsResponse>.hotTopics())
        let model = ResourceViewModel<DailiesResponse>(repository: NewsRepository(client: client))
        await model.load(try .dailies())
        #expect(model.retryAt.map { $0 > .now } == true)
        #expect(model.message != nil)
        #expect(!model.isLoading)
        #expect(await transport.requests.count == 1)
    }

    @Test func cancellingDebouncedFeedDoesNotPublishAnErrorOrFetch() async {
        let transport = StubTransport([])
        let model = FeedViewModel(repository: NewsRepository(client: APIClient(transport: transport)))
        model.searchText = "模型"
        let task = Task { await model.load(debounce: true) }
        await Task.yield()
        task.cancel()
        await task.value
        #expect(!model.isLoading)
        #expect(model.message == nil)
        #expect(await transport.requests.isEmpty)
    }

    @Test func externalLinkPolicyRejectsNonWebSchemes() throws {
        for address in ["https://example.com/story", "http://example.com/story", "HTTPS://example.com/story"] {
            #expect(ExternalLinkPolicy.allows(try #require(URL(string: address))))
        }
        for address in ["file:///etc/passwd", "javascript:alert(1)", "mailto:test@example.com", "tel:123", "aihotnews://feed", "https:relative"] {
            #expect(!ExternalLinkPolicy.allows(try #require(URL(string: address))))
        }
    }

    @Test func returningToFeedPreservesAllLoadedPagesAndCursor() async throws {
        let transport = StubTransport([
            .response(200, [:], try itemsBody(["a"], cursor: "next")),
            .response(200, [:], try itemsBody(["b"], cursor: "third"))
        ])
        let model = FeedViewModel(repository: NewsRepository(client: APIClient(transport: transport)))
        await model.load()
        await model.loadMore()
        await model.load()
        #expect(model.items.map(\.id) == ["a", "b"])
        #expect(model.nextCursor == "third")
        #expect(await transport.requests.count == 2)
    }

    @Test(arguments: [true, false])
    func revalidatedFirstPagePreservesLoadedPagesAndPagination(hasMore: Bool) async throws {
        let cursor = hasMore ? "third" : nil
        let transport = StubTransport([
            .response(200, ["ETag": "first-tag", "Cache-Control": "no-cache"], try itemsBody(["a"], cursor: "next")),
            .response(200, [:], try itemsBody(["b"], cursor: cursor)),
            .response(304, ["Cache-Control": "s-maxage=60"], Data())
        ])
        let model = FeedViewModel(repository: NewsRepository(client: APIClient(transport: transport)))
        await model.load()
        await model.loadMore()
        await model.refreshIfIdle()
        #expect(model.items.map(\.id) == ["a", "b"])
        #expect(model.nextCursor == cursor)
        #expect(model.hasMore == hasMore)
        #expect(model.message?.hasPrefix("更新于") == true)
        await model.load()
        #expect(model.items.map(\.id) == ["a", "b"])
        #expect(model.nextCursor == cursor)
        #expect(model.hasMore == hasMore)
        let requests = await transport.requests
        #expect(requests.count == 3)
        #expect(requests.last?.value(forHTTPHeaderField: "If-None-Match") == "first-tag")
    }

    @Test func changedFirstPageReplacesLoadedPages() async throws {
        let transport = StubTransport([
            .response(200, ["Cache-Control": "no-cache"], try itemsBody(["a"], cursor: "next")),
            .response(200, [:], try itemsBody(["b"], cursor: "third")),
            .response(200, [:], try itemsBody(["new"], cursor: "new-next"))
        ])
        let model = FeedViewModel(repository: NewsRepository(client: APIClient(transport: transport)))
        await model.load()
        await model.loadMore()
        await model.refreshIfIdle()
        #expect(model.items.map(\.id) == ["new"])
        #expect(model.nextCursor == "new-next")
        #expect(model.hasMore)
        #expect(await transport.requests.count == 3)
    }

    @Test func revalidatedSharedCacheUpdateReplacesPreviouslyDisplayedPages() async throws {
        let transport = StubTransport([
            .response(200, ["ETag": "old-tag", "Cache-Control": "no-cache"], try itemsBody(["a"], cursor: "next")),
            .response(200, [:], try itemsBody(["b"], cursor: "third")),
            .response(200, ["ETag": "new-tag", "Cache-Control": "no-cache"], try itemsBody(["new"], cursor: "new-next")),
            .response(304, [:], Data())
        ])
        let client = APIClient(transport: transport)
        let model = FeedViewModel(repository: NewsRepository(client: client))
        await model.load()
        await model.loadMore()
        _ = try await client.fetch(APIEndpoint<ItemsResponse>.items(), policy: .reload)
        await model.refreshIfIdle()
        #expect(model.items.map(\.id) == ["new"])
        #expect(model.nextCursor == "new-next")
        #expect(model.hasMore)
        let requests = await transport.requests
        #expect(requests.count == 4)
        #expect(requests.last?.value(forHTTPHeaderField: "If-None-Match") == "new-tag")
    }

    @Test func invalidCursorRebuildsPaginationEvenWhenFirstPageIsRevalidated() async throws {
        let transport = StubTransport([
            .response(200, ["ETag": "first-tag"], try itemsBody(["a"], cursor: "next")),
            .response(200, [:], try itemsBody(["b"], cursor: "expired")),
            .response(400, [:], problemBody(code: "invalid_cursor", status: 400)),
            .response(304, [:], Data())
        ])
        let model = FeedViewModel(repository: NewsRepository(client: APIClient(transport: transport)))
        await model.load()
        await model.loadMore()
        await model.loadMore()
        #expect(model.items.map(\.id) == ["a"])
        #expect(model.nextCursor == "next")
        #expect(model.hasMore)
        #expect(model.pageError == nil)
        #expect(await transport.requests.count == 4)
    }

    @Test func nextShanghaiDayRebuildsPaginationForUnchangedFirstPage() async throws {
        let clock = TestClock()
        let transport = StubTransport([
            .response(200, ["ETag": "first-tag"], try itemsBody(["a"], cursor: "next")),
            .response(200, [:], try itemsBody(["b"], cursor: "third")),
            .response(200, ["ETag": "first-tag"], try itemsBody(["a"], cursor: "next"))
        ])
        let client = APIClient(transport: transport, now: { clock.now })
        let model = FeedViewModel(repository: NewsRepository(client: client), now: { clock.now })
        await model.load()
        await model.loadMore()
        clock.advance(86_400)
        _ = try await client.fetch(APIEndpoint<ItemsResponse>.items(), policy: .reload)
        await model.refreshIfIdle()
        #expect(model.items.map(\.id) == ["a"])
        #expect(model.nextCursor == "next")
        #expect(model.hasMore)
        let requests = await transport.requests
        #expect(requests.count == 3)
        #expect(requests.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func browsedPagesPersistAsCursorFreeOfflineSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try ResponseCache(directory: directory)
        let client = APIClient(cache: cache, transport: StubTransport([
            .response(200, ["ETag": "first-tag"], try itemsBody(["a"], cursor: "sensitive-cursor")),
            .response(200, ["ETag": "page-tag"], try itemsBody(["a", "b"], cursor: "next-secret"))
        ]))
        let model = FeedViewModel(repository: NewsRepository(client: client))
        await model.load()
        await model.loadMore()
        let disk = try String(contentsOf: directory.appendingPathComponent("responses-v1.json"), encoding: .utf8)
        #expect(!disk.contains("sensitive-cursor"))
        #expect(!disk.contains("next-secret"))
        let restored = APIClient(cache: try ResponseCache(directory: directory), transport: StubTransport([]))
        let snapshot = try #require(await restored.cached(APIEndpoint<ItemsResponse>.items()))
        #expect(snapshot.value.items.map(\.id) == ["a", "b"])
        #expect(snapshot.value.page.nextCursor == nil)
        #expect(await restored.cachedItem(id: "b")?.id == "b")
        _ = try await client.fetch(APIEndpoint<ItemsResponse>.items(), policy: .cacheOnly)
        let firstPage = try APIEndpoint<ItemsResponse>.items()
        #expect(await client.cached(firstPage)?.value.items.map(\.id) == ["a"])
    }

    @Test func diskFirstPageIsRenderedOfflineWithoutPretendingPaginationEnded() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try ResponseCache(directory: directory)
        let client = APIClient(cache: cache, transport: StubTransport([
            .response(200, [:], try itemsBody(["saved"], cursor: "opaque"))
        ]))
        _ = try await client.fetch(APIEndpoint<ItemsResponse>.items())
        let offline = APIClient(cache: try ResponseCache(directory: directory), transport: StubTransport([.failure(.notConnectedToInternet)]))
        let model = FeedViewModel(repository: NewsRepository(client: offline))
        await model.load()
        #expect(model.items.map(\.id) == ["saved"])
        #expect(model.nextCursor == nil)
        #expect(model.hasMore)
        #expect(model.message?.hasPrefix("离线") == true)
    }

    private func itemsBody(_ ids: [String], cursor: String?) throws -> Data {
        let items: [[String: Any]] = ids.map { id in
            ["id": id, "title": id, "originalTitle": NSNull(), "summary": NSNull(),
             "source": ["name": "Test"],
             "links": ["aihot": "https://aihot.news/items/\(id)", "original": "https://example.com/\(id)"],
             "publishedAt": NSNull(), "discoveredAt": "2026-09-08T00:00:00Z",
             "category": NSNull(), "score": NSNull(), "selected": true]
        }
        return try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "query": ["mode": "selected", "category": NSNull(), "window": "24h", "q": NSNull(),
                      "by": "timeline", "ordering": "timelineDesc"],
            "items": items,
            "page": ["count": ids.count, "hasMore": cursor != nil, "nextCursor": cursor.map { $0 as Any } ?? NSNull()]
        ])
    }

    private func dailiesBody(_ count: Int) -> Data {
        Data("{\"schemaVersion\":1,\"count\":\(count),\"items\":[]}".utf8)
    }

    private func problemBody(code: String, status: Int) -> Data {
        Data("{\"type\":\"about:blank\",\"title\":\"Error\",\"status\":\(status),\"detail\":\"Retry\",\"code\":\"\(code)\",\"requestId\":\"test\"}".utf8)
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}

private actor FeatureGateTransport: HTTPTransport {
    nonisolated struct Step: Sendable {
        var status = 200
        let body: Data
        var held = false
    }

    private let steps: [Step]
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var released: Set<Int> = []
    private(set) var requestCount = 0

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let index = requestCount
        requestCount += 1
        guard steps.indices.contains(index) else { throw URLError(.badServerResponse) }
        let step = steps[index]
        if step.held && !released.contains(index) {
            await withCheckedContinuation { continuations[index] = $0 }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: step.status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        return HTTPResponse(data: step.body, response: response)
    }

    func release(_ index: Int) {
        released.insert(index)
        continuations.removeValue(forKey: index)?.resume()
    }

    func waitForRequests(_ count: Int) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while requestCount < count && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return requestCount >= count
    }
}
