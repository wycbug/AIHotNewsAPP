#if DEBUG
import Foundation

nonisolated enum UITestRuntime {
    static var session: UUID? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--ui-test-session"), arguments.indices.contains(index + 1) else { return nil }
        return UUID(uuidString: arguments[index + 1])
    }

    static var directory: URL? {
        session.map { URL.applicationSupportDirectory.appendingPathComponent("UITests-\($0.uuidString)", isDirectory: true) }
    }
}

nonisolated struct UITestTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        if ProcessInfo.processInfo.arguments.contains("--ui-offline") { throw URLError(.notConnectedToInternet) }
        try await Task.sleep(for: .milliseconds(100))
        let url = request.url!
        let date = LibraryKey.dailyID(Date())
        let now = ISO8601DateFormatter().string(from: Date())
        let links: [String: Any] = ["aihot": "https://aihot.news/items/ui-article", "original": "https://example.com/article"]
        let source: [String: Any] = ["name": "研究团队"]
        let title = "开源模型发布全新推理能力"
        let summary = "研究团队公布模型评测与技术报告，覆盖复杂推理、代码生成与多语言任务。完整评测方法和限制可在原文核对。"
        let item: [String: Any] = ["id": "ui-article", "title": title, "originalTitle": "Open model research update",
                                   "summary": summary, "reason": "公开评测方法与模型权重，便于独立复现。",
                                   "source": source, "links": links, "publishedAt": now, "discoveredAt": now,
                                   "category": "ai-models", "score": 92, "selected": true]
        let storyLink = "https://aihot.virxact.com/story/ui-story"
        let report: [String: Any] = ["date": date, "generatedAt": now, "windowStart": now, "windowEnd": now,
                                     "links": ["aihot": "https://aihot.news/daily/\(date)"],
                                     "lead": ["title": "今日 AI 研究与产品进展", "leadParagraph": "从模型研究到产品发布，关注可以核对的行业进展。"],
                                     "sections": [["label": "模型进展", "items": [["title": title, "summary": summary, "source": source, "links": links]]]],
                                     "flashes": [["title": "开发者工具更新", "source": source, "links": links, "publishedAt": now]]]
        var body: [String: Any] = ["schemaVersion": 1]
        switch url.path {
        case "/api/v1/items":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String, _ fallback: String) -> String { query.first { $0.name == name }?.value ?? fallback }
            let search = query.first { $0.name == "q" }?.value
            let items = search.map { title.contains($0) ? [item] : [] } ?? [item]
            body["query"] = ["mode": value("mode", "selected"), "window": value("window", "24h"),
                             "by": value("by", "timeline"), "ordering": "timelineDesc", "q": search as Any? ?? NSNull(), "category": NSNull()]
            body["items"] = items
            body["page"] = ["count": items.count, "hasMore": false, "nextCursor": NSNull()]
        case "/api/v1/hot-topics":
            body["count"] = 1
            body["items"] = [["id": "ui-article", "rank": 1, "title": title, "source": source,
                              "links": links.merging(["story": storyLink]) { _, new in new },
                              "sourceCount": 3, "signalCount": 5, "sourceNames": ["研究团队", "技术媒体", "开发者社区"], "latestAt": now]]
        case "/api/v1/stories/ui-story":
            body["story"] = ["publicId": "ui-story", "title": "开源推理模型持续演进", "status": "active",
                             "sourceCount": 3, "reportCount": 1, "firstReportAt": now, "latestAt": now,
                             "latest": "研究团队发布技术报告，开发者开始独立复现。", "digest": summary, "digestUpdatedAt": now,
                             "links": ["aihot": storyLink], "storyline": [], "related": [],
                             "reports": [["id": "ui-report", "title": title, "summary": summary, "publishedAt": now,
                                          "source": ["name": "研究团队", "firstParty": true], "links": links]]]
        case "/api/v1/dailies":
            body["count"] = 1
            body["items"] = [["date": date, "generatedAt": now, "leadTitle": "今日 AI 研究与产品进展", "leadParagraph": "模型与产品的重要更新。", "links": ["aihot": "https://aihot.news/daily/\(date)"]]]
        default:
            guard url.path.hasPrefix("/api/v1/dailies/") else { throw URLError(.badURL) }
            body["report"] = report
        }
        return HTTPResponse(data: try JSONSerialization.data(withJSONObject: body), response: HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json", "Cache-Control": "s-maxage=0", "ETag": "ui-fixture"]
        )!)
    }
}
#endif
