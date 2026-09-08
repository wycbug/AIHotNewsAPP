import SwiftUI

@MainActor
struct BookmarksView: View {
    let repository: NewsRepository
    var kind: String? = nil
    @Environment(LibraryStore.self) private var library
    @State private var selectedKind = "all"
    @State private var pendingRemoval: Bookmark?
    @State private var confirmRemoval = false

    private var activeKind: String {
        kind.map(LibraryKey.canonicalKind) ?? selectedKind
    }

    private var saved: [Bookmark] {
        library.bookmarks.filter { activeKind == "all" || $0.kind == activeKind }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("本机收藏", systemImage: "bookmark.fill")
                        .font(.headline).foregroundStyle(LibraryPalette.teal)
                    Text("仅你设备上的副本 · 无需登录，不会上传")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if kind == nil {
                        Picker("收藏类型", selection: $selectedKind) {
                            Text("全部").tag("all")
                            Text("条目").tag("item")
                            Text("事件").tag("story")
                            Text("日报").tag("daily")
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(.vertical, 8)
            }
            if let error = library.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("重新读取资料库") { library.reload() }
                }
            }
            if saved.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("还没有收藏", systemImage: "bookmark")
                    } description: {
                        Text("在详情右上角点星标，即可保存在这台设备上。")
                    }
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(saved, id: \.key) { bookmark in
                        ReaderLink(route: .bookmark(bookmark.key)) {
                            BookmarkRow(bookmark: bookmark)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("取消收藏", role: .destructive) { requestRemoval(bookmark) }
                        }
                        .contextMenu {
                            Button("取消收藏", systemImage: "bookmark.slash", role: .destructive) {
                                requestRemoval(bookmark)
                            }
                        }
                    }
                } header: {
                    Text("\(saved.count) 份收藏 · 最近收藏在前")
                } footer: {
                    Text("保存的是收藏时的摘要与链接，不包含第三方全文。原文网页仍需联网打开。")
                }
            }
        }
        .libraryListSurface()
        .navigationTitle(title)
        .confirmationDialog("取消这份收藏？", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("取消收藏", role: .destructive) {
                if let pendingRemoval { library.remove(pendingRemoval) }
                pendingRemoval = nil
            }
            Button("保留", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("将删除这台设备上的收藏副本，不影响已读标记。此操作无法撤销。")
        }
    }

    private var title: String {
        switch kind.map(LibraryKey.canonicalKind) {
        case "item": "条目收藏"
        case "story": "事件收藏"
        case "daily": "日报收藏"
        default: "本机收藏"
        }
    }

    private func requestRemoval(_ bookmark: Bookmark) {
        pendingRemoval = bookmark
        confirmRemoval = true
    }
}

@MainActor
private struct BookmarkRow: View {
    let bookmark: Bookmark
    @Environment(LibraryStore.self) private var library
    @State private var source: String?
    @State private var summary: String?
    @State private var damaged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Label(kindName, systemImage: kindIcon)
                    .foregroundStyle(LibraryPalette.teal)
                Spacer(minLength: 8)
                if library.isRead(kind: bookmark.kind, id: bookmark.publicID) {
                    Text("已读").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            Text(bookmark.title)
                .font(.headline).lineLimit(3)
                .foregroundStyle(library.isRead(kind: bookmark.kind, id: bookmark.publicID) ? .secondary : .primary)
            if let summary, !summary.isEmpty {
                Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(source ?? "本机副本").lineLimit(1)
                    Spacer(minLength: 12)
                    Text(bookmark.savedAt, format: .dateTime.month().day()) + Text(" 收藏")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(source ?? "本机副本")
                    Text(bookmark.savedAt, format: .dateTime.month().day()) + Text(" 收藏")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            if damaged {
                Label("副本无法读取，可取消收藏后重新保存", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .task(id: bookmark.payload) { loadPreview() }
    }

    private var kindName: String {
        switch bookmark.kind {
        case "story": "事件"
        case "daily": "日报"
        default: "条目"
        }
    }

    private var kindIcon: String {
        switch bookmark.kind {
        case "story": "point.3.connected.trianglepath.dotted"
        case "daily": "calendar"
        default: "doc.text"
        }
    }

    private func loadPreview() {
        damaged = false
        switch bookmark.kind {
        case "item":
            if let article = library.decode(ArticleSnapshot.self, from: bookmark) {
                source = article.source
                summary = article.summary
            } else { damaged = true }
        case "story":
            if let story = library.decode(Story.self, from: bookmark) {
                source = "\(story.sourceCount) 家来源 · \(story.reportCount) 条报道"
                summary = story.latest
            } else { damaged = true }
        case "daily":
            if let report = library.decode(DailyReport.self, from: bookmark) {
                source = "AI 日报 · \(LibraryKey.dailyID(report.date))"
                summary = report.lead?.leadParagraph
            } else { damaged = true }
        default:
            damaged = true
        }
    }
}

@MainActor
struct SavedBookmarkDetail: View {
    let bookmark: Bookmark
    let repository: NewsRepository
    @Environment(LibraryStore.self) private var library
    @State private var article: ArticleSnapshot?
    @State private var story: Story?
    @State private var daily: DailyReport?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let article {
                ArticleDetailView(article: article)
            } else if let story {
                StoryDetailView(link: story.links.aihot, repository: repository, savedStory: story)
            } else if let daily {
                DailyDetailView(report: daily, repository: repository)
            } else if didLoad {
                ContentUnavailableView("无法读取收藏副本", systemImage: "exclamationmark.doc",
                                       description: Text("本机资料可能已损坏。你可以返回列表取消收藏，再从最近内容重新保存。"))
            } else {
                ProgressView("正在读取本机副本")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Label("仅你设备上的副本 · 保存于 \(bookmark.savedAt.formatted(date: .abbreviated, time: .omitted))", systemImage: "internaldrive")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
        }
        .task {
            switch bookmark.kind {
            case "item": article = library.decode(ArticleSnapshot.self, from: bookmark)
            case "story": story = library.decode(Story.self, from: bookmark)
            case "daily": daily = library.decode(DailyReport.self, from: bookmark)
            default: break
            }
            didLoad = true
            if article != nil || story != nil || daily != nil {
                library.markRead(kind: bookmark.kind, id: bookmark.publicID)
            }
        }
    }
}

@MainActor
struct LibraryPalette {
    static let teal = ReaderTheme.accent
}

private struct LibraryListSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
#if os(iOS)
            .listStyle(.insetGrouped)
#else
            .listStyle(.inset)
#endif
            .scrollContentBackground(.hidden)
            .background(colorScheme == .dark ? Color.black.opacity(0.15) : Color(red: 247 / 255, green: 246 / 255, blue: 243 / 255))
            .tint(colorScheme == .dark ? Color(red: 45 / 255, green: 212 / 255, blue: 191 / 255) : LibraryPalette.teal)
    }
}

extension View {
    func libraryListSurface() -> some View {
        modifier(LibraryListSurface())
    }
}
