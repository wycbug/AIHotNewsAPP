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
    private(set) var failure: APIError?
    @ObservationIgnored private var resourceURL: URL?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activeLoads = 0
    @ObservationIgnored private var latestFetchedAt: Date?
    @ObservationIgnored private var initialValue: Response?
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    init(repository: NewsRepository, initialValue: Response? = nil) {
        self.repository = repository
        self.initialValue = initialValue
        value = initialValue
    }

    // Swift 6.3's optimizer crashes on the implicit isolated generic destructor.
    nonisolated deinit {}

    func load(_ endpoint: APIEndpoint<Response>, reload: Bool = false) async {
        guard !Task.isCancelled else { return }
        if resourceURL != endpoint.url {
            for task in tasks.values { task.cancel() }
            tasks.removeAll()
            if resourceURL != nil {
                value = nil
                initialValue = nil
            }
            resourceURL = endpoint.url
            generation = UUID()
            activeLoads = 0
            latestFetchedAt = nil
            message = nil
            failure = nil
        }
        let id = UUID()
        let token = generation
        let task = Task { await self.performLoad(endpoint, reload: reload, token: token) }
        tasks[id] = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        tasks[id] = nil
    }

    private func performLoad(_ endpoint: APIEndpoint<Response>, reload: Bool, token: UUID) async {
        guard !Task.isCancelled, generation == token else { return }
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
            let result = try await repository.fetch(endpoint, policy: reload ? .reload : .standard) { error in
                guard self.generation == token else { throw CancellationError() }
                self.retryAt = error.retryAt
                self.message = retryMessage(error)
            }
            try Task.checkCancellation()
            guard generation == token else { return }
            if latestFetchedAt.map({ result.fetchedAt >= $0 }) ?? true {
                failure = result.staleError
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
            failure = error as? APIError
            if let apiError = error as? APIError {
                switch apiError {
                case .problem(let problem, _) where problem.status == 404:
                    value = initialValue
                    latestFetchedAt = nil
                case .http(let status, _, _) where status == 404:
                    value = initialValue
                    latestFetchedAt = nil
                default:
                    break
                }
            }
            message = displayError(error, hasContent: value != nil)
            retryAt = retryDate(error)
        }
    }

    func showError(_ error: Error) {
        message = error.localizedDescription
    }
}

@MainActor
func retryMessage(_ error: APIError) -> String {
    let seconds = Int(ceil(max(0, error.retryAt?.timeIntervalSinceNow ?? 0)))
    return "服务暂不可用，\(seconds) 秒后自动重试。\(error.localizedDescription)"
}

@MainActor
func retryDate(_ error: Error) -> Date? {
    (error as? APIError)?.retryAt
}

@MainActor
func displayError(_ error: Error, hasContent: Bool) -> String {
    let message = error.localizedDescription
    if let api = error as? APIError {
        if case .transport = api, hasContent { return "离线，正在显示缓存。\(message)" }
        if let requestID = api.requestID { return "\(message)\n请求编号：\(requestID)" }
    }
    return message
}

@MainActor
func cacheMessage<Response: APIResponse>(_ result: APIResult<Response>) -> String {
    let date = result.fetchedAt.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day().hour().minute())
    switch result.source {
    case .offline:
        return "离线，正在显示缓存（\(date)）。\(result.staleError?.localizedDescription ?? "")"
    case .cache:
        return "正在显示缓存 · \(date)"
    case .network, .revalidated:
        return "更新于 \(date)"
    }
}
