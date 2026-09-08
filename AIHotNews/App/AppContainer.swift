import Foundation
import Observation
#if os(iOS)
import UIKit
#endif

@MainActor
@Observable
final class AppContainer {
    let repository: NewsRepository
    let cacheNotice: String?
    let feed: FeedViewModel
    let hotTopics: ResourceViewModel<HotTopicsResponse>
    let latestDaily: ResourceViewModel<DailyResponse>
    let dailies: ResourceViewModel<DailiesResponse>

    init(repository: NewsRepository, cacheNotice: String? = nil) {
        self.repository = repository
        self.cacheNotice = cacheNotice
        self.feed = FeedViewModel(repository: repository)
        self.feed.query.window = ItemsWindow(rawValue: UserDefaults.standard.string(forKey: "defaultWindow") ?? "24h") ?? .day
        self.feed.query.mode = ItemsMode(rawValue: UserDefaults.standard.string(forKey: "defaultMode") ?? "selected") ?? .selected
        self.feed.query.by = UserDefaults.standard.bool(forKey: "publishedOrder") ? .published : .timeline
        self.hotTopics = ResourceViewModel(repository: repository)
        self.latestDaily = ResourceViewModel(repository: repository)
        self.dailies = ResourceViewModel(repository: repository)
    }

    func preload() async {
        async let news: Void = feed.refreshIfIdle()
        async let hot: Void = hotTopics.load(.hotTopics())
        async let daily: Void = latestDaily.load(.latestDaily())
        _ = await (news, hot, daily)
    }

    func refreshInBackground() async {
        async let news = try? repository.fetch(APIEndpoint<ItemsResponse>.items())
        async let hot = try? repository.fetch(APIEndpoint<HotTopicsResponse>.hotTopics())
        async let daily = try? repository.fetch(APIEndpoint<DailyResponse>.latestDaily())
        _ = await (news, hot, daily)
    }

    static func live() -> AppContainer {
#if DEBUG
        if let directory = UITestRuntime.directory, let cache = try? ResponseCache(directory: directory) {
            return AppContainer(repository: NewsRepository(client: APIClient(cache: cache, transport: UITestTransport())))
        }
#endif
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
#if os(iOS)
        let platform = UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
#elseif os(macOS)
        let platform = "macOS"
#else
        let platform = "unknown"
#endif
        let userAgent = APIUserAgent.make(version: version, platform: platform)
        do {
            let directory = URL.cachesDirectory.appending(path: "APIResponses", directoryHint: .isDirectory)
            let cache = try ResponseCache(directory: directory)
            return AppContainer(repository: NewsRepository(client: APIClient(cache: cache, userAgent: userAgent)))
        } catch {
            return AppContainer(
                repository: NewsRepository(client: APIClient(userAgent: userAgent)),
                cacheNotice: "磁盘缓存不可用，本次仅在内存中缓存：\(error.localizedDescription)"
            )
        }
    }
}
