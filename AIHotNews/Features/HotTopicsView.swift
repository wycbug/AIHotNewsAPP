import SwiftUI

struct HotTopicsView: View {
    @Bindable var model: ResourceViewModel<HotTopicsResponse>
    let repository: NewsRepository
    @AppStorage("hideHotExplanation") private var hideExplanation = false

    var body: some View {
        List {
            if !hideExplanation {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Text("多源同时报道的当前事件，不是热度分数榜。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button { hideExplanation = true } label: {
                            Image(systemName: "xmark").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭热点说明")
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            LoadStatusView(isLoading: model.isLoading, message: model.message, retryAt: model.retryAt) {
                await model.load(.hotTopics(), reload: true)
            }
            if let response = model.value {
                Section("当前热点 · \(response.items.count) 件") {
                    if response.items.isEmpty {
                        ContentUnavailableView("暂无热点", systemImage: "flame", description: Text("新的多源报道事件会出现在这里。"))
                    }
                    ForEach(response.items) { topic in
                        ReaderLink(route: topic.links.story.flatMap { link in
                            (try? StoryLink.publicID(from: link)).map { .story($0, link) }
                        } ?? .hotArticle(topic)) {
                            HStack(alignment: .top, spacing: 16) {
                                Text(String(format: "%02d", topic.rank))
                                    .font(.system(.title2, design: .rounded, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(topic.rank <= 3 ? Color.accentColor : Color.secondary)
                                    .frame(minWidth: 36, alignment: .leading)
                                    .accessibilityLabel("第 \(topic.rank) 名")
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(topic.title).font(.headline).foregroundStyle(.primary).lineLimit(3)
                                    Text(topic.sourceNames.prefix(3).joined(separator: " · ") + (topic.sourceNames.count > 3 ? " 等" : ""))
                                        .font(.caption).foregroundStyle(.secondary)
                                    ViewThatFits(in: .horizontal) {
                                        HStack {
                                            topicMetadata(topic)
                                            Spacer(minLength: 8)
                                            if topic.links.story != nil { digestBadge }
                                        }
                                        VStack(alignment: .leading, spacing: 8) {
                                            topicMetadata(topic)
                                            if topic.links.story != nil { digestBadge }
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 12)
                        }
                    }
                }
            } else if model.isLoading {
                ReadingSkeleton()
            }
        }
        .readerBackground()
        .navigationTitle("热点")
#if os(macOS)
        .toolbar {
            Button { Task { await model.load(.hotTopics(), reload: true) } } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isLoading)
        }
#endif
        .task { await model.load(.hotTopics()) }
        .refreshable { await model.load(.hotTopics(), reload: true) }
    }

    private var digestBadge: some View {
        Label("有综述", systemImage: "text.alignleft")
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.1), in: Capsule())
    }

    private func topicMetadata(_ topic: HotTopic) -> some View {
        HStack(spacing: 4) {
            Text("\(topic.sourceCount) 家来源")
            Text("·")
            Text(topic.latestAt, format: .relative(presentation: .named))
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}

struct HotArticleDetailView: View {
    let topic: HotTopic
    let repository: NewsRepository
    @State private var cached: NewsItem?

    var body: some View {
        ArticleDetailView(article: ArticleSnapshot(topic: topic, cachedItem: cached))
            .task { cached = await repository.cachedItem(id: topic.id) }
    }
}

struct StoryDetailView: View {
    let publicID: String?
    let link: URL?
    let repository: NewsRepository
    let savedStory: Story?
    @Environment(LibraryStore.self) private var library
    @State private var model: ResourceViewModel<StoryResponse>

    init(link: URL, repository: NewsRepository, savedStory: Story? = nil) {
        self.publicID = savedStory?.publicId ?? (try? StoryLink.publicID(from: link))
        self.link = link
        self.repository = repository
        self.savedStory = savedStory
        _model = State(initialValue: ResourceViewModel(repository: repository, initialValue: savedStory.map { StoryResponse(schemaVersion: 1, story: $0) }))
    }

    init(publicID: String, link: URL?, repository: NewsRepository) {
        self.publicID = publicID
        self.link = link
        self.repository = repository
        savedStory = nil
        _model = State(initialValue: ResourceViewModel(repository: repository))
    }

    var body: some View {
        List {
            if savedStory != nil { LocalCopyNotice() }
            LoadStatusView(isLoading: model.isLoading, message: model.message, retryAt: model.retryAt) {
                await load(reload: true)
            }
            if let story = model.value?.story {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label(story.status == "active" ? "进行中" : story.status == "settled" ? "已收敛" : story.status,
                                  systemImage: story.status == "active" ? "dot.radiowaves.left.and.right" : "checkmark.circle")
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                            Text("\(story.sourceCount) 家来源")
                        }
                        .font(.caption.weight(.medium))
                        Text(story.title).font(.largeTitle.bold())
                        Text(story.latest).font(.body).foregroundStyle(.secondary).lineSpacing(5)
                        Text("\(story.reportCount) 条报道 · 最近更新 \(story.latestAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                }
                .listRowBackground(Color.clear)
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("事件综述", systemImage: "text.alignleft").font(.title3.bold())
                        Text(story.digest ?? "暂无综述，可先看下方报道时间线。")
                            .font(.body).lineSpacing(7)
                        if let date = story.digestUpdatedAt {
                            Text("综述更新于 \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("综述可能由自动化系统生成，重要事实请打开原文核对。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Link(destination: story.links.aihot) {
                            Label("打开事件站内页", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
                Section("报道时间线 · \(story.reports.count)") {
                    ForEach(story.reports) { report in
                        ReaderLink(route: .article(ArticleSnapshot(report: report))) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 6) {
                                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                                    Text(report.publishedAt, format: .dateTime.month().day().hour().minute())
                                    if report.source.firstParty { Text("· 当事方") }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                                ArticleRow(article: ArticleSnapshot(report: report), isRead: library.isRead(kind: "item", id: report.id))
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                neighbors(story.storyline, title: "同一事件线")
                neighbors(story.related, title: "相关事件")
            } else if model.isLoading {
                ReadingSkeleton()
            } else {
                ContentUnavailableView("暂时无法读取事件", systemImage: "doc.text.magnifyingglass", description: Text("事件可能已下线，也可能是连接暂不可用。"))
                if let link { Link("打开事件站内页", destination: link) }
            }
        }
        .readerBackground()
        .textSelection(.enabled)
        .navigationTitle("事件")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            if let story = model.value?.story {
                Button { library.toggleStory(story) } label: {
                    Label(library.isSaved(kind: "story", id: story.publicId) ? "取消收藏" : "收藏事件",
                          systemImage: library.isSaved(kind: "story", id: story.publicId) ? "star.fill" : "star")
                }
                ShareLink(item: story.links.aihot, subject: Text(story.title))
                    .accessibilityLabel("分享事件")
            }
#if os(macOS)
            Button { Task { await load(reload: true) } } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isLoading)
#endif
        }
        .task { await load() }
        .refreshable { await load(reload: true) }
    }

    @ViewBuilder
    private func neighbors(_ items: [StoryNeighbor], title: String) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    ReaderLink(route: .story(item.publicId, item.links.aihot)) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title).font(.headline)
                            Text(item.relation).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func load(reload: Bool = false) async {
        do {
            guard let publicID else { throw RequestValidationError.invalidStoryLink }
            await model.load(try .story(publicID: publicID), reload: reload)
            if let story = model.value?.story {
                library.reconcileStory(previousID: publicID, story: story)
                library.markRead(kind: "story", id: story.publicId)
            }
        } catch {
            model.showError(error)
        }
    }
}

struct EditorialHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(eyebrow, systemImage: symbol)
                .font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
            Text(title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

struct ReadingSkeleton: View {
    var body: some View {
        ForEach(0..<4, id: \.self) { _ in
            VStack(alignment: .leading, spacing: 12) {
                Text("正在准备阅读内容").font(.caption)
                Text("正在加载最新报道与事件摘要").font(.headline)
                Text("内容就绪后将在这里展示，稍候即可开始阅读。").font(.subheadline)
            }
            .foregroundStyle(.secondary)
            .redacted(reason: .placeholder)
            .padding(.vertical, 12)
            .accessibilityHidden(true)
        }
    }
}

struct LocalCopyNotice: View {
    var body: some View {
        Label("仅你设备上的副本 · 原文网页需联网", systemImage: "internaldrive")
            .font(.footnote).foregroundStyle(.secondary)
    }
}
