import Foundation
import Testing
@testable import AIHotNews

@MainActor
struct RepositoryTests {
    private let hotBody = Data(#"{"schemaVersion":1,"count":0,"items":[]}"#.utf8)

    @Test func retryWaitsForServerDeadlineAndReloads() async throws {
        let clock = TestClock()
        let transport = StubTransport([
            .response(200, ["ETag": "v1", "Cache-Control": "s-maxage=0"], hotBody),
            .response(429, ["Retry-After": "120"], problemBody(status: 429)),
            .response(200, [:], hotBody)
        ])
        let client = APIClient(transport: transport, now: { clock.now })
        let sleeps = SleepLog()
        var notified: [APIError] = []
        let repository = NewsRepository(client: client, sleep: { interval in
            await sleeps.record(interval)
            clock.advance(interval + 1)
        })
        _ = try await client.fetch(APIEndpoint<HotTopicsResponse>.hotTopics())

        let result = try await repository.fetch(.hotTopics(), retryLimit: 2) { notified.append($0) }
        #expect(result.source == .network)
        #expect(notified.count == 1)
        #expect(notified.first?.retryAt != nil)
        let slept = await sleeps.intervals
        #expect(slept.count == 1)
        #expect(slept[0] > 100 && slept[0] <= 120)
        let requests = await transport.requests
        #expect(requests.count == 3)
        #expect(requests.last?.value(forHTTPHeaderField: "If-None-Match") == "v1")
    }

    @Test func zeroRetryLimitSurfacesOfflineResultWithoutWaiting() async throws {
        let transport = StubTransport([
            .response(200, ["Cache-Control": "s-maxage=0"], hotBody),
            .response(429, ["Retry-After": "120"], problemBody(status: 429))
        ])
        let repository = NewsRepository(client: APIClient(transport: transport))
        _ = try await repository.fetch(.hotTopics())
        let result = try await repository.fetch(.hotTopics())
        #expect(result.source == .offline)
        #expect(result.staleError?.retryAt != nil)
        #expect(await transport.requests.count == 2)
    }

    @Test func zeroRetryLimitRethrowsProblemWithoutCache() async {
        let transport = StubTransport([.response(429, ["Retry-After": "120"], problemBody(status: 429))])
        let repository = NewsRepository(client: APIClient(transport: transport))
        await #expect(throws: APIError.self) { _ = try await repository.fetch(.hotTopics()) }
        #expect(await transport.requests.count == 1)
    }

    @Test func onRetryCanAbortTheRetryLoop() async {
        let transport = StubTransport([.response(429, ["Retry-After": "120"], problemBody(status: 429))])
        let repository = NewsRepository(client: APIClient(transport: transport), sleep: { _ in })
        await #expect(throws: CancellationError.self) {
            _ = try await repository.fetch(APIEndpoint<HotTopicsResponse>.hotTopics(), retryLimit: 1) { _ in
                throw CancellationError()
            }
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func cacheClearDuringRetryWaitCancelsFetch() async {
        let hook = RetryHook()
        let transport = StubTransport([.response(429, ["Retry-After": "120"], problemBody(status: 429))])
        let repository = NewsRepository(client: APIClient(transport: transport), sleep: { _ in
            try await hook.body?()
        })
        hook.body = { try await repository.clearCache() }
        await #expect(throws: CancellationError.self) {
            _ = try await repository.fetch(APIEndpoint<HotTopicsResponse>.hotTopics(), retryLimit: 1)
        }
    }

    @Test func fetchAfterClearCacheUsesFreshGeneration() async throws {
        let transport = StubTransport([.response(200, [:], hotBody), .response(200, [:], hotBody)])
        let repository = NewsRepository(client: APIClient(transport: transport))
        _ = try await repository.fetch(.hotTopics())
        try await repository.clearCache()
        let again = try await repository.fetch(.hotTopics())
        #expect(again.source == .network)
        #expect(await transport.requests.count == 2)
    }

    @Test func containerAppliesReadingPreferences() {
        let defaults = UserDefaults.standard
        let keys = ["defaultWindow", "defaultMode", "publishedOrder"]
        var saved: [String: Any] = [:]
        for key in keys { saved[key] = defaults.object(forKey: key) }
        defer {
            for key in keys {
                if let value = saved[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set("7d", forKey: "defaultWindow")
        defaults.set("all", forKey: "defaultMode")
        defaults.set(true, forKey: "publishedOrder")
        let repository = NewsRepository(client: APIClient(transport: StubTransport([])))
        let container = AppContainer(repository: repository)
        #expect(container.feed.query.window == .week)
        #expect(container.feed.query.mode == .all)
        #expect(container.feed.query.by == .published)

        defaults.set("bogus", forKey: "defaultWindow")
        defaults.set("bogus", forKey: "defaultMode")
        let fallback = AppContainer(repository: repository)
        #expect(fallback.feed.query.window == .day)
        #expect(fallback.feed.query.mode == .selected)
        #expect(fallback.cacheNotice == nil)
    }

    private func problemBody(status: Int, code: String = "rate_limited") -> Data {
        Data("{\"type\":\"about:blank\",\"title\":\"Error\",\"status\":\(status),\"detail\":\"Retry\",\"code\":\"\(code)\",\"requestId\":\"t\"}".utf8)
    }
}

private actor SleepLog {
    private(set) var intervals: [TimeInterval] = []
    func record(_ interval: TimeInterval) { intervals.append(interval) }
}

private final class RetryHook: @unchecked Sendable {
    var body: (() async throws -> Void)?
}
