import Foundation

nonisolated protocol APIResponse: Codable, Sendable {
    var schemaVersion: Int { get }
}

nonisolated struct APIProblem: Codable, Sendable {
    let type: String
    let title: String
    let status: Int
    let detail: String
    let code: String
    let requestId: String
}

nonisolated struct Attribution: Codable, Sendable, Hashable {
    let name: String
    let url: URL
}

nonisolated struct NewsSource: Codable, Sendable, Hashable {
    let name: String
}

nonisolated struct NewsLinks: Codable, Sendable, Hashable {
    let aihot: URL
    let original: URL
}

nonisolated struct AihotLinks: Codable, Sendable, Hashable {
    let aihot: URL
}

nonisolated struct NewsItem: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let originalTitle: String?
    let summary: String?
    let source: NewsSource
    let links: NewsLinks
    let publishedAt: Date?
    let discoveredAt: Date
    let category: String?
    let score: Double?
    let selected: Bool
    let reason: String?
    let attribution: Attribution?
}

nonisolated struct NewsItemMinimal: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let source: NewsSource
    let links: AihotLinks
    let publishedAt: Date?
    let discoveredAt: Date
    let category: String?
    let score: Double?
    let selected: Bool
}

nonisolated struct Page: Codable, Sendable {
    let count: Int
    let hasMore: Bool
    var nextCursor: String?
}

nonisolated struct ItemsResponse: APIResponse {
    let schemaVersion: Int
    let query: ItemsQueryEcho
    let items: [NewsItem]
    var page: Page
}

nonisolated struct ItemsQueryEcho: Codable, Sendable {
    let mode: String
    let category: String?
    let window: String
    let q: String?
    let by: String
    let ordering: String
}

nonisolated struct HotTopicLinks: Codable, Sendable, Hashable {
    let aihot: URL
    let original: URL
    let story: URL?
}

nonisolated struct HotTopic: Codable, Sendable, Identifiable, Hashable {
    let rank: Int
    let id: String
    let title: String
    let source: NewsSource
    let links: HotTopicLinks
    let sourceCount: Int
    let signalCount: Int
    let sourceNames: [String]
    let latestAt: Date
}

nonisolated struct HotTopicsResponse: APIResponse {
    let schemaVersion: Int
    let count: Int
    let items: [HotTopic]
}

nonisolated struct StoryReportSource: Codable, Sendable, Hashable {
    let name: String
    let firstParty: Bool
}

nonisolated struct StoryReportLinks: Codable, Sendable, Hashable {
    let aihot: URL
    let original: URL?
}

nonisolated struct StoryReport: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String?
    let source: StoryReportSource
    let publishedAt: Date
    let links: StoryReportLinks
}

nonisolated struct StoryNeighborLinks: Codable, Sendable, Hashable {
    let aihot: URL
    let api: URL
}

nonisolated struct StoryNeighbor: Codable, Sendable, Identifiable, Hashable {
    let publicId: String
    let title: String
    let relation: String
    let links: StoryNeighborLinks
    var id: String { publicId }
}

nonisolated struct Story: Codable, Sendable, Identifiable, Hashable {
    let publicId: String
    let title: String
    let status: String
    let sourceCount: Int
    let reportCount: Int
    let firstReportAt: Date
    let latestAt: Date
    let latest: String
    let digest: String?
    let digestUpdatedAt: Date?
    let links: AihotLinks
    let reports: [StoryReport]
    let storyline: [StoryNeighbor]
    let related: [StoryNeighbor]
    var id: String { publicId }
}

nonisolated struct StoryResponse: APIResponse {
    let schemaVersion: Int
    let story: Story
}

nonisolated struct APICalendarDate: Codable, Sendable, Hashable {
    var wrappedValue: Date

    init(wrappedValue: Date) {
        self.wrappedValue = wrappedValue
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let formatter = Self.formatter()
        guard value.utf8.count == 10,
              let date = formatter.date(from: value),
              formatter.string(from: date) == value else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid calendar date")
        }
        wrappedValue = date
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.formatter().string(from: wrappedValue))
    }

    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return formatter
    }
}

nonisolated struct DailyEntry: Codable, Sendable, Identifiable, Hashable {
    let date: Date
    let generatedAt: Date
    let leadTitle: String?
    let leadParagraph: String?
    let links: AihotLinks
    let attribution: Attribution?
    var id: Date { date }
}

extension DailyEntry {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(APICalendarDate.self, forKey: .date).wrappedValue
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        leadTitle = try container.decodeIfPresent(String.self, forKey: .leadTitle)
        leadParagraph = try container.decodeIfPresent(String.self, forKey: .leadParagraph)
        links = try container.decode(AihotLinks.self, forKey: .links)
        attribution = try container.decodeIfPresent(Attribution.self, forKey: .attribution)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(APICalendarDate(wrappedValue: date), forKey: .date)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(leadTitle, forKey: .leadTitle)
        try container.encode(leadParagraph, forKey: .leadParagraph)
        try container.encode(links, forKey: .links)
        try container.encodeIfPresent(attribution, forKey: .attribution)
    }

    private nonisolated enum CodingKeys: String, CodingKey {
        case date, generatedAt, leadTitle, leadParagraph, links, attribution
    }
}

nonisolated struct DailiesResponse: APIResponse {
    let schemaVersion: Int
    let count: Int
    let items: [DailyEntry]
}

nonisolated struct DailyContentLinks: Codable, Sendable, Hashable {
    let aihot: URL?
    let original: URL
}

nonisolated struct DailyLead: Codable, Sendable, Hashable {
    let title: String
    let leadParagraph: String
}

nonisolated struct DailySectionItem: Codable, Sendable, Hashable {
    let title: String
    let summary: String
    let source: NewsSource
    let links: DailyContentLinks
    let attribution: Attribution?
}

nonisolated struct DailySection: Codable, Sendable, Hashable {
    let label: String
    let items: [DailySectionItem]
}

nonisolated struct DailyFlash: Codable, Sendable, Hashable {
    let title: String
    let source: NewsSource
    let links: DailyContentLinks
    let publishedAt: Date
    let attribution: Attribution?
}

nonisolated struct DailyReport: Codable, Sendable, Identifiable, Hashable {
    let date: Date
    let generatedAt: Date
    let windowStart: Date
    let windowEnd: Date
    let links: AihotLinks
    let attribution: Attribution?
    let lead: DailyLead?
    let sections: [DailySection]
    let flashes: [DailyFlash]
    var id: Date { date }
}

extension DailyReport {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(APICalendarDate.self, forKey: .date).wrappedValue
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        windowStart = try container.decode(Date.self, forKey: .windowStart)
        windowEnd = try container.decode(Date.self, forKey: .windowEnd)
        links = try container.decode(AihotLinks.self, forKey: .links)
        attribution = try container.decodeIfPresent(Attribution.self, forKey: .attribution)
        lead = try container.decodeIfPresent(DailyLead.self, forKey: .lead)
        sections = try container.decode([DailySection].self, forKey: .sections)
        flashes = try container.decode([DailyFlash].self, forKey: .flashes)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(APICalendarDate(wrappedValue: date), forKey: .date)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(windowStart, forKey: .windowStart)
        try container.encode(windowEnd, forKey: .windowEnd)
        try container.encode(links, forKey: .links)
        try container.encodeIfPresent(attribution, forKey: .attribution)
        try container.encode(lead, forKey: .lead)
        try container.encode(sections, forKey: .sections)
        try container.encode(flashes, forKey: .flashes)
    }

    private nonisolated enum CodingKeys: String, CodingKey {
        case date, generatedAt, windowStart, windowEnd, links, attribution, lead, sections, flashes
    }
}

nonisolated struct DailyResponse: APIResponse {
    let schemaVersion: Int
    let report: DailyReport
}

nonisolated enum JSONValue: Codable, Sendable, Hashable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

nonisolated enum SnapshotItem: Codable, Sendable, Hashable {
    case full(NewsItem)
    case minimal(NewsItemMinimal)
    case unknown(JSONValue)

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let links = try container.nestedContainer(keyedBy: LinkKeys.self, forKey: .links)
        if links.contains(.original) {
            self = .full(try NewsItem(from: decoder))
        } else {
            self = .minimal(try NewsItemMinimal(from: decoder))
        }
    }

    init(from decoder: Decoder, fields: String) throws {
        switch fields {
        case "default": self = .full(try NewsItem(from: decoder))
        case "minimal": self = .minimal(try NewsItemMinimal(from: decoder))
        default: self = .unknown(try JSONValue(from: decoder))
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        switch self {
        case .full(let item): try item.encode(to: encoder)
        case .minimal(let item): try item.encode(to: encoder)
        case .unknown(let value): try value.encode(to: encoder)
        }
    }

    private nonisolated enum CodingKeys: String, CodingKey { case links }
    private nonisolated enum LinkKeys: String, CodingKey { case original }
}

nonisolated struct SnapshotResponse: APIResponse {
    let schemaVersion: Int
    let asOf: Date
    let fields: String
    let cursor: String
    let count: Int
    let hasMore: Bool
    let nextPage: String?
    let items: [SnapshotItem]

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        asOf = try container.decode(Date.self, forKey: .asOf)
        fields = try container.decode(String.self, forKey: .fields)
        cursor = try container.decode(String.self, forKey: .cursor)
        count = try container.decode(Int.self, forKey: .count)
        hasMore = try container.decode(Bool.self, forKey: .hasMore)
        nextPage = try container.decodeIfPresent(String.self, forKey: .nextPage)
        var values = try container.nestedUnkeyedContainer(forKey: .items)
        var decoded: [SnapshotItem] = []
        while !values.isAtEnd {
            decoded.append(try SnapshotItem(from: values.superDecoder(), fields: fields))
        }
        items = decoded
    }

    private nonisolated enum CodingKeys: String, CodingKey {
        case schemaVersion, asOf, fields, cursor, count, hasMore, nextPage, items
    }
}

nonisolated enum SelectedChange: Codable, Sendable, Hashable {
    case upsert(changedAt: Date, item: SnapshotItem)
    case remove(changedAt: Date, id: String)
    case unknown(op: String, payload: JSONValue)

    var op: String {
        switch self {
        case .upsert: return "upsert"
        case .remove: return "remove"
        case .unknown(let op, _): return op
        }
    }

    nonisolated init(from decoder: Decoder) throws {
        try self.init(from: decoder, fields: nil)
    }

    init(from decoder: Decoder, fields: String?) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let op = try container.decode(String.self, forKey: .op)
        switch op {
        case "upsert":
            let changedAt = try container.decode(Date.self, forKey: .changedAt)
            let itemDecoder = try container.superDecoder(forKey: .item)
            let item: SnapshotItem
            if let fields {
                item = try SnapshotItem(from: itemDecoder, fields: fields)
            } else {
                item = try SnapshotItem(from: itemDecoder)
            }
            self = .upsert(changedAt: changedAt, item: item)
        case "remove":
            self = .remove(
                changedAt: try container.decode(Date.self, forKey: .changedAt),
                id: try container.decode(String.self, forKey: .id)
            )
        default:
            self = .unknown(op: op, payload: try JSONValue(from: decoder))
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        if case .unknown(_, let payload) = self {
            try payload.encode(to: encoder)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(op, forKey: .op)
        switch self {
        case .upsert(let changedAt, let item):
            try container.encode(changedAt, forKey: .changedAt)
            try container.encode(item, forKey: .item)
        case .remove(let changedAt, let id):
            try container.encode(changedAt, forKey: .changedAt)
            try container.encode(id, forKey: .id)
        case .unknown: break
        }
    }

    private nonisolated enum CodingKeys: String, CodingKey { case op, changedAt, item, id }
}

nonisolated struct ChangesResponse: APIResponse {
    let schemaVersion: Int
    let fields: String
    let cursor: String
    let count: Int
    let hasMore: Bool
    let changes: [SelectedChange]

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        fields = try container.decode(String.self, forKey: .fields)
        cursor = try container.decode(String.self, forKey: .cursor)
        count = try container.decode(Int.self, forKey: .count)
        hasMore = try container.decode(Bool.self, forKey: .hasMore)
        var values = try container.nestedUnkeyedContainer(forKey: .changes)
        var decoded: [SelectedChange] = []
        while !values.isAtEnd {
            decoded.append(try SelectedChange(from: values.superDecoder(), fields: fields))
        }
        changes = decoded
    }

    private nonisolated enum CodingKeys: String, CodingKey {
        case schemaVersion, fields, cursor, count, hasMore, changes
    }
}
