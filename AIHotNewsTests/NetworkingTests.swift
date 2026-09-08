import Foundation
import Testing
@testable import AIHotNews

struct NetworkingTests {
    private let hotBody = Data(#"{"schemaVersion":1,"count":0,"items":[]}"#.utf8)

    @Test func conditionalRequestReusesBodyOn304() async throws {
        let clock = TestClock()
        let transport = StubTransport([
            .response(200, ["ETag": "\"v1\"", "Cache-Control": "public, s-maxage=300"], hotBody),
            .response(304, ["ETag": "\"v1\""], Data())
        ])
        let client = APIClient(transport: transport, now: { clock.now })
        let first = try await client.fetch(.hotTopics())
        #expect(first.source == .network)
        let fresh = try await client.fetch(.hotTopics())
        #expect(fresh.source == .cache)
        #expect(await transport.requests.count == 1)
        clock.advance(301)
        let next = try await client.fetch(.hotTopics())
        #expect(next.source == .revalidated)
        #expect(next.value.count == 0)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[1].value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(requests[0].value(forHTTPHeaderField: "Accept")?.contains("application/json") == true)
    }

    @Test func reloadStillUsesConditionalHeaders() async throws {
        let transport = StubTransport([
            .response(200, ["ETag": "first", "Cache-Control": "s-maxage=300"], hotBody),
            .response(304, [:], Data())
        ])
        let client = APIClient(transport: transport)
        _ = try await client.fetch(.hotTopics())
        let result = try await client.fetch(.hotTopics(), policy: .reload)
        #expect(result.source == .revalidated)
        #expect(await transport.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "first")
    }

    @Test func missing304BodyDoesNotBecomeEmptySuccess() async throws {
        let client = APIClient(transport: StubTransport([.response(304, [:], Data())]))
        await #expect(throws: APIError.self) { _ = try await client.fetch(.hotTopics()) }
    }

    @Test func offlineFallbackRetainsDataAndFailure() async throws {
        let clock = TestClock()
        let transport = StubTransport([.response(200, [:], hotBody), .failure(.notConnectedToInternet)])
        let client = APIClient(transport: transport, now: { clock.now })
        _ = try await client.fetch(.hotTopics())
        clock.advance(301)
        let result = try await client.fetch(.hotTopics())
        #expect(result.source == .offline)
        #expect(result.staleError != nil)
        #expect(result.value.count == 0)
    }

    @Test func cancellationIsNotAnOfflineSuccess() async throws {
        let transport = StubTransport([.response(200, [:], hotBody), .failure(.cancelled)])
        let client = APIClient(transport: transport)
        _ = try await client.fetch(.hotTopics())
        await #expect(throws: CancellationError.self) { _ = try await client.fetch(.hotTopics(), policy: .reload) }
    }

    @Test func retryAfterBlocksOtherURLsAndPreservesProblem() async throws {
        let clock = TestClock()
        let body = Data(#"{"type":"about:blank","title":"Too Many Requests","status":429,"detail":"Wait","code":"rate_limited","requestId":"request-1"}"#.utf8)
        let transport = StubTransport([.response(429, ["Retry-After": "120"], body), .response(200, [:], hotBody)])
        let client = APIClient(transport: transport, now: { clock.now })
        do {
            _ = try await client.fetch(.hotTopics())
            Issue.record("Expected rate limit")
        } catch APIError.problem(let problem, let retryAt) {
            #expect(problem.code == "rate_limited")
            #expect(problem.requestId == "request-1")
            #expect(retryAt == clock.now.addingTimeInterval(120))
        }
        do {
            _ = try await client.fetch(.latestDaily())
            Issue.record("Expected shared cooldown")
        } catch APIError.rateLimited(let until) {
            #expect(until == clock.now.addingTimeInterval(120))
        }
        #expect(await transport.requests.count == 1)
        clock.advance(121)
        _ = try await client.fetch(.hotTopics())
        #expect(await transport.requests.count == 2)
    }

    @Test func serverProblemIsNotHiddenByCache() async throws {
        let body = Data(#"{"type":"about:blank","title":"Bad Request","status":400,"detail":"Invalid query","code":"invalid_cursor","requestId":"r"}"#.utf8)
        let client = APIClient(transport: StubTransport([.response(200, [:], hotBody), .response(400, [:], body)]))
        _ = try await client.fetch(.hotTopics())
        do {
            _ = try await client.fetch(.hotTopics(), policy: .reload)
            Issue.record("Expected problem")
        } catch APIError.problem(let problem, _) {
            #expect(problem.code == "invalid_cursor")
        }
    }

    @Test func invalidPayloadDoesNotPoisonCache() async throws {
        let client = APIClient(transport: StubTransport([
            .response(200, [:], hotBody), .response(200, [:], Data("not JSON".utf8))
        ]))
        _ = try await client.fetch(.hotTopics())
        await #expect(throws: APIError.self) { _ = try await client.fetch(.hotTopics(), policy: .reload) }
        #expect(await client.cached(.hotTopics())?.value.count == 0)
    }

    @Test func cacheControlNoStoreAndAgeAreHonored() async throws {
        let client = APIClient(transport: StubTransport([.response(200, ["Cache-Control": "no-store"], hotBody)]))
        _ = try await client.fetch(.hotTopics())
        #expect(await client.cached(.hotTopics()) == nil)
        let response = HTTPURLResponse(url: URL(string: "https://aihot.news/api/v1/hot-topics")!, statusCode: 200,
                                       httpVersion: nil, headerFields: ["Age": "20"])!
        #expect(HTTPHeaders.freshness("max-age=10, s-maxage=\"300\"", response: response, fallback: 1) == 280)
        #expect(HTTPHeaders.freshness("no-cache, s-maxage=300", response: response, fallback: 1) == 0)
    }

    @Test func concurrentRequestsAreCoalesced() async throws {
        let transport = StubTransport([.response(200, [:], hotBody)], delay: .milliseconds(100))
        let client = APIClient(transport: transport)
        async let first = client.fetch(APIEndpoint<HotTopicsResponse>.hotTopics())
        async let second = client.fetch(APIEndpoint<HotTopicsResponse>.hotTopics())
        let (a, b) = try await (first, second)
        #expect(a.value.count == b.value.count)
        #expect(await transport.requests.count == 1)
    }

    @Test func notFoundEvictsPreviousResponse() async throws {
        let client = APIClient(transport: StubTransport([.response(200, [:], hotBody), .response(404, [:], Data())]))
        _ = try await client.fetch(.hotTopics())
        await #expect(throws: APIError.self) { _ = try await client.fetch(.hotTopics(), policy: .reload) }
        #expect(await client.cached(.hotTopics()) == nil)
    }

    @Test func rejectsForeignAndNonStoryRedirects() async throws {
        let endpoint = try APIEndpoint<StoryResponse>.story(publicID: "old-story")
        for location in ["https://example.com/api/v1/stories/new", "http://aihot.news/api/v1/stories/new", "/stories/new", "/api/v1/stories/new?secret=x"] {
            let client = APIClient(transport: StubTransport([.response(308, ["Location": location], Data())]))
            await #expect(throws: APIError.self) { _ = try await client.fetch(endpoint) }
        }
    }

    @Test func followsStoryMergeAndExposesCanonicalURL() async throws {
        let body = Data(#"{"schemaVersion":1,"story":{"publicId":"new-story","title":"Event","status":"active","sourceCount":1,"reportCount":1,"firstReportAt":"2026-09-08T00:00:00Z","latestAt":"2026-09-08T01:00:00.000Z","latest":"Update","digest":null,"digestUpdatedAt":null,"links":{"aihot":"https://aihot.news/stories/new-story"},"reports":[],"storyline":[],"related":[]}}"#.utf8)
        let transport = StubTransport([
            .response(308, ["Location": "/api/v1/stories/new-story"], Data()),
            .response(200, ["ETag": "new"], body)
        ])
        let client = APIClient(transport: transport)
        let endpoint = try APIEndpoint<StoryResponse>.story(publicID: "old-story")
        let result = try await client.fetch(endpoint)
        #expect(result.value.story.publicId == "new-story")
        #expect(result.resolvedURL.path == "/api/v1/stories/new-story")
        #expect(await client.cached(endpoint)?.resolvedURL == result.resolvedURL)
        #expect(await transport.requests.count == 2)
    }

    @Test func mergedStoryRevalidationUsesCanonicalURL() async throws {
        let body = Data(#"{"schemaVersion":1,"story":{"publicId":"new-story","title":"Event","status":"active","sourceCount":1,"reportCount":1,"firstReportAt":"2026-09-08T00:00:00Z","latestAt":"2026-09-08T01:00:00Z","latest":"Update","digest":null,"digestUpdatedAt":null,"links":{"aihot":"https://aihot.news/story/new-story"},"reports":[],"storyline":[],"related":[]}}"#.utf8)
        let transport = StubTransport([
            .response(308, ["Location": "/api/v1/stories/new-story"], Data()),
            .response(200, ["ETag": "canonical"], body),
            .response(304, [:], Data())
        ])
        let client = APIClient(transport: transport)
        let old = try APIEndpoint<StoryResponse>.story(publicID: "old-story")
        let canonical = try APIEndpoint<StoryResponse>.story(publicID: "new-story")
        _ = try await client.fetch(old)
        #expect(await client.cached(canonical)?.value.story.publicId == "new-story")
        _ = try await client.fetch(old, policy: .reload)
        let request = try #require(await transport.requests.last)
        #expect(request.url == canonical.url)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "canonical")
    }

    @Test func datedDailyPersistsWithFiniteLongTermRetention() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try ResponseCache(directory: directory)
        let body = Data(#"{"schemaVersion":1,"report":{"date":"2026-09-08","generatedAt":"2026-09-08T00:00:00Z","windowStart":"2026-09-07T00:00:00Z","windowEnd":"2026-09-08T00:00:00Z","links":{"aihot":"https://aihot.news/daily/2026-09-08"},"lead":null,"sections":[],"flashes":[]}}"#.utf8)
        let endpoint = try APIEndpoint<DailyResponse>.daily(date: "2026-09-08")
        let client = APIClient(cache: cache, transport: StubTransport([.response(200, [:], body)]))
        _ = try await client.fetch(endpoint)
        let restored = try ResponseCache(directory: directory)
        let entry = try #require(await restored.value(for: endpoint.url, now: Date().addingTimeInterval(8 * 86_400)))
        #expect(entry.freshUntil > Date().addingTimeInterval(8 * 86_400))
        #expect(try APIJSON.decoder().decode(DailyResponse.self, from: entry.body).report.lead == nil)
    }

    @Test func storyRedirectLoopIsBounded() async throws {
        let transport = StubTransport([
            .response(308, ["Location": "/api/v1/stories/other"], Data()),
            .response(308, ["Location": "/api/v1/stories/start"], Data())
        ])
        let client = APIClient(transport: transport)
        let endpoint = try APIEndpoint<StoryResponse>.story(publicID: "start")
        await #expect(throws: APIError.self) { _ = try await client.fetch(endpoint) }
        #expect(await transport.requests.count == 2)
    }

    @Test func cancellingOneWaiterDoesNotCancelAnother() async throws {
        let transport = StubTransport([.response(200, [:], hotBody)], delay: .milliseconds(200))
        let client = APIClient(transport: transport)
        let first = Task { try await client.fetch(APIEndpoint<HotTopicsResponse>.hotTopics()) }
        let second = Task { try await client.fetch(APIEndpoint<HotTopicsResponse>.hotTopics()) }
        try await Task.sleep(for: .milliseconds(50))
        first.cancel()
        await #expect(throws: CancellationError.self) { _ = try await first.value }
        #expect(try await second.value.value.count == 0)
        #expect(await transport.requests.count == 1)
    }

    @Test func clearingCacheDuringRequestDoesNotRepopulateIt() async throws {
        let transport = StubTransport([.response(200, [:], hotBody)], delay: .milliseconds(200))
        let client = APIClient(transport: transport)
        let task = Task { try await client.fetch(APIEndpoint<HotTopicsResponse>.hotTopics()) }
        try await Task.sleep(for: .milliseconds(50))
        try await client.clearCache()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(await client.cached(.hotTopics()) == nil)
    }

    @Test func httpDateRetryAfter() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(HTTPHeaders.retryDate("Thu, 01 Jan 1970 00:02:00 GMT", now: now) == Date(timeIntervalSince1970: 120))
        #expect(HTTPHeaders.retryDate("nonsense", now: now) == nil)
        #expect(HTTPHeaders.retryDate("-3", now: now) == now)
    }

    @Test func dailyIndexFreshnessStopsAtNextShanghaiPublication() throws {
        let now = ISO8601DateFormatter().date(from: "2026-09-08T23:59:00Z")!
        let endpoint = APIEndpoint<DailyResponse>.latestDaily()
        let response = HTTPURLResponse(url: endpoint.url, statusCode: 200, httpVersion: nil, headerFields: [:])!
        #expect(endpoint.freshUntil(control: "s-maxage=86400", response: response, now: now) == now.addingTimeInterval(60))
        #expect(endpoint.freshUntil(control: "s-maxage=30", response: response, now: now) == now.addingTimeInterval(30))
    }

    @Test func latestDailyAlsoCachesItsReturnedDateForOfflineArchive() async throws {
        let transport = StubTransport([.response(200, [:], Data(#"{"schemaVersion":1,"report":{"date":"2026-09-08","generatedAt":"2026-09-08T00:00:00Z","windowStart":"2026-09-07T00:00:00Z","windowEnd":"2026-09-08T00:00:00Z","links":{"aihot":"https://aihot.news/daily/2026-09-08"},"lead":null,"sections":[],"flashes":[]}}"#.utf8))])
        let client = APIClient(transport: transport)
        _ = try await client.fetch(APIEndpoint<DailyResponse>.latestDaily())
        let report = try await client.fetch(APIEndpoint<DailyResponse>.daily(date: "2026-09-08"))
        #expect(report.source == .cache)
        #expect(await transport.requests.count == 1)
    }

    @Test func diskCacheSurvivesRestartAndDoesNotPersistCursors() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try ResponseCache(directory: directory)
        let endpoint = try APIEndpoint<ItemsResponse>.items()
        let now = Date()
        let body = Data(#"{"schemaVersion":1,"query":{"mode":"selected","category":null,"window":"24h","q":null,"by":"timeline","ordering":"timelineDesc"},"items":[],"page":{"count":0,"hasMore":true,"nextCursor":"opaque"}}"#.utf8)
        let entry = CachedResponse(body: body, etag: "old", validatedAt: now, freshUntil: now.addingTimeInterval(60),
                                   expiresAt: now.addingTimeInterval(600), cacheControl: "s-maxage=60", resolvedURL: endpoint.url)
        try await cache.insert(entry, for: endpoint.url, persist: true)
        #expect(try APIJSON.decoder().decode(ItemsResponse.self, from: await cache.value(for: endpoint.url, now: now)!.body).page.nextCursor == "opaque")
        let restored = try ResponseCache(directory: directory)
        let loaded = try #require(await restored.value(for: endpoint.url, now: now))
        #expect(loaded.etag == nil)
        #expect(loaded.freshUntil < now)
        #expect(try APIJSON.decoder().decode(ItemsResponse.self, from: loaded.body).page.nextCursor == nil)
        try await restored.clear()
        let cleared = try ResponseCache(directory: directory)
        #expect(await cleared.value(for: endpoint.url, now: now) == nil)
    }

    @Test func cacheIsBoundedAndQuerySpecific() async throws {
        let cache = try ResponseCache(capacity: 1)
        let now = Date()
        let a = try APIEndpoint<ItemsResponse>.items().url
        let b = try APIEndpoint<ItemsResponse>.items(ItemsQuery(mode: .all)).url
        let entry = CachedResponse(body: hotBody, etag: "a", validatedAt: now, freshUntil: now,
                                   expiresAt: now.addingTimeInterval(1), cacheControl: "", resolvedURL: a)
        try await cache.insert(entry, for: a, persist: false)
        #expect(await cache.value(for: b, now: now) == nil)
        var second = entry
        second.validatedAt = now.addingTimeInterval(0.1)
        try await cache.insert(second, for: b, persist: false)
        #expect(await cache.value(for: a, now: now) == nil)
        #expect(await cache.value(for: b, now: now.addingTimeInterval(2)) == nil)
    }
}

actor StubTransport: HTTPTransport {
    enum Step: Sendable {
        case response(Int, [String: String], Data)
        case failure(URLError.Code)
    }

    private var steps: [Step]
    private let delay: Duration
    private(set) var requests: [URLRequest] = []

    init(_ steps: [Step], delay: Duration = .zero) {
        self.steps = steps
        self.delay = delay
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !steps.isEmpty else { throw URLError(.badServerResponse) }
        let step = steps.removeFirst()
        if delay > .zero { try await Task.sleep(for: delay) }
        switch step {
        case .response(let status, let headers, let data):
            let headers = headers.merging(["Content-Type": "application/json"]) { current, _ in current }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            return HTTPResponse(data: data, response: response)
        case .failure(let code): throw URLError(code)
        }
    }
}

nonisolated final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()
    var now: Date { lock.withLock { value } }
    func advance(_ interval: TimeInterval) { lock.withLock { value.addTimeInterval(interval) } }
}
