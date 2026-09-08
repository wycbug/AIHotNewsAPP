import Foundation
import OSLog

nonisolated enum APIUserAgent {
    static func make(version: String, platform: String, actorID: UUID? = nil) -> String {
        let base = "AIHotNews/\(version) (\(platform))"
        return actorID.map { base + " aihot-actor/" + $0.uuidString.lowercased() } ?? base
    }

    static var `default`: String {
        #if os(macOS)
        let platform = "macOS"
        #else
        let platform = "iOS"
        #endif
        return make(version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0", platform: platform)
    }
}

nonisolated enum APIJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date")
        }
        return decoder
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

nonisolated enum APIError: Error, LocalizedError, Sendable {
    case problem(APIProblem, retryAt: Date?)
    case http(status: Int, requestID: String?, retryAt: Date?)
    case transport(URLError.Code)
    case invalidResponse
    case decoding
    case cacheMiss
    case invalidRedirect
    case rateLimited(until: Date)

    var errorDescription: String? {
        switch self {
        case .problem(let problem, _): return problem.detail
        case .http(let status, _, _): return "服务暂时不可用（HTTP \(status)），请稍后重试。"
        case .transport: return "无法连接网络，请检查连接后重试。"
        case .invalidResponse: return "服务器返回了无效响应。"
        case .decoding: return "暂时无法读取服务器返回的数据。"
        case .cacheMiss: return "本机暂无缓存，请连接网络后重试。"
        case .invalidRedirect: return "事件跳转地址无效。"
        case .rateLimited: return "请求过于频繁，请等待后重试。"
        }
    }

    var retryAt: Date? {
        switch self {
        case .problem(_, let date), .http(_, _, let date): return date
        case .rateLimited(let date): return date
        default: return nil
        }
    }

    var permitsOfflineFallback: Bool {
        switch self {
        case .transport(let code): return code != .cancelled
        case .rateLimited: return true
        case .problem(let problem, _): return problem.status == 429 || problem.status == 503
        case .http(let status, _, _): return status == 429 || status >= 500
        default: return false
        }
    }
}

nonisolated enum FetchPolicy: Sendable { case standard, reload, cacheOnly }
nonisolated enum ResponseSource: Sendable { case network, cache, revalidated, offline }

nonisolated struct APIResult<Value: Sendable>: Sendable {
    let value: Value
    let source: ResponseSource
    let fetchedAt: Date
    let staleError: APIError?
    let resolvedURL: URL
}

nonisolated struct HTTPResponse: Sendable {
    let data: Data
    let response: HTTPURLResponse
}

nonisolated protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

nonisolated final class URLSessionTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, Sendable {
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request, delegate: self)
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return HTTPResponse(data: data, response: response)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

actor APIClient {
    private struct Flight {
        let task: Task<RawResult, Error>
        var waiters: Set<UUID>
    }

    private struct RawResult: Sendable {
        let entry: CachedResponse
        let source: ResponseSource
        let staleError: APIError?
    }

    private let cache: ResponseCache
    private let transport: any HTTPTransport
    private let userAgent: String
    private let now: @Sendable () -> Date
    private var flights: [URL: Flight] = [:]
    private var retryNotBefore: Date?
    private var cacheGeneration = 0
    private let logger = Logger(subsystem: "com.wycbug.AIHotNews", category: "Networking")

    init(cache: ResponseCache = .memory(), transport: any HTTPTransport = URLSessionTransport(),
         userAgent: String = APIUserAgent.default, now: @escaping @Sendable () -> Date = { Date() }) {
        self.cache = cache
        self.transport = transport
        self.userAgent = userAgent
        self.now = now
    }

    func cached<Response>(_ endpoint: APIEndpoint<Response>) async -> APIResult<Response>? {
        guard let entry = await cache.value(for: endpoint.url, now: now()),
              let value = try? APIJSON.decoder().decode(Response.self, from: entry.body) else { return nil }
        return APIResult(value: value, source: .cache, fetchedAt: entry.validatedAt,
                         staleError: nil, resolvedURL: entry.resolvedURL)
    }

    func fetch<Response>(_ endpoint: APIEndpoint<Response>, policy: FetchPolicy = .standard) async throws -> APIResult<Response> {
        try Task.checkCancellation()
        let entry = await cache.value(for: endpoint.url, now: now())
        if policy == .cacheOnly || (policy == .standard && entry.map { $0.freshUntil > now() } == true) {
            guard let entry else { throw APIError.cacheMiss }
            return try decode(RawResult(entry: entry, source: .cache, staleError: nil))
        }
        let id = UUID()
        let task: Task<RawResult, Error>
        if var flight = flights[endpoint.url] {
            flight.waiters.insert(id)
            flights[endpoint.url] = flight
            task = flight.task
        } else {
            let generation = cacheGeneration
            task = Task { try await self.load(endpoint, cached: entry, generation: generation) }
            flights[endpoint.url] = Flight(task: task, waiters: [id])
        }
        return try await withTaskCancellationHandler {
            defer { release(endpoint.url, waiter: id) }
            let result = try await task.value
            try Task.checkCancellation()
            return try decode(result)
        } onCancel: {
            Task { await self.release(endpoint.url, waiter: id) }
        }
    }

    func clearCache() async throws {
        cacheGeneration += 1
        try await cache.clear()
    }

    private func release(_ url: URL, waiter: UUID) {
        guard var flight = flights[url], flight.waiters.remove(waiter) != nil else { return }
        if flight.waiters.isEmpty {
            flight.task.cancel()
            flights[url] = nil
        } else {
            flights[url] = flight
        }
    }

    private func decode<Response: APIResponse>(_ result: RawResult) throws -> APIResult<Response> {
        do {
            let value = try APIJSON.decoder().decode(Response.self, from: result.entry.body)
            if value.schemaVersion != 1 {
                logger.warning("Unrecognized API schema version: \(value.schemaVersion)")
            }
            return APIResult(value: value, source: result.source, fetchedAt: result.entry.validatedAt,
                             staleError: result.staleError, resolvedURL: result.entry.resolvedURL)
        } catch {
            throw APIError.decoding
        }
    }

    private func load<Response>(_ endpoint: APIEndpoint<Response>, cached: CachedResponse?, generation: Int) async throws -> RawResult {
        do {
            if let until = retryNotBefore, until > now() { throw APIError.rateLimited(until: until) }
            return try await request(endpoint, cached: cached, generation: generation)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let failure: APIError
            if let error = error as? URLError {
                if error.code == .cancelled { throw CancellationError() }
                failure = .transport(error.code)
            } else {
                failure = error as? APIError ?? .invalidResponse
            }
            if failure.permitsOfflineFallback, let cached, cached.expiresAt > now() {
                return RawResult(entry: cached, source: .offline, staleError: failure)
            }
            throw failure
        }
    }

    private func request<Response>(_ endpoint: APIEndpoint<Response>, cached: CachedResponse?, generation: Int) async throws -> RawResult {
        var url = cached?.resolvedURL ?? endpoint.url
        var visited: Set<URL> = []
        var previous = cached
        while visited.count < 6 {
            try Task.checkCancellation()
            guard url.scheme == "https", url.host == "aihot.news", url.port == nil,
                  url.user == nil, url.password == nil, url.path.hasPrefix("/api/v1/"),
                  visited.insert(url).inserted else { throw APIError.invalidRedirect }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.httpMethod = "GET"
            request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(previous?.etag, forHTTPHeaderField: "If-None-Match")
            let result = try await transport.send(request)
            try Task.checkCancellation()
            let response = result.response
            let date = now()
            if response.statusCode == 308 {
                guard url.path.hasPrefix("/api/v1/stories/"),
                      let location = response.value(forHTTPHeaderField: "Location"),
                      let target = URL(string: location, relativeTo: url)?.absoluteURL,
                      target.scheme == "https", target.host == "aihot.news", target.port == nil,
                      target.user == nil, target.password == nil, target.query == nil, target.fragment == nil,
                      target.path.hasPrefix("/api/v1/stories/"),
                      let destination = try? APIEndpoint<StoryResponse>.story(publicID: target.lastPathComponent),
                      destination.url.path == target.path else { throw APIError.invalidRedirect }
                url = target
                previous = await cache.value(for: target, now: date)
                continue
            }
            if response.statusCode == 304 {
                guard var entry = previous else { throw APIError.cacheMiss }
                entry.validatedAt = date
                entry.etag = response.value(forHTTPHeaderField: "ETag") ?? entry.etag
                let control = response.value(forHTTPHeaderField: "Cache-Control") ?? entry.cacheControl
                entry.cacheControl = control
                entry.freshUntil = date.addingTimeInterval(HTTPHeaders.freshness(control, response: response, fallback: endpoint.defaultFreshness))
                entry.expiresAt = date.addingTimeInterval(endpoint.cacheRetention)
                entry.resolvedURL = url
                try await store(entry, for: endpoint, generation: generation)
                return RawResult(entry: entry, source: .revalidated, staleError: nil)
            }
            guard response.statusCode == 200 else {
                let retryAt: Date?
                if response.statusCode == 429 || response.statusCode == 503 {
                    retryAt = HTTPHeaders.retryDate(response.value(forHTTPHeaderField: "Retry-After"), now: date)
                        ?? date.addingTimeInterval(60)
                    retryNotBefore = max(retryNotBefore ?? date, retryAt!)
                } else { retryAt = nil }
                if response.statusCode == 404 {
                    do {
                        try await cache.remove(url)
                        if url != endpoint.url { try await cache.remove(endpoint.url) }
                    } catch {
                        logger.error("Unable to persist cache invalidation")
                    }
                }
                if let problem = try? APIJSON.decoder().decode(APIProblem.self, from: result.data) {
                    let normalized = APIProblem(type: problem.type, title: problem.title, status: response.statusCode,
                                                detail: problem.detail, code: problem.code,
                                                requestId: problem.requestId.isEmpty ? response.value(forHTTPHeaderField: "X-Request-Id") ?? "" : problem.requestId)
                    throw APIError.problem(normalized, retryAt: retryAt)
                }
                throw APIError.http(status: response.statusCode, requestID: response.value(forHTTPHeaderField: "X-Request-Id"), retryAt: retryAt)
            }
            guard let contentType = response.value(forHTTPHeaderField: "Content-Type"),
                  contentType.lowercased().split(separator: ";").first?.trimmingCharacters(in: .whitespaces) == "application/json"
            else { throw APIError.invalidResponse }
            guard (try? APIJSON.decoder().decode(Response.self, from: result.data)) != nil else { throw APIError.decoding }
            let control = response.value(forHTTPHeaderField: "Cache-Control") ?? ""
            let entry = CachedResponse(body: result.data, etag: response.value(forHTTPHeaderField: "ETag"),
                                       validatedAt: date,
                                       freshUntil: date.addingTimeInterval(HTTPHeaders.freshness(control, response: response, fallback: endpoint.defaultFreshness)),
                                       expiresAt: date.addingTimeInterval(endpoint.cacheRetention),
                                       cacheControl: control, resolvedURL: url)
            try await store(entry, for: endpoint, generation: generation)
            return RawResult(entry: entry, source: .network, staleError: nil)
        }
        throw APIError.invalidRedirect
    }

    private func store<Response>(_ entry: CachedResponse, for endpoint: APIEndpoint<Response>, generation: Int) async throws {
        guard generation == cacheGeneration else { return }
        do {
            if HTTPHeaders.directives(entry.cacheControl)["no-store"] != nil {
                try await cache.remove(entry.resolvedURL)
                if entry.resolvedURL != endpoint.url { try await cache.remove(endpoint.url) }
            } else {
                try await cache.insert(entry, for: endpoint.url, persist: endpoint.persistResponse)
                if entry.resolvedURL != endpoint.url {
                    try await cache.insert(entry, for: entry.resolvedURL, persist: endpoint.persistResponse)
                }
            }
        } catch {
            logger.error("Unable to persist response cache")
        }
    }
}

nonisolated enum HTTPHeaders {
    static func directives(_ value: String) -> [String: String] {
        value.split(separator: ",").reduce(into: [:]) { result, component in
            let pair = component.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            if let key = pair.first { result[key] = pair.count == 2 ? pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) : "" }
        }
    }

    static func freshness(_ value: String, response: HTTPURLResponse, fallback: TimeInterval) -> TimeInterval {
        let control = directives(value)
        if control["no-cache"] != nil || control["no-store"] != nil { return 0 }
        let ttl = control["s-maxage"].flatMap(Double.init) ?? control["max-age"].flatMap(Double.init) ?? fallback
        let age = response.value(forHTTPHeaderField: "Age").flatMap(Double.init) ?? 0
        return max(0, ttl - max(0, age))
    }

    static func retryDate(_ value: String?, now: Date) -> Date? {
        guard let value else { return nil }
        if let seconds = Double(value.trimmingCharacters(in: .whitespaces)), seconds.isFinite {
            return now.addingTimeInterval(max(0, seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(now, $0) }
    }
}
