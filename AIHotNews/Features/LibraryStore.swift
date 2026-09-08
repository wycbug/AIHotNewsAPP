import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class LibraryStore {
    private(set) var bookmarks: [Bookmark] = []
    private(set) var readKeys: Set<String> = []
    private var storyAliases: [String: String] = [:]
    var errorMessage: String?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let saveChanges: (ModelContext) throws -> Void

    convenience init(context: ModelContext) {
        self.init(context: context, saveChanges: { try $0.save() })
    }

    init(context: ModelContext, saveChanges: @escaping (ModelContext) throws -> Void) {
        self.context = context
        self.saveChanges = saveChanges
        context.autosaveEnabled = false
        reload()
    }

    func isSaved(kind: String, id: String) -> Bool {
        bookmarks.contains { $0.key == LibraryKey.make(kind: kind, id: id) }
    }

    func isRead(kind: String, id: String) -> Bool {
        readKeys.contains(LibraryKey.make(kind: kind, id: id))
    }

    func bookmark(forKey key: String) -> Bookmark? {
        if let bookmark = bookmarks.first(where: { $0.key == key }) { return bookmark }
        guard key.hasPrefix("story:") else { return nil }
        var id = String(key.dropFirst("story:".count))
        var visited: Set<String> = []
        while let canonical = storyAliases[id], visited.insert(id).inserted { id = canonical }
        return bookmarks.first { $0.key == LibraryKey.make(kind: "story", id: id) }
    }

    func toggleArticle(_ article: ArticleSnapshot) {
        toggle(kind: "item", id: article.id, title: article.title, value: article)
    }

    func toggleStory(_ story: Story) {
        toggle(kind: "story", id: story.publicId, title: story.title, value: story)
    }

    func toggleDaily(_ report: DailyReport) {
        let id = LibraryKey.dailyID(report.date)
        toggle(kind: "daily", id: id, title: report.lead?.title ?? "AI 日报 · \(id)", value: report)
    }

    func markRead(kind: String, id: String) {
        perform {
            let key = LibraryKey.make(kind: kind, id: id)
            let records = try context.fetch(FetchDescriptor<ReadRecord>(predicate: #Predicate { $0.key == key }))
            guard records.isEmpty else { return }
            context.insert(ReadRecord(kind: kind, publicID: id))
        }
    }

    func reconcileStory(previousID: String, story: Story) {
        guard previousID != story.publicId else { return }
        perform {
            let oldKey = LibraryKey.make(kind: "story", id: previousID)
            let old = try context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.key == oldKey }))
            if let previous = old.first {
                let newKey = LibraryKey.make(kind: "story", id: story.publicId)
                let current = try context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.key == newKey }))
                if current.isEmpty {
                    context.insert(Bookmark(kind: "story", publicID: story.publicId, title: story.title,
                                            payload: try JSONEncoder().encode(story), savedAt: previous.savedAt))
                }
                for bookmark in old { context.delete(bookmark) }
            }
            let reads = try context.fetch(FetchDescriptor<ReadRecord>(predicate: #Predicate { $0.key == oldKey }))
            if let read = reads.first {
                let newKey = LibraryKey.make(kind: "story", id: story.publicId)
                let current = try context.fetch(FetchDescriptor<ReadRecord>(predicate: #Predicate { $0.key == newKey }))
                if current.isEmpty {
                    context.insert(ReadRecord(kind: "story", publicID: story.publicId, readAt: read.readAt))
                }
                for record in reads { context.delete(record) }
            }
        }
        if errorMessage == nil { storyAliases[previousID] = story.publicId }
    }

    func clearRead() {
        perform {
            for record in try context.fetch(FetchDescriptor<ReadRecord>()) {
                context.delete(record)
            }
        }
    }

    func remove(_ bookmark: Bookmark) {
        let key = bookmark.key
        perform {
            for record in try context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.key == key })) {
                context.delete(record)
            }
        }
    }

    func article(id: String) -> ArticleSnapshot? {
        guard let bookmark = bookmarks.first(where: { $0.key == LibraryKey.make(kind: "item", id: id) }) else {
            return nil
        }
        return decode(ArticleSnapshot.self, from: bookmark)
    }

    func decode<Value: Decodable>(_ type: Value.Type, from bookmark: Bookmark) -> Value? {
        do {
            return try JSONDecoder().decode(type, from: bookmark.payload)
        } catch {
            errorMessage = "无法读取这份本机收藏：\(error.localizedDescription)"
            return nil
        }
    }

    func reload() {
        do {
            try fetchState()
            errorMessage = nil
        } catch {
            errorMessage = "无法读取本机资料库：\(error.localizedDescription)"
        }
    }

    private func toggle<Value: Encodable>(kind: String, id: String, title: String, value: Value) {
        perform {
            let key = LibraryKey.make(kind: kind, id: id)
            let existing = try context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.key == key }))
            if existing.isEmpty {
                let payload = try JSONEncoder().encode(value)
                context.insert(Bookmark(kind: kind, publicID: id, title: title, payload: payload))
            } else {
                for bookmark in existing { context.delete(bookmark) }
            }
        }
    }

    private func perform(_ changes: () throws -> Void) {
        do {
            try changes()
            if context.hasChanges { try saveChanges(context) }
            try fetchState()
            errorMessage = nil
        } catch {
            context.rollback()
            let failure = error.localizedDescription
            do {
                try fetchState()
                errorMessage = "本机资料未能保存，操作已撤销：\(failure)"
            } catch {
                errorMessage = "本机资料未能保存，操作已撤销：\(failure)。重新读取失败：\(error.localizedDescription)"
            }
        }
    }

    private func fetchState() throws {
        let saved = try context.fetch(FetchDescriptor<Bookmark>(sortBy: [SortDescriptor(\Bookmark.savedAt, order: .reverse)]))
        let reads = try context.fetch(FetchDescriptor<ReadRecord>())
        bookmarks = saved
        readKeys = Set(reads.map(\.key))
    }
}
