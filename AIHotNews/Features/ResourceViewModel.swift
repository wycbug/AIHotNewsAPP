import Foundation
import Observation

@MainActor
@Observable
final class ResourceViewModel<Response: APIResponse> {
    private let repository: NewsRepository
    private(set) var value: Response?
    private(set) var isLoading = false
    private(set) var message: String?
    private(set) var retryAt: Date?
    private var resourceURL: URL?
    private var generation = UUID()
    private var activeLoads = 0
    private var latestFetchedAt: Date?

    init(repository: NewsRepository) {
        self.repository = repository
    }

    func load(_ endpoint: APIEndpoint<Response>, reload: Bool = false) async {
        guard !Task.isCancelled else { return }
        if resourceURL != endpoint.url {
            resourceURL = endpoint.url
            generation = UUID()
            activeLoads = 0
            value = nil
            latestFetchedAt = nil
            message = nil
        }
        let token = generation
        activeLoads += 1
        isLoading = true
        defer {
            if generation == token {
                activeLoads -= 1
                isLoading = activeLoads > 0
            }
        }
        do {
            if value == nil, let cached = await repository.cached(endpoint) {
                try Task.checkCancellation()
                guard generation == token else { return }
                if value == nil {
                    value = cached.value
                    latestFetchedAt = cached.fetchedAt
                    message = cacheMessage(cached)
                }
            }
            try Task.checkCancellation()
            guard generation == token else { return }
            guard retryAt.map({ $0 <= .now }) ?? true else {
                message = "请求暂不可重试，请等待服务器指定时间。"
                return
            }
            let result = try await repository.fetch(endpoint, policy: reload ? .reload : .standard)
            try Task.checkCancellation()
            guard generation == token else { return }
            if latestFetchedAt.map({ result.fetchedAt >= $0 }) ?? true {
                value = result.value
                latestFetchedAt = result.fetchedAt
                message = cacheMessage(result)
            } else if let error = result.staleError {
                message = error.localizedDescription
            }
            if let error = result.staleError {
                retryAt = retryDate(error)
            } else if retryAt.map({ $0 <= .now }) ?? true {
                retryAt = nil
            }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, generation == token else { return }
            if let apiError = error as? APIError {
                switch apiError {
                case .problem(let problem, _) where problem.status == 404:
                    value = nil
                case .http(let status, _, _) where status == 404:
                    value = nil
                default:
                    break
                }
            }
            message = error.localizedDescription
            retryAt = retryDate(error)
        }
    }

    func showError(_ error: Error) {
        message = error.localizedDescription
    }
}

@MainActor
func retryDate(_ error: Error) -> Date? {
    (error as? APIError)?.retryAt
}

@MainActor
func cacheMessage<Response: APIResponse>(_ result: APIResult<Response>) -> String {
    let date = result.fetchedAt.formatted(date: .abbreviated, time: .shortened)
    switch result.source {
    case .offline:
        return "离线，正在显示缓存（\(date)）。\(result.staleError?.localizedDescription ?? "")"
    case .cache:
        return "正在显示缓存 · \(date)"
    case .network, .revalidated:
        return "更新于 \(date)"
    }
}
