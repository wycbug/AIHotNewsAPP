import SwiftUI

@MainActor
struct AboutView: View {
    let container: AppContainer
    @Environment(LibraryStore.self) private var library
    @State private var confirmClearRead = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: "text.book.closed.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.tint)
                            .frame(width: 60, height: 60)
                            .background(.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("本机资料库").font(.title3.bold())
                            Text("\(library.bookmarks.count) 份收藏 · \(library.readKeys.count) 条已读")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 8) {
                        Label("免费", systemImage: "checkmark.circle")
                        Text("·")
                        Text("无广告")
                        Text("·")
                        Text("无登录")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
            }
            Section {
                collectionLink("条目收藏", subtitle: "摘要、推荐理由与原文链接", icon: "doc.text", kind: "item")
                collectionLink("事件收藏", subtitle: "综述与多源报道时间线", icon: "point.3.connected.trianglepath.dotted", kind: "story")
                collectionLink("日报收藏", subtitle: "留存完整的每日阅读", icon: "calendar", kind: "daily")
            } header: {
                Text("我的收藏")
            } footer: {
                Text("仅保存在这台设备上，离线也能阅读收藏副本。")
            }
            Section {
                Button { confirmClearRead = true } label: {
                    LibrarySettingsRow(title: "清除已读标记", icon: "checkmark.circle", detail: "\(library.readKeys.count) 条")
                }
                .buttonStyle(.plain)
                .disabled(library.readKeys.isEmpty)
            } header: {
                Text("阅读记录")
            } footer: {
                Text("已读标记只用于区分读过的内容，不记录浏览轨迹。")
            }
            Section("偏好与支持") {
                ReaderLink(route: .settings) {
                    LibrarySettingsRow(title: "设置", icon: "slider.horizontal.3", detail: "外观与阅读")
                }
                ReaderLink(route: .about) {
                    LibrarySettingsRow(title: "关于 AI 圈速览", icon: "info.circle", detail: nil)
                }
            }
            if let error = library.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("重新读取本机资料") { library.reload() }
                }
            }
            Section {
                VStack(spacing: 6) {
                    Text("AI 圈速览").font(.footnote.weight(.medium))
                    Text("摘要在这里读，全文在原文打开")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
        }
        .libraryListSurface()
        .navigationTitle("我的")
        .confirmationDialog("清除全部已读标记？", isPresented: $confirmClearRead, titleVisibility: .visible) {
            Button("清除已读标记", role: .destructive) { library.clearRead() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有内容将恢复为未读。不会删除收藏或网络缓存，此操作无法撤销。")
        }
    }

    private func collectionLink(_ title: String, subtitle: String, icon: String, kind: String) -> some View {
        ReaderLink(route: .bookmarks(kind)) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 38, height: 38)
                    .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.body.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("\(library.bookmarks.filter { $0.kind == kind }.count)")
                    .font(.title3.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(.tint)
            }
            .padding(.vertical, 7)
        }
    }
}

@MainActor
struct SettingsView: View {
    let container: AppContainer
    @Environment(LibraryStore.self) private var library
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("defaultWindow") private var defaultWindow = "24h"
    @AppStorage("defaultMode") private var defaultMode = "selected"
    @AppStorage("publishedOrder") private var publishedOrder = false
    @State private var isClearing = false
    @State private var cacheMessage: String?
    @State private var confirmClearCache = false
    @State private var confirmClearRead = false

    var body: some View {
        List {
            Section("外观") {
                Picker(selection: $appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                } label: {
                    Label("显示模式", systemImage: "circle.lefthalf.filled")
                }
                .frame(minHeight: 44)
            }
            Section {
                Picker("默认时间窗", selection: $defaultWindow) {
                    Text("24 小时").tag("24h")
                    Text("7 天").tag("7d")
                }
                .frame(minHeight: 44)
                Picker("默认资讯范围", selection: $defaultMode) {
                    Text("精选").tag("selected")
                    Text("公开池").tag("all")
                }
                .frame(minHeight: 44)
                Toggle("按原文时间排序", isOn: $publishedOrder)
                    .frame(minHeight: 44)
            } header: {
                Text("阅读偏好")
            } footer: {
                Text("默认按收录时间排列。公开池仅包含最近 7 天的可见动态，不是全站历史。")
            }
            Section {
                Button { confirmClearCache = true } label: {
                    HStack {
                        LibrarySettingsRow(title: "清除网络缓存", icon: "externaldrive", detail: nil)
                        if isClearing { ProgressView().controlSize(.small) }
                    }
                }
                .buttonStyle(.plain).disabled(isClearing)
                Button { confirmClearRead = true } label: {
                    LibrarySettingsRow(title: "清除已读标记", icon: "checkmark.circle", detail: "\(library.readKeys.count) 条")
                }
                .buttonStyle(.plain).disabled(library.readKeys.isEmpty)
                if let notice = container.cacheNotice {
                    Text(notice).font(.footnote).foregroundStyle(.secondary)
                }
                if let cacheMessage {
                    Text(cacheMessage).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("cacheStatus")
                }
                if let error = library.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("本机存储")
            } footer: {
                Text("清除网络缓存不会删除收藏或已读标记。缓存仅供本机阅读，不提供全库镜像或批量导出。")
            }
            Section {
                ReaderLink(route: .about) {
                    LibrarySettingsRow(title: "关于 AI 圈速览", icon: "info.circle", detail: nil)
                }
            } footer: {
                Text("无需账号 · 不做云同步 · 不含广告与追踪 SDK")
            }
        }
        .libraryListSurface()
        .navigationTitle("设置")
        .onChange(of: publishedOrder) { _, value in
            container.feed.query.by = value ? .published : .timeline
        }
        .onChange(of: defaultWindow) { _, value in
            if let window = ItemsWindow(rawValue: value) { container.feed.query.window = window }
        }
        .onChange(of: defaultMode) { _, value in
            if let mode = ItemsMode(rawValue: value) { container.feed.query.mode = mode }
        }
        .confirmationDialog("清除本机网络缓存？", isPresented: $confirmClearCache, titleVisibility: .visible) {
            Button("清除缓存", role: .destructive) { clearCache() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("收藏与已读标记会保留。已打开的页面可继续显示，再次访问时重新请求。")
        }
        .confirmationDialog("清除全部已读标记？", isPresented: $confirmClearRead, titleVisibility: .visible) {
            Button("清除已读标记", role: .destructive) { library.clearRead() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("内容将恢复为未读，不影响收藏。此操作无法撤销。")
        }
    }

    private func clearCache() {
        Task {
            isClearing = true
            defer { isClearing = false }
            do {
                try await container.repository.clearCache()
                cacheMessage = "网络缓存已清除，收藏与已读标记已保留。"
            } catch {
                cacheMessage = "清除失败：\(error.localizedDescription)"
            }
        }
    }
}

@MainActor
struct ProductAboutView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 36, weight: .light)).foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("AI 圈速览").font(.title.bold())
                    Text("少一点噪音，多一点理解。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("免费 · 无广告 · 无登录")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
            }
            Section("数据与来源") {
                Text("本应用不是 AIHOT 官方产品。")
                    .font(.headline)
                Text("本应用读取 aihot.news 的公开只读接口，展示摘要、推荐理由与链接。标题翻译和摘要可能由自动化系统生成，重要事实请打开原文核对。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Link(destination: URL(string: "https://aihot.news/terms")!) {
                    LibrarySettingsRow(title: "公开使用规则", icon: "doc.plaintext", detail: "aihot.news")
                }
                Link(destination: URL(string: "https://aihot.news/agent")!) {
                    LibrarySettingsRow(title: "数据接入说明", icon: "network", detail: "aihot.news")
                }
            }
            Section("隐私与反馈") {
                Text("收藏与已读仅存储在本机，不上传、不跨设备同步。外部文章通过系统浏览器打开，访问时适用对应网站的隐私政策。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Link(destination: URL(string: "https://aihot.news/feedback")!) {
                    LibrarySettingsRow(title: "数据来源反馈", icon: "bubble.left", detail: "aihot.news")
                }
            }
        }
        .libraryListSurface()
        .navigationTitle("关于")
    }
}

@MainActor
private struct LibrarySettingsRow: View {
    let title: String
    let icon: String
    let detail: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18)).foregroundStyle(.tint)
                .frame(width: 26).accessibilityHidden(true)
            Text(title).foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
