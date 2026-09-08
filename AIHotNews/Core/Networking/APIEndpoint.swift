import Foundation

nonisolated enum ItemsMode: String, Codable, Sendable, CaseIterable {
    case selected
    case all
}

nonisolated enum ItemsWindow: String, Codable, Sendable, CaseIterable {
    case day = "24h"
    case week = "7d"
}

nonisolated enum ItemsOrder: String, Codable, Sendable, CaseIterable {
    case timeline
    case published
}

nonisolated struct ItemsQuery: Hashable, Sendable {
    var mode: ItemsMode
    var window: ItemsWindow
    var by: ItemsOrder
    var category: String?
    var q: String?
    var limit: Int

    init(
        mode: ItemsMode = .selected,
        window: ItemsWindow = .day,
        by: ItemsOrder = .timeline,
        category: String? = nil,
        q: String? = nil,
        limit: Int = 50
    ) {
        self.mode = mode
        self.window = window
        self.by = by
        self.category = category
        self.q = q
        self.limit = limit
    }
}

nonisolated enum SnapshotFields: String, Codable, Sendable, CaseIterable {
    case `default`
    case minimal
}

nonisolated enum RequestValidationError: Error, LocalizedError, Sendable, Equatable {
    case invalidSearchLength
    case invalidLimit(minimum: Int, maximum: Int)
    case invalidDate
    case invalidPublicID
    case emptyCursor
    case invalidStoryLink
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidSearchLength: return "搜索词去除首尾空白后须为 2–200 个 Unicode 码点。"
        case .invalidLimit(let minimum, let maximum): return "每页条数须为 \(minimum)–\(maximum)。"
        case .invalidDate: return "日期须为有效的 YYYY-MM-DD 日历日期。"
        case .invalidPublicID: return "事件 ID 须为不超过 128 个码点的安全路径片段。"
        case .emptyCursor: return "游标不能为空。"
        case .invalidStoryLink: return "接口返回的事件网页链接无效，无法提取事件 ID。"
        case .invalidURL: return "无法构建有效的 API 请求地址。"
        }
    }
}

nonisolated struct APIEndpoint<Response: APIResponse>: Sendable {
    let url: URL
    let defaultFreshness: TimeInterval
    let cacheRetention: TimeInterval
    let persistResponse: Bool

    func freshUntil(control: String, response: HTTPURLResponse, now: Date) -> Date {
        let ttl = HTTPHeaders.freshness(control, response: response, fallback: defaultFreshness)
        let deadline = now.addingTimeInterval(ttl)
        guard url.path == "/api/v1/dailies" || url.path == "/api/v1/dailies/latest" else { return deadline }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let publication = calendar.nextDate(after: now, matching: DateComponents(hour: 8), matchingPolicy: .nextTime)!
        return min(deadline, publication)
    }

    private init(
        url: URL,
        defaultFreshness: TimeInterval,
        cacheRetention: TimeInterval = 7 * 24 * 60 * 60,
        persistResponse: Bool = true
    ) {
        self.url = url
        self.defaultFreshness = defaultFreshness
        self.cacheRetention = cacheRetention
        self.persistResponse = persistResponse
    }

    private static func make(
        path: String,
        query: [URLQueryItem] = [],
        freshness: TimeInterval,
        retention: TimeInterval = 7 * 24 * 60 * 60,
        persist: Bool = true
    ) throws -> Self {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "aihot.news"
        components.path = "/api/v1/" + path
        if !query.isEmpty {
            components.queryItems = query
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else { throw RequestValidationError.invalidURL }
        return Self(url: url, defaultFreshness: freshness, cacheRetention: retention, persistResponse: persist)
    }
}

extension APIEndpoint where Response == ItemsResponse {
    nonisolated static func items(_ query: ItemsQuery = .init(), cursor: String? = nil) throws -> Self {
        try RequestValidation.limit(query.limit, maximum: 100)
        var parameters = [
            URLQueryItem(name: "mode", value: query.mode.rawValue),
            URLQueryItem(name: "window", value: query.window.rawValue),
            URLQueryItem(name: "by", value: query.by.rawValue),
            URLQueryItem(name: "limit", value: String(query.limit))
        ]
        if let category = query.category {
            parameters.append(URLQueryItem(name: "category", value: category))
        }
        if let q = query.q {
            let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (2...200).contains(trimmed.unicodeScalars.count) else {
                throw RequestValidationError.invalidSearchLength
            }
            parameters.append(URLQueryItem(name: "q", value: trimmed))
        }
        if let cursor {
            try RequestValidation.cursor(cursor)
            parameters.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return try make(path: "items", query: parameters, freshness: 60, persist: cursor == nil)
    }
}

extension APIEndpoint where Response == HotTopicsResponse {
    nonisolated static func hotTopics() -> Self {
        Self(url: URL(string: "https://aihot.news/api/v1/hot-topics")!, defaultFreshness: 300)
    }
}

extension APIEndpoint where Response == StoryResponse {
    nonisolated static func story(publicID: String) throws -> Self {
        try RequestValidation.publicID(publicID)
        return try make(path: "stories/" + publicID, freshness: 300)
    }
}

extension APIEndpoint where Response == DailiesResponse {
    nonisolated static func dailies(limit: Int = 30) throws -> Self {
        try RequestValidation.limit(limit, maximum: 180)
        return try make(path: "dailies", query: [URLQueryItem(name: "limit", value: String(limit))], freshness: 24 * 60 * 60)
    }
}

extension APIEndpoint where Response == DailyResponse {
    nonisolated static func latestDaily() -> Self {
        Self(url: URL(string: "https://aihot.news/api/v1/dailies/latest")!, defaultFreshness: 24 * 60 * 60)
    }

    nonisolated static func daily(date: String) throws -> Self {
        try RequestValidation.date(date)
        let lifetime = Date.distantFuture.timeIntervalSince1970
        return try make(path: "dailies/" + date, freshness: lifetime, retention: lifetime)
    }
}

extension APIEndpoint where Response == SnapshotResponse {
    nonisolated static func snapshot(fields: SnapshotFields = .default, limit: Int = 500, page: String? = nil) throws -> Self {
        try RequestValidation.limit(limit, maximum: 1000)
        var parameters = [
            URLQueryItem(name: "fields", value: fields.rawValue),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let page {
            try RequestValidation.cursor(page)
            parameters.append(URLQueryItem(name: "page", value: page))
        }
        return try make(path: "selected/snapshot", query: parameters, freshness: 60, retention: 60, persist: false)
    }
}

extension APIEndpoint where Response == ChangesResponse {
    nonisolated static func changes(cursor: String, limit: Int = 100) throws -> Self {
        try RequestValidation.cursor(cursor)
        try RequestValidation.limit(limit, maximum: 100)
        return try make(
            path: "selected/changes",
            query: [URLQueryItem(name: "cursor", value: cursor), URLQueryItem(name: "limit", value: String(limit))],
            freshness: 60,
            retention: 60,
            persist: false
        )
    }
}

nonisolated enum StoryLink {
    nonisolated static func publicID(from url: URL) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil,
              components.password == nil,
              let segment = components.percentEncodedPath.split(separator: "/").last,
              let publicID = String(segment).removingPercentEncoding else {
            throw RequestValidationError.invalidStoryLink
        }
        try RequestValidation.publicID(publicID)
        return publicID
    }
}

private nonisolated enum RequestValidation {
    nonisolated static func limit(_ value: Int, maximum: Int) throws {
        guard (1...maximum).contains(value) else {
            throw RequestValidationError.invalidLimit(minimum: 1, maximum: maximum)
        }
    }

    nonisolated static func cursor(_ value: String) throws {
        guard !value.isEmpty else { throw RequestValidationError.emptyCursor }
    }

    nonisolated static func publicID(_ value: String) throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        guard !value.isEmpty,
              value.unicodeScalars.count <= 128,
              value != ".", value != "..",
              value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw RequestValidationError.invalidPublicID
        }
    }

    nonisolated static func date(_ value: String) throws {
        let bytes = Array(value.utf8)
        guard bytes.count == 10,
              bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48...57).contains(byte)
              }),
              let year = Int(value.prefix(4)), year >= 1,
              let month = Int(value.dropFirst(5).prefix(2)),
              let day = Int(value.suffix(2)) else {
            throw RequestValidationError.invalidDate
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components else {
            throw RequestValidationError.invalidDate
        }
    }
}
