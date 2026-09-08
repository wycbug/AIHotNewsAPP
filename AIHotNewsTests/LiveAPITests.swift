import Foundation
import Testing
@testable import AIHotNews

struct LiveAPITests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AIHOT_LIVE_API_TESTS"] == "1"))
    func publicReadEndpoints() async throws {
        let client = APIClient()
        let items = try await client.fetch(.items(ItemsQuery(limit: 1)))
        #expect(items.value.schemaVersion >= 1)
        let hot = try await client.fetch(.hotTopics())
        #expect(hot.value.count == hot.value.items.count)
        if let link = hot.value.items.compactMap(\.links.story).first {
            let story = try await client.fetch(.story(publicID: StoryLink.publicID(from: link)))
            #expect(!story.value.story.publicId.isEmpty)
        }
        let index = try await client.fetch(.dailies(limit: 1))
        if let entry = index.value.items.first {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.dateFormat = "yyyy-MM-dd"
            let report = try await client.fetch(.daily(date: formatter.string(from: entry.date)))
            #expect(report.value.report.date == entry.date)
            let latest = try await client.fetch(.latestDaily())
            #expect(latest.value.report.date >= entry.date)
        }
    }
}
