import SwiftUI

struct DailyHomeView: View {
    let container: AppContainer

    var body: some View {
        List {
            Section {
                NavigationLink("往期日报") {
                    DailyArchiveView(model: container.dailies, repository: container.repository)
                }
            } footer: {
                Text("每日 08:00（上海时间）发布；最新一期日期以接口为准。")
            }
            LoadStatusView(isLoading: container.latestDaily.isLoading, message: container.latestDaily.message,
                           retryAt: container.latestDaily.retryAt) {
                await container.latestDaily.load(.latestDaily(), reload: true)
            }
            if let report = container.latestDaily.value?.report {
                DailyReportSections(report: report)
            } else if !container.latestDaily.isLoading {
                ContentUnavailableView("暂无可读日报", systemImage: "calendar", description: Text("可能尚未发布，或连接暂不可用。可以重试或查看往期。"))
            }
        }
        .navigationTitle("日报")
        .task { await container.latestDaily.load(.latestDaily()) }
        .refreshable { await container.latestDaily.load(.latestDaily(), reload: true) }
    }
}

struct DailyArchiveView: View {
    @Bindable var model: ResourceViewModel<DailiesResponse>
    let repository: NewsRepository

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
                    NavigationLink {
                        DailyDetailView(entry: entry, repository: repository)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(shanghaiDateString(entry.date)).font(.caption).foregroundStyle(.secondary)
                            Text(entry.leadTitle ?? "AI 日报").font(.headline)
                            if let lead = entry.leadParagraph {
                                Text(lead).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("往期日报")
        .task { await load() }
        .refreshable { await load(reload: true) }
    }

    private func load(reload: Bool = false) async {
        do {
            await model.load(try .dailies(limit: 30), reload: reload)
        } catch {
            model.showError(error)
        }
    }
}

struct DailyDetailView: View {
    let entry: DailyEntry
    @State private var model: ResourceViewModel<DailyResponse>

    init(entry: DailyEntry, repository: NewsRepository) {
        self.entry = entry
        _model = State(initialValue: ResourceViewModel(repository: repository))
    }

    var body: some View {
        List {
            LoadStatusView(isLoading: model.isLoading, message: model.message, retryAt: model.retryAt) {
                await load(reload: true)
            }
            if let report = model.value?.report {
                DailyReportSections(report: report)
            } else if !model.isLoading {
                Link("打开网页版日报", destination: entry.links.aihot)
            }
        }
        .navigationTitle(shanghaiDateString(entry.date))
        .task { await load() }
    }

    private func load(reload: Bool = false) async {
        do {
            await model.load(try .daily(date: shanghaiDateString(entry.date)), reload: reload)
        } catch {
            model.showError(error)
        }
    }
}

struct DailyReportSections: View {
    let report: DailyReport

    var body: some View {
        Section {
            Text("AI 日报 · \(shanghaiDateString(report.date))").font(.title2.bold())
            Text("统计区间：\(report.windowStart.formatted()) – \(report.windowEnd.formatted())")
                .font(.caption).foregroundStyle(.secondary)
            if let lead = report.lead {
                Text(lead.title).font(.title3.bold())
                Text(lead.leadParagraph)
            }
        }
        ForEach(Array(report.sections.enumerated()), id: \.offset) { _, section in
            Section(section.label) {
                ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                    NavigationLink {
                        ArticleDetailView(title: item.title, summary: item.summary, source: item.source.name,
                                          originalURL: item.links.original, aihotURL: item.links.aihot)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title).font(.headline)
                            Text(item.summary).font(.subheadline).foregroundStyle(.secondary)
                            Text(item.source.name).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        if !report.flashes.isEmpty {
            Section("快讯") {
                ForEach(Array(report.flashes.enumerated()), id: \.offset) { _, flash in
                    NavigationLink {
                        ArticleDetailView(title: flash.title, source: flash.source.name,
                                          originalURL: flash.links.original, aihotURL: flash.links.aihot)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(flash.title).font(.headline)
                            Text(flash.source.name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        Section {
            Link("打开网页版日报", destination: report.links.aihot)
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
