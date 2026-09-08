import Foundation

@MainActor
final class NewsRepository {
    let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetch<Response: APIResponse>(
        _ endpoint: APIEndpoint<Response>,
        policy: FetchPolicy = .standard
    ) async throws -> APIResult<Response> {
        try await client.fetch(endpoint, policy: policy)
    }

    func cached<Response: APIResponse>(_ endpoint: APIEndpoint<Response>) async -> APIResult<Response>? {
        await client.cached(endpoint)
    }

    func clearCache() async throws {
        try await client.clearCache()
    }
}
