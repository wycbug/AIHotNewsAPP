import Foundation
import Observation

@MainActor
@Observable
final class FeedViewModel {
    private let repository: NewsRepository
    @ObservationIgnored private let now: @Sendable () -> Date
    var query = ItemsQuery()
    var searchText = ""
    private(set) var items: [NewsItem] = []
    private(set) var isLoading = false
    private(set) var isPaging = false
    private(set) var message: String?
    private(set) var pageError: String?
    private(set) var nextCursor: String?
    private(set) var retryAt: Date?
    private var cursorDay: Date?
    private var generation = UUID()
    private var displayedQuery: ItemsQuery?
    @ObservationIgnored private var firstPage: APIResult<ItemsResponse>?
    private(set) var hasMore = false

    init(repository: NewsRepository, now: @escaping @Sendable () -> Date = { Date() }) {
        self.repository = repository
        self.now = now
        query.window = .day
        query.mode = .selected
        query.by = .timeline
        query.limit = 50
    }

    var request: ItemsQuery {
        var request = query
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        request.q = trimmed.isEmpty ? nil : trimmed
        return request
    }

    var searchValidation: String? {
        guard let text = request.q else { return nil }
        return (2...200).contains(text.unicodeScalars.count) ? nil : "搜索请输入 2–200 个字，范围仅限当前时间窗。"
    }

    func refreshIfIdle() async {
        guard !isLoading, !isPaging, request.q == nil else { return }
        await load()
    }

    func load(reload: Bool = false, debounce: Bool = false) async {
        guard !Task.isCancelled else { return }
        let request = request
        let token = UUID()
        generation = token
        isPaging = false
        guard searchValidation == nil else {
            isLoading = false
            return
        }
        guard retryAt.map({ $0 <= .now }) ?? true else {
            isLoading = false
            message = "请求暂不可重试，请等待服务器指定时间。"
            return
        }
        isLoading = true
        defer { if generation == token { isLoading = false } }
        do {
            if debounce { try await Task.sleep(for: .milliseconds(300)) }
            try Task.checkCancellation()
            guard generation == token, request == self.request else { return }
            if displayedQuery != request {
                items = []
                nextCursor = nil
                cursorDay = nil
                pageError = nil
                message = nil
                firstPage = nil
                hasMore = false
            } else if cursorDay != shanghaiDay() {
                nextCursor = nil
                cursorDay = nil
            }
            displayedQuery = request
            let endpoint = try APIEndpoint<ItemsResponse>.items(request)
            if items.isEmpty, let cached = await repository.cached(endpoint) {
                try Task.checkCancellation()
                guard generation == token, request == self.request else { return }
                items = cached.value.items
                hasMore = cached.value.page.hasMore
                message = cacheMessage(cached)
                acceptCursor(cached)
            }
            try Task.checkCancellation()
            guard generation == token, request == self.request else { return }
            let result = try await repository.fetch(endpoint, policy: reload ? .reload : .standard)
            try Task.checkCancellation()
            guard generation == token, request == self.request else { return }
            message = cacheMessage(result)
            retryAt = result.staleError.flatMap(retryDate)
            if result.source == .offline {
                if items.isEmpty { items = result.value.items }
            } else if preservesPagination(result) {
                firstPage = result
                return
            } else {
                var known: Set<String> = []
                items = result.value.items.filter { known.insert($0.id).inserted }
                firstPage = result
                hasMore = result.value.page.hasMore
                pageError = nil
            }
            acceptCursor(result)
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, generation == token, request == self.request else { return }
            message = displayError(error, hasContent: !items.isEmpty)
            retryAt = retryDate(error)
        }
    }

    func loadMore() async {
        guard !Task.isCancelled, !isLoading, !isPaging, let cursor = nextCursor,
              displayedQuery == request,
              retryAt.map({ $0 <= .now }) ?? true else { return }
        guard cursorDay == shanghaiDay() else {
            await load(reload: true)
            return
        }
        let token = generation
        let request = request
        isPaging = true
        pageError = nil
        defer { if generation == token { isPaging = false } }
        do {
            let endpoint = try APIEndpoint<ItemsResponse>.items(request, cursor: cursor)
            let result = try await repository.fetch(endpoint, policy: .reload)
            try Task.checkCancellation()
            guard generation == token, request == self.request else { return }
            if result.source == .offline {
                pageError = result.staleError?.localizedDescription ?? "加载下一页失败，请重试。"
                retryAt = result.staleError.flatMap(retryDate)
                acceptCursor(result)
                return
            }
            guard cursorDay == shanghaiDay() else {
                await load(reload: true)
                return
            }
            var known = Set(items.map(\.id))
            items.append(contentsOf: result.value.items.filter { known.insert($0.id).inserted })
            hasMore = result.value.page.hasMore
            message = cacheMessage(result)
            retryAt = result.staleError.flatMap(retryDate)
            acceptCursor(result)
            if nextCursor == cursor {
                nextCursor = nil
                firstPage = nil
                pageError = "分页未能继续，请刷新列表。"
            }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, generation == token, request == self.request else { return }
            if let apiError = error as? APIError,
               case .problem(let problem, _) = apiError,
               problem.code == "invalid_cursor" {
                nextCursor = nil
                cursorDay = nil
                firstPage = nil
                await load(reload: true)
            } else {
                pageError = error.localizedDescription
                retryAt = retryDate(error)
            }
        }
    }

    private func preservesPagination(_ result: APIResult<ItemsResponse>) -> Bool {
        guard result.source == .cache || result.source == .revalidated,
              let firstPage, !items.isEmpty,
              shanghaiDay(firstPage.fetchedAt) == shanghaiDay(),
              shanghaiDay(result.fetchedAt) == shanghaiDay() else { return false }
        // Another reader can update the shared cache before this page receives a 304.
        return firstPage.value.items == result.value.items
            && firstPage.value.page.count == result.value.page.count
            && firstPage.value.page.hasMore == result.value.page.hasMore
            && firstPage.value.page.nextCursor == result.value.page.nextCursor
    }

    private func acceptCursor(_ result: APIResult<ItemsResponse>) {
        let today = shanghaiDay()
        if result.source == .offline {
            if cursorDay != today {
                nextCursor = nil
                cursorDay = nil
            }
            return
        }
        guard shanghaiDay(result.fetchedAt) == today else {
            nextCursor = nil
            cursorDay = nil
            return
        }
        nextCursor = result.value.page.hasMore ? result.value.page.nextCursor : nil
        cursorDay = nextCursor == nil ? nil : today
    }

    private func shanghaiDay(_ date: Date? = nil) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.startOfDay(for: date ?? now())
    }
}
