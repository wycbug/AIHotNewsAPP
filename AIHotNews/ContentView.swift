//
//  ContentView.swift
//  AIHotNews
//
//  Created by wycbug on 2026/9/8.
//

import SwiftUI

private enum AppSection: String, CaseIterable, Identifiable {
    case feed = "精选"
    case hot = "热点"
    case daily = "日报"
    case personal = "我的"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .feed: "newspaper"
        case .hot: "flame"
        case .daily: "calendar"
        case .personal: "person"
        }
    }
}

struct ContentView: View {
    let container: AppContainer
    @Environment(LibraryStore.self) private var library
    @State private var selection: AppSection? = .feed
    @State private var tabSelection: AppSection = .feed
    @State private var paths: [AppSection: [ReaderRoute]] = [:]
    @State private var detail: ReaderRoute?
    @State private var detailPath: [ReaderRoute] = []
    @State private var linkMessage: String?
    @State private var isSearchingFeed = false
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
#endif

    var body: some View {
        Group {
#if os(macOS)
            sidebar
                .frame(minWidth: 1000, minHeight: 600)
#else
            if sizeClass == .regular {
                sidebar
            } else {
                TabView(selection: $tabSelection) {
                    ForEach(AppSection.allCases) { section in
                        Tab(section.rawValue, systemImage: section.symbol, value: section) {
                            NavigationStack(path: path(for: section)) {
                                screen(section)
                                    .navigationDestination(for: ReaderRoute.self) { ReaderDestination(route: $0) }
                            }
                        }
                    }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
            }
#endif
        }
        .tint(.accentColor)
        .safariPresenter()
        .onOpenURL { url in Task { await open(url) } }
        .onChange(of: tabSelection) { _, section in
            if section != .feed { isSearchingFeed = false }
        }
        .alert("无法打开链接", isPresented: Binding(get: { linkMessage != nil }, set: { if !$0 { linkMessage = nil } })) {
            Button("好", role: .cancel) { linkMessage = nil }
        } message: { Text(linkMessage ?? "") }
    }

    private var sidebar: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: Binding(get: { selection }, set: { newSelection in
                selection = newSelection
                detail = nil
                detailPath = []
                if let newSelection, newSelection != .feed { isSearchingFeed = false }
            })) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationTitle("AI 圈速览")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            Group {
                screen(selection ?? .feed)
            }
            .environment(\.readerSelection, { route in
                detailPath = []
                detail = route
            })
            .id(selection)
            .navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 480)
        } detail: {
            NavigationStack(path: $detailPath) {
                Group {
                    if let detail {
                        ReaderDestination(route: detail)
                            .id(detail)
                    } else {
                        ContentUnavailableView("选择一条资讯", systemImage: "text.book.closed",
                                               description: Text("摘要在这里读，全文在原文打开"))
                            .readerBackground()
                    }
                }
                .navigationDestination(for: ReaderRoute.self) { ReaderDestination(route: $0) }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func path(for section: AppSection) -> Binding<[ReaderRoute]> {
        Binding(get: { paths[section] ?? [] }, set: { paths[section] = $0 })
    }

    private func navigate(_ section: AppSection, route: ReaderRoute? = nil) {
        selection = section
        tabSelection = section
        paths[section] = route.map { [$0] } ?? []
        detailPath = []
        detail = route
    }

    private func open(_ url: URL) async {
        guard let link = ReaderDeepLink(url: url) else {
            linkMessage = "此链接格式不受支持。"
            return
        }
        switch link {
        case .feed: navigate(.feed)
        case .hot: navigate(.hot)
        case .dailyHome: navigate(.daily)
        case .personal: navigate(.personal)
        case .search(let query):
            navigate(.feed)
            container.feed.searchText = query
            isSearchingFeed = true
        case .daily(let date): navigate(.daily, route: .daily(date))
        case .item(let id):
            if let article = library.article(id: id) {
                navigate(.feed, route: .article(article))
            } else if let item = await container.repository.cachedItem(id: id) {
                navigate(.feed, route: .article(ArticleSnapshot(item: item)))
            } else {
                linkMessage = "应用内没有这篇文章的摘要，请从原始分享链接打开网页。"
            }
        case .story(let id):
            let endpoint = try? APIEndpoint<StoryResponse>.story(publicID: id)
            if let bookmark = library.bookmark(forKey: LibraryKey.make(kind: "story", id: id)) {
                navigate(.hot, route: .bookmark(bookmark.key))
            } else if let topic = container.hotTopics.value?.items.first(where: { $0.links.story.flatMap { try? StoryLink.publicID(from: $0) } == id }) {
                navigate(.hot, route: .story(id, topic.links.story))
            } else if let endpoint, let cached = await container.repository.cached(endpoint) {
                navigate(.hot, route: .story(id, cached.value.story.links.aihot))
            } else {
                linkMessage = "本机尚未收到这个事件的公开引用，请从热点列表打开事件。"
            }
        }
    }

    @ViewBuilder
    private func screen(_ section: AppSection) -> some View {
        switch section {
        case .feed:
            FeedView(model: container.feed, isSearching: $isSearchingFeed)
        case .hot:
            HotTopicsView(model: container.hotTopics, repository: container.repository)
        case .daily:
            DailyHomeView(container: container)
        case .personal:
            AboutView(container: container)
        }
    }
}
