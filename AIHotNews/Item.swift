//
//  Item.swift
//  AIHotNews
//
//  Created by wycbug on 2026/9/8.
//

import Foundation
import SwiftData

nonisolated enum LibraryKey {
    static func canonicalKind(_ kind: String) -> String {
        kind == "article" ? "item" : kind
    }

    static func make(kind: String, id: String) -> String {
        "\(canonicalKind(kind)):\(id)"
    }

    static func dailyID(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return formatter.string(from: date)
    }
}

@Model
final class Bookmark {
    @Attribute(.unique) var key: String
    var kind: String
    var publicID: String
    var title: String
    var savedAt: Date
    var payload: Data

    init(kind: String, publicID: String, title: String, payload: Data, savedAt: Date = .now) {
        self.key = LibraryKey.make(kind: kind, id: publicID)
        self.kind = LibraryKey.canonicalKind(kind)
        self.publicID = publicID
        self.title = title
        self.payload = payload
        self.savedAt = savedAt
    }
}

@Model
final class ReadRecord {
    @Attribute(.unique) var key: String
    var readAt: Date

    init(kind: String, publicID: String, readAt: Date = .now) {
        self.key = LibraryKey.make(kind: kind, id: publicID)
        self.readAt = readAt
    }
}
