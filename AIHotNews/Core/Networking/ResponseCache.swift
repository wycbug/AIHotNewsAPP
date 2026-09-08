import Foundation

nonisolated struct CachedResponse: Codable, Sendable {
    let body: Data
    var etag: String?
    var validatedAt: Date
    var freshUntil: Date
    var expiresAt: Date
    var cacheControl: String
    var resolvedURL: URL
}

actor ResponseCache {
    private struct Record: Codable, Sendable {
        var response: CachedResponse
        let persist: Bool
        var listRevision: UUID? = nil

        private enum CodingKeys: String, CodingKey {
            case response, persist
        }
    }

    private let fileURL: URL?
    private let capacity: Int
    private let byteLimit: Int
    private var records: [String: Record]
    private var generation = 0

    init(directory: URL? = nil, capacity: Int = 128, byteLimit: Int = 20 * 1_024 * 1_024) throws {
        self.capacity = max(1, capacity)
        self.byteLimit = max(1, byteLimit)
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            fileURL = directory.appendingPathComponent("responses-v1.json")
        } else {
            fileURL = nil
        }
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = saved.filter { $0.value.response.expiresAt > Date() }
        } else {
            records = [:]
        }
    }

    private init(memoryCapacity: Int) {
        fileURL = nil
        capacity = memoryCapacity
        byteLimit = 20 * 1_024 * 1_024
        records = [:]
    }

    nonisolated static func memory() -> ResponseCache {
        ResponseCache(memoryCapacity: 128)
    }

    func value(for url: URL, now: Date) -> CachedResponse? {
        guard let record = records[url.absoluteString] else { return nil }
        guard record.response.expiresAt > now else {
            records[url.absoluteString] = nil
            return nil
        }
        var response = record.response
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        if url.path == "/api/v1/items", !calendar.isDate(response.validatedAt, inSameDayAs: now),
           var body = try? APIJSON.decoder().decode(ItemsResponse.self, from: response.body) {
            body.page.nextCursor = nil
            if let data = try? APIJSON.encoder().encode(body) {
                response = CachedResponse(body: data, etag: nil, validatedAt: response.validatedAt,
                                          freshUntil: .distantPast, expiresAt: response.expiresAt,
                                          cacheControl: response.cacheControl, resolvedURL: response.resolvedURL)
            }
        }
        return response
    }

    func listRevision(for url: URL, now: Date) -> UUID? {
        guard let key = Self.firstPageKey(url.absoluteString), key != url.absoluteString,
              let firstPage = records[key], firstPage.response.expiresAt > now,
              Self.isSameShanghaiDay(firstPage.response.validatedAt, now) else { return nil }
        return firstPage.listRevision
    }

    func insert(_ response: CachedResponse, for url: URL, persist: Bool, listRevision: UUID? = nil) throws {
        records = records.filter { $0.value.response.expiresAt > response.validatedAt }
        guard response.body.count <= byteLimit else { return }
        let key = url.absoluteString
        var revision = listRevision
        if Self.firstPageKey(key) == key {
            let previous = records[key]
            let unchanged = previous.map {
                Self.isSameShanghaiDay($0.response.validatedAt, response.validatedAt)
                    && Self.isSameListBody($0.response.body, response.body)
            } == true
            revision = unchanged ? previous?.listRevision ?? UUID() : UUID()
        }
        records[key] = Record(response: response, persist: persist, listRevision: revision)
        var size = records.values.reduce(0) { $0 + $1.response.body.count }
        for (key, record) in records.sorted(by: { $0.value.response.validatedAt < $1.value.response.validatedAt }) {
            guard records.count > capacity || size > byteLimit else { break }
            records[key] = nil
            size -= record.response.body.count
        }
        try save()
    }

    func remove(_ url: URL) throws {
        records = records.filter { $0.key != url.absoluteString && $0.value.response.resolvedURL != url }
        try save()
    }

    func clear(generation: Int? = nil) throws {
        if let generation { self.generation = generation }
        records.removeAll()
        try save()
    }

    func store(_ response: CachedResponse, urls: Set<URL>, persist: Bool, generation: Int,
               listRevision: UUID? = nil) throws {
        guard generation == self.generation else { return }
        if HTTPHeaders.directives(response.cacheControl)["no-store"] != nil {
            try invalidate(urls, generation: generation)
        } else {
            for url in urls { try insert(response, for: url, persist: persist, listRevision: listRevision) }
        }
    }

    func invalidate(_ urls: Set<URL>, generation: Int) throws {
        guard generation == self.generation else { return }
        records = records.filter { key, record in
            !urls.contains(record.response.resolvedURL) && !urls.contains(where: { $0.absoluteString == key })
        }
        try save()
    }

    func cachedItem(id: String, now: Date) -> NewsItem? {
        for (key, record) in records.sorted(by: { $0.value.response.validatedAt > $1.value.response.validatedAt }) {
            guard record.response.expiresAt > now, URL(string: key)?.path == "/api/v1/items",
                  let response = try? APIJSON.decoder().decode(ItemsResponse.self, from: record.response.body) else { continue }
            if let item = response.items.first(where: { $0.id == id }) { return item }
        }
        return nil
    }

    private func save() throws {
        guard let fileURL else { return }
        var persisted = records.filter { $0.value.persist }
        for (key, record) in persisted where URL(string: key)?.path == "/api/v1/items" {
            guard var body = try JSONSerialization.jsonObject(with: record.response.body) as? [String: Any],
                  var page = body["page"] as? [String: Any] else { continue }
            // Revalidation preserves the list revision; only its current cursor chain belongs in the snapshot.
            var items = body["items"] as? [[String: Any]] ?? []
            var known = Set(items.compactMap { $0["id"] as? String })
            var visited = Set<String>()
            while let revision = record.listRevision,
                  let cursor = page["nextCursor"] as? String, !cursor.isEmpty,
                  visited.insert(cursor).inserted,
                  let pageKey = Self.pageKey(key, cursor: cursor),
                  let candidate = records[pageKey] {
                guard !candidate.persist, candidate.listRevision == revision,
                      Self.isSameShanghaiDay(candidate.response.validatedAt, record.response.validatedAt),
                      let object = try? JSONSerialization.jsonObject(with: candidate.response.body) as? [String: Any],
                      let moreItems = object["items"] as? [[String: Any]],
                      let nextPage = object["page"] as? [String: Any] else { break }
                items.append(contentsOf: moreItems.filter { item in
                    guard let id = item["id"] as? String else { return false }
                    return known.insert(id).inserted
                })
                page = nextPage
            }
            body["items"] = items
            page["count"] = items.count
            page["nextCursor"] = NSNull()
            body["page"] = page
            let response = record.response
            persisted[key] = Record(response: CachedResponse(
                body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
                etag: nil, validatedAt: response.validatedAt, freshUntil: .distantPast,
                expiresAt: response.expiresAt, cacheControl: response.cacheControl, resolvedURL: response.resolvedURL
            ), persist: true)
        }
        let data = try JSONEncoder().encode(persisted)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func firstPageKey(_ key: String) -> String? {
        guard var components = URLComponents(string: key), components.path == "/api/v1/items" else { return nil }
        components.queryItems = components.queryItems?.filter { $0.name != "cursor" }
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url?.absoluteString
    }

    private static func pageKey(_ firstPageKey: String, cursor: String) -> String? {
        guard var components = URLComponents(string: firstPageKey) else { return nil }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "cursor", value: cursor)]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url?.absoluteString
    }

    private static func isSameShanghaiDay(_ first: Date, _ second: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.isDate(first, inSameDayAs: second)
    }

    private static func isSameListBody(_ first: Data, _ second: Data) -> Bool {
        if first == second { return true }
        guard let first = try? APIJSON.decoder().decode(ItemsResponse.self, from: first),
              let second = try? APIJSON.decoder().decode(ItemsResponse.self, from: second) else { return false }
        return first.items == second.items && first.page.count == second.page.count
            && first.page.hasMore == second.page.hasMore && first.page.nextCursor == second.page.nextCursor
    }
}
