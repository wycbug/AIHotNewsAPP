import Foundation

@MainActor
final class NewsRepository {
    let client: APIClient
    private var generation = 0
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    init(client: APIClient, sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
        try await Task.sleep(for: .seconds($0))
    }) {
        self.client = client
        self.sleep = sleep
    }

    func fetch<Response: APIResponse>(
        _ endpoint: APIEndpoint<Response>,
        policy: FetchPolicy = .standard,
        retryLimit: Int = 0,
        onRetry: @MainActor (APIError) throws -> Void = { _ in }
    ) async throws -> APIResult<Response> {
        let token = generation
        var attempts = 0
        var policy = policy
        while true {
            try Task.checkCancellation()
            guard token == generation else { throw CancellationError() }
            let result: APIResult<Response>?
            let failure: APIError
            do {
                let fetched = try await client.fetch(endpoint, policy: policy)
                guard let error = fetched.staleError, error.retryAt != nil, attempts < retryLimit else { return fetched }
                result = fetched
                failure = error
            } catch let error as APIError {
                guard error.retryAt != nil, attempts < retryLimit else { throw error }
                result = nil
                failure = error
            }
            guard let deadline = failure.retryAt else {
                if let result { return result }
                throw failure
            }
            try onRetry(failure)
            attempts += 1
            try await sleep(max(0, deadline.timeIntervalSinceNow))
            try Task.checkCancellation()
            guard token == generation else { throw CancellationError() }
            policy = .reload
        }
    }

    func cached<Response: APIResponse>(_ endpoint: APIEndpoint<Response>) async -> APIResult<Response>? {
        await client.cached(endpoint)
    }

    func cachedItem(id: String) async -> NewsItem? {
        await client.cachedItem(id: id)
    }

    func clearCache() async throws {
        generation += 1
        try await client.clearCache()
    }
}
