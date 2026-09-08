import SwiftUI

enum ReaderRoute: Hashable {
    case article(ArticleSnapshot)
    case hotArticle(HotTopic)
    case story(String, URL?)
    case daily(String)
    case dailyEntry(DailyEntry)
    case archive
    case bookmarks(String)
    case bookmark(String)
    case settings
    case about
}

struct ReaderSelection: EnvironmentKey {
    static let defaultValue: (@MainActor (ReaderRoute) -> Void)? = nil
}

extension EnvironmentValues {
    var readerSelection: (@MainActor (ReaderRoute) -> Void)? {
        get { self[ReaderSelection.self] }
        set { self[ReaderSelection.self] = newValue }
    }
}

struct ReaderLink<Label: View>: View {
    let route: ReaderRoute
    @ViewBuilder let label: () -> Label
    @Environment(\.readerSelection) private var selection

    var body: some View {
        if let selection {
            Button { selection(route) } label: { label() }
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: route, label: label)
        }
    }
}

struct ReaderDestination: View {
    let route: ReaderRoute
    @Environment(AppContainer.self) private var container
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Group {
            switch route {
            case .article(let article): ArticleDetailView(article: article)
            case .hotArticle(let topic): HotArticleDetailView(topic: topic, repository: container.repository)
            case .story(let id, let link): StoryDetailView(publicID: id, link: link, repository: container.repository)
            case .daily(let date): DailyDetailView(date: date, repository: container.repository)
            case .dailyEntry(let entry): DailyDetailView(entry: entry, repository: container.repository)
            case .archive: DailyArchiveView(model: container.dailies, repository: container.repository)
            case .bookmarks(let kind): BookmarksView(repository: container.repository, kind: kind)
            case .bookmark(let key):
                if let bookmark = library.bookmark(forKey: key) {
                    SavedBookmarkDetail(bookmark: bookmark, repository: container.repository)
                } else {
                    ContentUnavailableView("已取消收藏", systemImage: "star")
                }
            case .settings: SettingsView(container: container)
            case .about: ProductAboutView()
            }
        }
        .environment(\.readerSelection, nil)
    }
}

nonisolated enum ReaderDeepLink: Equatable {
    case feed, hot, dailyHome, personal
    case item(String), story(String), daily(String)
    case search(String)

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "aihotnews", components.user == nil,
              components.password == nil, components.port == nil,
              components.fragment == nil else { return nil }
        if components.host == "search" {
            guard components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/",
                  let queryItems = components.queryItems, queryItems.count == 1,
                  queryItems[0].name == "q", let value = queryItems[0].value else { return nil }
            let query = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (try? APIEndpoint<ItemsResponse>.items(ItemsQuery(q: query))) != nil else { return nil }
            self = .search(query)
            return
        }
        guard components.query == nil else { return nil }
        let segments = components.percentEncodedPath.split(separator: "/").compactMap { String($0).removingPercentEncoding }
        switch (components.host, segments.count) {
        case ("feed", 0): self = .feed
        case ("hot", 0): self = .hot
        case ("daily", 0): self = .dailyHome
        case ("my", 0): self = .personal
        case ("item", 1), ("story", 1):
            guard (try? APIEndpoint<StoryResponse>.story(publicID: segments[0])) != nil else { return nil }
            self = components.host == "item" ? .item(segments[0]) : .story(segments[0])
        case ("daily", 1):
            guard (try? APIEndpoint<DailyResponse>.daily(date: segments[0])) != nil else { return nil }
            self = .daily(segments[0])
        default: return nil
        }
    }
}
