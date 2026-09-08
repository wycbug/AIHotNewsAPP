import SwiftUI
#if os(iOS)
import SafariServices
#endif

struct LoadStatusView: View {
    let isLoading: Bool
    let message: String?
    var retryAt: Date? = nil
    let retry: () async -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 8) {
                if isLoading { ProgressView("正在加载…") }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                if let retryAt, retryAt > context.date {
                    Text("可重试时间：\(retryAt.formatted(date: .omitted, time: .standard))")
                        .font(.footnote)
                }
                Button("刷新 / 重试") { Task { await retry() } }
                    .disabled(isLoading || (retryAt.map { $0 > context.date } ?? false))
            }
            .padding(.vertical, 4)
        }
    }
}

struct ArticleDetailView: View {
    let title: String
    var originalTitle: String? = nil
    var summary: String? = nil
    var reason: String? = nil
    let source: String
    var originalURL: URL? = nil
    var aihotURL: URL? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(source).font(.subheadline).foregroundStyle(.secondary)
                Text(title).font(.title.bold())
                if let originalTitle, originalTitle != title {
                    Text(originalTitle).foregroundStyle(.secondary)
                }
                if let reason, !reason.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("推荐理由").font(.headline)
                        Text(reason)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                Text(summary ?? "暂无摘要，请阅读原文。")
                Text("摘要可能由自动化系统生成，数字与引语请以原文为准。")
                    .font(.footnote).foregroundStyle(.secondary)
                ArticleLinks(original: originalURL, aihot: aihotURL)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .textSelection(.enabled)
        .navigationTitle("资讯卡片")
        .toolbar {
            if let url = originalURL ?? aihotURL {
                ShareLink(item: url, subject: Text(title))
            }
        }
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
