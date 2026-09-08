import SwiftUI

struct HotTopicsView: View {
    @Bindable var model: ResourceViewModel<HotTopicsResponse>
    let repository: NewsRepository

    var body: some View {
        List {
            Text("多源同时报道的当前事件，不是热度分数榜。")
                .font(.footnote).foregroundStyle(.secondary)
            LoadStatusView(isLoading: model.isLoading, message: model.message, retryAt: model.retryAt) {
                await model.load(.hotTopics(), reload: true)
            }
            if let response = model.value {
                if response.items.isEmpty {
                    ContentUnavailableView("暂无热点", systemImage: "flame")
                }
                ForEach(response.items) { topic in
                    NavigationLink {
                        if let link = topic.links.story {
                            StoryDetailView(link: link, repository: repository)
                        } else {
                            ArticleDetailView(title: topic.title, source: topic.source.name,
                                              originalURL: topic.links.original, aihotURL: topic.links.aihot)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 16) {
                            Text("\(topic.rank)").font(.title2.bold()).foregroundStyle(.teal)
                                .accessibilityLabel("第 \(topic.rank) 名")
                            VStack(alignment: .leading, spacing: 8) {
                                Text(topic.title).font(.headline)
                                Text("\(topic.sourceCount) 家来源 · \(topic.source.name)")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(topic.latestAt, style: .relative)
                                    .font(.caption).foregroundStyle(.secondary)
                                if topic.links.story != nil {
                                    Label("事件综述", systemImage: "text.alignleft").font(.caption)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("热点")
        .task { await model.load(.hotTopics()) }
        .refreshable { await model.load(.hotTopics(), reload: true) }
    }
}

struct StoryDetailView: View {
    let link: URL
    let repository: NewsRepository
    @State private var model: ResourceViewModel<StoryResponse>

    init(link: URL, repository: NewsRepository) {
        self.link = link
        self.repository = repository
        _model = State(initialValue: ResourceViewModel(repository: repository))
    }

    var body: some View {
        List {
            LoadStatusView(isLoading: model.isLoading, message: model.message, retryAt: model.retryAt) {
                await load(reload: true)
            }
            if let story = model.value?.story {
                Section {
                    Text(story.title).font(.title.bold())
                    Text("\(story.sourceCount) 家来源 · \(story.reportCount) 条报道")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(story.latest)
                }
                Section("综述") {
                    Text(story.digest ?? "暂无综述，可先看下方报道时间线。")
                    if let date = story.digestUpdatedAt {
                        Text("综述更新于 \(date.formatted())").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("综述可能由自动化系统生成，重要事实请打开原文核对。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("打开事件站内页", destination: story.links.aihot)
                }
                Section("报道时间线") {
                    ForEach(story.reports) { report in
                        NavigationLink {
                            ArticleDetailView(title: report.title, summary: report.summary,
                                              source: report.source.name, originalURL: report.links.original,
                                              aihotURL: report.links.aihot)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(report.title).font(.headline)
                                Text(report.source.name + (report.source.firstParty ? " · 当事方" : ""))
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(report.publishedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else if !model.isLoading {
                Text("暂时无法读取事件。可以重试，或打开站内页。")
                Link("打开事件站内页", destination: link)
            }
        }
        .textSelection(.enabled)
        .navigationTitle("事件")
        .task { await load() }
        .refreshable { await load(reload: true) }
    }

    private func load(reload: Bool = false) async {
        do {
            let publicID = try StoryLink.publicID(from: link)
            await model.load(try .story(publicID: publicID), reload: reload)
        } catch {
            model.showError(error)
        }
    }
}
