#if os(iOS)
import BackgroundTasks
import OSLog

@MainActor
enum BackgroundRefresh {
    static let identifier = "com.wycbug.AIHotNews.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        do {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Logger(subsystem: "com.wycbug.AIHotNews", category: "BackgroundRefresh")
                .debug("Background refresh unavailable: \(error.localizedDescription)")
        }
    }
}
#endif
