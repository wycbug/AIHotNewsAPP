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
#if DEBUG
        if let directory = UITestRuntime.directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: directory.appendingPathComponent("library.store"))])
        }
#endif
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    var body: some Scene {
        WindowGroup {
            switch storage {
            case .success(let modelContainer):
                ReaderAppRoot(container: container, modelContainer: modelContainer)
            case .failure(let error):
                ContentUnavailableView {
                    Label("本机存储无法打开", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("为避免丢失本机数据，未重置存储。请重新启动应用。\n\(error.localizedDescription)")
                }
            }
        }
#if os(iOS)
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await container.refreshInBackground()
            await BackgroundRefresh.schedule()
        }
#endif
    }
}

private struct ReaderAppRoot: View {
    let container: AppContainer
    let modelContainer: ModelContainer
    @State private var library: LibraryStore
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var scenePhase

    init(container: AppContainer, modelContainer: ModelContainer) {
        self.container = container
        self.modelContainer = modelContainer
        _library = State(initialValue: LibraryStore(context: ModelContext(modelContainer)))
    }

    var body: some View {
        ContentView(container: container)
            .modelContainer(modelContainer)
            .environment(library)
            .environment(container)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
            .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                library.reload()
                await container.preload()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    await container.preload()
                }
            }
            .onChange(of: scenePhase) { _, phase in
#if os(iOS)
                if phase == .background { BackgroundRefresh.schedule() }
#endif
            }
    }
}
