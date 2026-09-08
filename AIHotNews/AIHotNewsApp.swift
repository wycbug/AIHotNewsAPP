//
//  AIHotNewsApp.swift
//  AIHotNews
//
//  Created by wycbug on 2026/9/8.
//

import SwiftUI
import SwiftData

@main
struct AIHotNewsApp: App {
    @State private var container = AppContainer.live()
    private let storage: Result<ModelContainer, Error> = Result {
        let schema = Schema([Bookmark.self, ReadRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    var body: some Scene {
        WindowGroup {
            switch storage {
            case .success(let modelContainer):
                ContentView(container: container)
                    .modelContainer(modelContainer)
            case .failure(let error):
                ContentUnavailableView {
                    Label("本机存储无法打开", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("为避免丢失本机数据，未重置存储。请重新启动应用。\n\(error.localizedDescription)")
                }
            }
        }
    }
}
