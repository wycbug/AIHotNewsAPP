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
    }

    private let fileURL: URL?
    private let capacity: Int
    private let byteLimit: Int
    private var records: [String: Record]

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
        return record.response
    }

    func insert(_ response: CachedResponse, for url: URL, persist: Bool) throws {
        records = records.filter { $0.value.response.expiresAt > response.validatedAt }
        guard response.body.count <= byteLimit else { return }
        records[url.absoluteString] = Record(response: response, persist: persist)
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

    func clear() throws {
        records.removeAll()
        try save()
    }

    private func save() throws {
        guard let fileURL else { return }
        var persisted = records.filter { $0.value.persist }
        for (key, record) in persisted where URL(string: key)?.path == "/api/v1/items" {
            guard var body = try JSONSerialization.jsonObject(with: record.response.body) as? [String: Any],
                  var page = body["page"] as? [String: Any] else { continue }
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
}
