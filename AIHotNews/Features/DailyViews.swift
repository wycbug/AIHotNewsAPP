import SwiftUI

struct DailyHomeView: View {
    let container: AppContainer
    @Environment(LibraryStore.self) private var library

    var body: some View {
        List {
            LoadStatusView(isLoading: container.latestDaily.isLoading, message: container.latestDaily.message,
                           retryAt: container.latestDaily.retryAt) {
                await container.latestDaily.load(.latestDaily(), reload: true)
            }
            if let report = container.latestDaily.value?.report {
                DailyReportSections(report: report, isLatest: true)
            } else if container.latestDaily.isLoading {
                ReadingSkeleton()
            } else {
                ContentUnavailableView(container.latestDaily.failure?.isNotFound == true ? "今日日报尚未发布" : "暂时无法获取日报",
                                       systemImage: "calendar", description: Text("日报于上海时间 08:00 出刊，你仍可阅读往期日报。"))
            }
            Section {
                ReaderLink(route: .archive) {
                    Label("往期日报", systemImage: "calendar.badge.clock")
                        .font(.headline).padding(.vertical, 10)
                }
            } footer: {
                Text("最新一期日期及统计区间以接口为准。")
            }
        }
        .readerBackground()
        .navigationTitle("日报")
        .toolbar {
            ReaderLink(route: .archive) {
                Label("往期日报", systemImage: "calendar.badge.clock")
            }
            if let report = container.latestDaily.value?.report {
                DailySaveButton(report: report)
            }
        }
        .task { await container.latestDaily.load(.latestDaily()) }
        .onChange(of: container.latestDaily.value?.report.date, initial: true) { _, date in
            if let date { library.markRead(kind: "daily", id: shanghaiDateString(date)) }
        }
        .refreshable { await container.latestDaily.load(.latestDaily(), reload: true) }
    }
}

struct DailyArchiveView: View {
    @Bindable var model: ResourceViewModel<DailiesResponse>
    let repository: NewsRepository
    @State private var limit = 30

    var body: some View {
        List {
            LoadStatusView(isLoading: model.isLoading, message: model.message, retryAt: model.retryAt) {
                await load(reload: true)
            }
            if let response = model.value {
                if response.items.isEmpty {
                    ContentUnavailableView("暂无往期日报", systemImage: "calendar")
                }
                ForEach(response.items) { entry in
                    ReaderLink(route: .dailyEntry(entry)) {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 4) {
                                Text(String(shanghaiDateString(entry.date).dropFirst(5).prefix(2)) + "月")
                                    .font(.caption.weight(.medium))
                                Text(String(shanghaiDateString(entry.date).suffix(2)))
                                    .font(.title2.bold())
                            }
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 52, height: 64)
                            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(entry.leadTitle ?? "AI 日报").font(.headline).lineLimit(3)
                                if let lead = entry.leadParagraph {
                                    Text(lead).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Text(shanghaiDateString(entry.date)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                }
                if response.items.count >= limit && limit < 180 {
                    Button("查看更多往期") { limit = min(limit + 30, 180) }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(model.isLoading)
                } else {
                    Text("已展示当前可用日报").font(.footnote).foregroundStyle(.secondary)
                }
            } else if model.isLoading {
                ReadingSkeleton()
            }
        }
        .readerBackground()
        .navigationTitle("往期日报")
        .task(id: limit) { await load() }
        .refreshable { await load(reload: true) }
    }

    private func load(reload: Bool = false) async {
        do {
            await model.load(try .dailies(limit: limit), reload: reload)
        } catch {
            model.showError(error)
        }
    }
}

struct DailyDetailView: View {
    private let date: String
    private let fallbackURL: URL?
    private let isSavedCopy: Bool
    @Environment(LibraryStore.self) private var library
    @State private var model: ResourceViewModel<DailyResponse>

    init(entry: DailyEntry, repository: NewsRepository) {
        date = shanghaiDateString(entry.date)
        fallbackURL = entry.links.aihot
        isSavedCopy = false
        _model = State(initialValue: ResourceViewModel(repository: repository))
    }

    init(report: DailyReport, repository: NewsRepository) {
        date = shanghaiDateString(report.date)
        fallbackURL = report.links.aihot
        isSavedCopy = true
        _model = State(initialValue: ResourceViewModel(repository: repository, initialValue: DailyResponse(schemaVersion: 1, report: report)))
    }

    init(date: String, repository: NewsRepository) {
        self.date = date
        fallbackURL = nil
        isSavedCopy = false
        _model = State(initialValue: ResourceViewModel(repository: repository))
    }

    var body: some View {
        List {
            if isSavedCopy { LocalCopyNotice() }
            LoadStatusView(isLoading: model.isLoading, message: model.message, retryAt: model.retryAt) {
                await load(reload: true)
            }
            if let report = model.value?.report {
                DailyReportSections(report: report)
            } else if model.isLoading {
                ReadingSkeleton()
            } else {
                ContentUnavailableView("暂时无法读取日报", systemImage: "calendar.badge.exclamationmark", description: Text("请检查连接后重试，已收藏的日报可离线阅读。"))
                if let fallbackURL { Link("打开网页版日报", destination: fallbackURL) }
            }
        }
        .readerBackground()
        .navigationTitle(date)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            if let report = model.value?.report {
                DailySaveButton(report: report)
                ShareLink(item: report.links.aihot, subject: Text("AI 日报 · \(date)"))
                    .accessibilityLabel("分享日报")
            }
        }
        .task { await load() }
        .refreshable { await load(reload: true) }
    }

    private func load(reload: Bool = false) async {
        do {
            await model.load(try .daily(date: date), reload: reload)
            if model.value != nil { library.markRead(kind: "daily", id: date) }
        } catch {
            model.showError(error)
        }
    }
}

private struct DailySaveButton: View {
    let report: DailyReport
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let saved = library.isSaved(kind: "daily", id: shanghaiDateString(report.date))
        Button { library.toggleDaily(report) } label: {
            Label(saved ? "取消收藏" : "收藏日报", systemImage: saved ? "star.fill" : "star")
        }
    }
}

struct DailyReportSections: View {
    let report: DailyReport
    var isLatest = false
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(isLatest ? "最新一期" : "每日速览")
                        .font(.caption.bold()).foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                    Spacer()
                    Text(shanghaiDateString(report.date)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                if let lead = report.lead {
                    Text(lead.title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                    Text(lead.leadParagraph).font(.body).lineSpacing(6)
                } else {
                    Text("AI 日报").font(.title.bold())
                }
                Divider()
                Label("\(report.sections.reduce(0) { $0 + $1.items.count }) 条精选 · \(report.flashes.count) 条快讯", systemImage: "text.book.closed")
                    .font(.caption).foregroundStyle(.secondary)
                Text("统计区间（上海）：\(shanghaiTime(report.windowStart)) — \(shanghaiTime(report.windowEnd))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
        }
        .listRowBackground(Color.clear)
        ForEach(Array(report.sections.enumerated()), id: \.offset) { _, section in
            Section(section.label) {
                ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                    let article = ArticleSnapshot(item: item)
                    ReaderLink(route: .article(article)) {
                        ArticleRow(article: article, isRead: library.isRead(kind: "item", id: article.id))
                            .padding(.vertical, 8)
                    }
                }
            }
        }
        if !report.flashes.isEmpty {
            Section("快讯") {
                ForEach(Array(report.flashes.enumerated()), id: \.offset) { _, flash in
                    let article = ArticleSnapshot(flash: flash)
                    ReaderLink(route: .article(article)) {
                        ArticleRow(article: article, isRead: library.isRead(kind: "item", id: article.id))
                            .padding(.vertical, 8)
                    }
                }
            }
        }
        Section {
            Link(destination: report.links.aihot) {
                Label("打开网页版日报", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        } footer: {
            Text("摘要可能由自动化系统生成，重要事实请以原文为准。")
        }
    }
}

@MainActor
func shanghaiDateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

private func shanghaiTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "M月d日 HH:mm"
    return formatter.string(from: date)
}
