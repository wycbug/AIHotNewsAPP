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
    @State private var selection: AppSection? = .feed
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
#endif

    var body: some View {
        Group {
#if os(macOS)
            sidebar
                .frame(minWidth: 850, minHeight: 600)
#else
            if sizeClass == .regular {
                sidebar
            } else {
                TabView {
                    ForEach(AppSection.allCases) { section in
                        NavigationStack {
                            screen(section)
                        }
                        .tabItem { Label(section.rawValue, systemImage: section.symbol) }
                    }
                }
            }
#endif
        }
        .tint(.accentColor)
        .safariPresenter()
        .task { await container.preload() }
    }

    private var sidebar: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationTitle("AI 圈速览")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            NavigationStack {
                screen(selection ?? .feed)
            }
            .id(selection)
        }
    }

    @ViewBuilder
    private func screen(_ section: AppSection) -> some View {
        switch section {
        case .feed:
            FeedView(model: container.feed)
        case .hot:
            HotTopicsView(model: container.hotTopics, repository: container.repository)
        case .daily:
            DailyHomeView(container: container)
        case .personal:
            AboutView(container: container)
        }
    }
}
