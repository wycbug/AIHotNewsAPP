import SwiftUI
#if os(iOS)
import SafariServices
#endif

struct LoadStatusView: View {
    let isLoading: Bool
    let message: String?
    var retryAt: Date? = nil
    let retry: () async -> Void
    @State private var isRetrying = false

    private var isInformational: Bool {
        guard let message else { return true }
        return message.hasPrefix("更新于") || message.hasPrefix("正在显示缓存")
    }

    var body: some View {
        status
            .listRowBackground(Color.clear)
            .task(id: retryAt) {
                guard let retryAt else { return }
                do {
                    try await Task.sleep(for: .seconds(max(0, retryAt.timeIntervalSinceNow)))
                    try Task.checkCancellation()
                    await retry()
                } catch {}
            }
    }

    @ViewBuilder
    private var status: some View {
        if isLoading && message == nil {
            ProgressView("正在加载…")
                .font(.footnote)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let message {
            if isInformational && retryAt == nil {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: message.hasPrefix("更新于") ? "checkmark.circle" : "clock")
                            .foregroundStyle(ReaderTheme.accent)
                    }
                    Text(message)
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .padding(.vertical, 4)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(message, systemImage: message.hasPrefix("离线") ? "wifi.slash" : "exclamationmark.circle")
                            .font(.footnote)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 12) {
                            if let retryAt, retryAt > context.date {
                                Text("\(Int(ceil(retryAt.timeIntervalSince(context.date)))) 秒后自动重试")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button {
                                isRetrying = true
                                Task {
                                    await retry()
                                    isRetrying = false
                                }
                            } label: {
                                Label(isLoading || isRetrying ? "正在重试" : "重试", systemImage: "arrow.clockwise")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.glass)
                            .disabled(isLoading || isRetrying || (retryAt.map { $0 > context.date } ?? false))
                        }
                    }
                    .padding(14)
                    .background(ReaderTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: ReaderTheme.cornerRadius))
                }
            }
        }
    }
}

struct ArticleRow: View {
    let article: ArticleSnapshot
    var isRead = false
    var selected = false
    var prefersPublishedTime = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var displayDate: Date? {
        prefersPublishedTime ? (article.publishedAt ?? article.discoveredAt) : (article.discoveredAt ?? article.publishedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    categoryLabel
                    Spacer(minLength: 8)
                    timestamp
                }
                VStack(alignment: .leading, spacing: 6) {
                    categoryLabel
                    timestamp
                }
            }
            Text(article.title)
                .font(.headline)
                .foregroundStyle(isRead ? .secondary : .primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if let summary = article.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(article.listSummaryLineLimit(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text(article.source)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isRead {
                    Image(systemName: "checkmark")
                        .accessibilityLabel("已读")
                }
                if selected {
                    Text("精选")
                        .fontWeight(.medium)
                        .foregroundStyle(ReaderTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(ReaderTheme.accent.opacity(0.08), in: Capsule())
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isRead ? "已读" : "未读")
    }

    private var categoryLabel: some View {
        HStack(spacing: 6) {
            if article.category != nil {
                Circle()
                    .fill(ReaderTheme.categoryColor(article.category))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Text(article.category == nil ? article.source : ReaderTheme.categoryName(article.category))
                .lineLimit(1)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var timestamp: some View {
        if let date = displayDate {
            Text(date, format: .relative(presentation: .named))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct ArticleDetailView: View {
    let article: ArticleSnapshot
    @Environment(LibraryStore.self) private var library
    @Environment(AppContainer.self) private var container
    @Environment(\.colorScheme) private var colorScheme

    init(article: ArticleSnapshot) {
        self.article = article
    }

    init(title: String, originalTitle: String? = nil, summary: String? = nil,
         reason: String? = nil, source: String, originalURL: URL? = nil, aihotURL: URL? = nil) {
        let id = aihotURL?.path.split(separator: "/").last.map(String.init)
            ?? originalURL?.absoluteString ?? "legacy:\(source):\(title)"
        self.article = ArticleSnapshot(id: id, title: title, originalTitle: originalTitle,
                                       summary: summary, reason: reason, source: source,
                                       originalURL: originalURL, aihotURL: aihotURL)
    }

    private var isSaved: Bool { library.isSaved(kind: "item", id: article.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                articleHeader
                if let reason = article.reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("为什么出现在精选", systemImage: "text.badge.checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ReaderTheme.accent)
                            .accessibilityAddTraits(.isHeader)
                        Text(reason)
                            .font(.body)
                            .lineSpacing(6)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ReaderTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: ReaderTheme.cornerRadius))
                }
                summarySection
                if case .topic(let topic) = article.origin {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(topic.sourceCount) 家报道来源").font(.headline)
                        Text(topic.sourceNames.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                articleActions
                if let topic = container.hotTopics.value?.items.first(where: { $0.id == article.id }),
                   let link = topic.links.story, let id = try? StoryLink.publicID(from: link) {
                    ReaderLink(route: .story(id, link)) {
                        Label("查看事件综述", systemImage: "point.3.connected.trianglepath.dotted")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                moreInformation
                if let error = library.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Image(systemName: "iphone")
                    Text(isSaved ? "已收藏到这台设备，可离线阅读此卡片" : "收藏仅保存在这台设备上")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: ReaderTheme.readingWidth, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .textSelection(.enabled)
        .readerBackground()
        .navigationTitle("资讯卡片")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            Button { library.toggleArticle(article) } label: {
                Image(systemName: isSaved ? "star.fill" : "star")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(isSaved ? "取消收藏" : "收藏资讯")
            .accessibilityValue(isSaved ? "已收藏" : "未收藏")
            if let url = article.originalURL ?? article.aihotURL {
                ShareLink(item: url, subject: Text(article.title), message: Text(article.title)) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("分享资讯")
            }
        }
        .task(id: article.id) {
            if !library.isRead(kind: "item", id: article.id) {
                library.markRead(kind: "item", id: article.id)
            }
        }
    }

    private var articleHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                if article.category != nil {
                    HStack(spacing: 6) {
                        Circle().fill(ReaderTheme.categoryColor(article.category)).frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text(ReaderTheme.categoryName(article.category))
                    }
                    .foregroundStyle(ReaderTheme.accent)
                    Text("·")
                }
                Text(article.source)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            Text(article.title)
                .font(.largeTitle.bold())
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let originalTitle = article.originalTitle,
               !originalTitle.isEmpty, originalTitle != article.title {
                Text(originalTitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
            HStack(spacing: 8) {
                if let date = article.publishedAt ?? article.discoveredAt {
                    Text(date, format: .relative(presentation: .named))
                }
                if library.isRead(kind: "item", id: article.id) {
                    Label("已读", systemImage: "checkmark.circle")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            Divider()
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("内容摘要")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(article.summary.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? "暂无摘要，请阅读原文。")
                .font(.body)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("摘要可能由自动化系统生成，数字与引语请以原文为准。")
                } icon: {
                    Image(systemName: "info.circle")
                }
                Text("网站详情里的完整中文译文不在公开接口中。本卡片只展示摘要与推荐理由，全文请打开站内页或原文。")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ReaderTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var articleActions: some View {
        VStack(spacing: 12) {
            if let original = article.originalURL {
                Link(destination: original) {
                    Label("打开原文", systemImage: "arrow.up.right.square")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(ReaderTheme.accent)
                Text(original.host() ?? original.absoluteString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Button {} label: {
                    Label("打开原文", systemImage: "arrow.up.right.square")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(true)
                Text("此条目未提供原文链接，可查看站内页。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let aihot = article.aihotURL {
                Link(destination: aihot) {
                    Label("打开站内页", systemImage: "safari")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
    }

    private var moreInformation: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 16) {
                if let score = article.score {
                    metadata("精选分", value: score.formatted(.number.precision(.fractionLength(0...1))))
                }
                if let publishedAt = article.publishedAt {
                    metadata("原文发布时间", value: publishedAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let discoveredAt = article.discoveredAt {
                    metadata("收录时间", value: discoveredAt.formatted(date: .abbreviated, time: .shortened))
                }
                metadata("条目 ID", value: article.id)
                if let attribution = article.attribution {
                    Link(destination: attribution.url) {
                        Label(attribution.name, systemImage: "link")
                            .font(.footnote)
                            .frame(minHeight: 44)
                    }
                }
            }
            .padding(.top, 12)
        } label: {
            Text("更多信息")
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(ReaderTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: ReaderTheme.cornerRadius))
    }

    private func metadata(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
        .font(.footnote)
    }
}

struct ArticleLinks: View {
    let original: URL?
    let aihot: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let original {
                Link(destination: original) { Label("打开原文", systemImage: "safari") }
                    .buttonStyle(.borderedProminent)
                Text(original.host() ?? original.absoluteString)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("此条目未提供原文链接。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let aihot {
                Link("打开站内页", destination: aihot).buttonStyle(.bordered)
            }
        }
    }
}

nonisolated enum ExternalLinkPolicy {
    static func allows(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false
    }
}

private struct SafariDestination: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SafariPresenter: ViewModifier {
#if os(iOS)
    @State private var destination: SafariDestination?
#endif

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard ExternalLinkPolicy.allows(url) else { return .discarded }
#if os(iOS)
                destination = SafariDestination(url: url)
                return .handled
#else
                return .systemAction
#endif
            })
#if os(iOS)
            .sheet(item: $destination) { destination in
                SafariView(url: destination.url).ignoresSafeArea()
            }
#endif
    }
}

#if os(iOS)
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif

extension View {
    func safariPresenter() -> some View {
        modifier(SafariPresenter())
    }
}
