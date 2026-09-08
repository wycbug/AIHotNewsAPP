//
//  Item.swift
//  AIHotNews
//
//  Created by wycbug on 2026/9/8.
//

import Foundation
import SwiftData

@Model
final class Bookmark {
    @Attribute(.unique) var key: String
    var kind: String
    var publicID: String
    var title: String
    var savedAt: Date
    var payload: Data

    init(kind: String, publicID: String, title: String, payload: Data, savedAt: Date = .now) {
        self.key = "\(kind):\(publicID)"
        self.kind = kind
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
        self.key = "\(kind):\(publicID)"
        self.readAt = readAt
    }
}
