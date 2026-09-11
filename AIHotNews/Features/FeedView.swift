import SwiftUI

struct FeedView: View {
    @Bindable var model: FeedViewModel
    @Binding var isSearching: Bool
    @Environment(LibraryStore.self) private var library
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.readerSelection) private var readerSelection
    @State private var showsPoolInfo = false

    private let categories: [String?] = [nil, "ai-models", "ai-products", "industry", "paper", "tip"]

    var body: some View {
        List {
#if !os(macOS)
            // 筛选跟列表一起滚动。钉在 safeAreaInset 时，大标题下拉出现的系统搜索栏会叠住分段控件。
            Section {
                filters
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
#endif

            if isSearching || model.request.q != nil {
                Section {
                    Label("搜索沿用当前时间窗、内容范围与分类。", systemImage: "line.3.horizontal.decrease")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
                .listRowBackground(ReaderTheme.accent.opacity(0.06))
            }

            if let validation = model.searchValidation {
                if model.items.isEmpty {
                    Section {
                        ContentUnavailableView("至少输入两个字", systemImage: "magnifyingglass", description: Text(validation))
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        Label(validation, systemImage: "magnifyingglass")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                    .listRowBackground(ReaderTheme.accent.opacity(0.06))
                    feedContent
                }
            } else {
                feedContent
            }
        }
#if os(iOS)
        .listStyle(.insetGrouped)
#else
        .listStyle(.inset)
        // macOS List 行内嵌套筛选控件会在辅助功能读取几何信息时触发 AttributeGraph 循环。
        .safeAreaInset(edge: .top, spacing: 0) {
            filters
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
#endif
        .readerBackground()
        .navigationTitle("精选")
#if os(iOS)
        .navigationBarTitleDisplayMode(readerSelection == nil ? .large : .inline)
#endif
        .searchable(text: $model.searchText, isPresented: $isSearching, prompt: "搜索最近内容（2–200 字）")
        .onChange(of: isSearching) { _, presented in
            if !presented { model.searchText = "" }
        }
        .onChange(of: model.searchText) { _, text in
            if !text.isEmpty { isSearching = true }
        }
        .task(id: model.request) { await model.load(debounce: model.request.q != nil) }
        .refreshable { await model.load(reload: true) }
        .toolbar {
            Button { isSearching = true } label: {
                Image(systemName: "magnifyingglass")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("搜索资讯")
            .keyboardShortcut("f", modifiers: .command)
#if os(macOS)
            Button { Task { await model.load(reload: true) } } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isLoading)
#endif
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    windowPicker.frame(minWidth: 140)
                    modePicker.frame(minWidth: 140)
                }
                VStack(spacing: 8) {
                    windowPicker
                    modePicker
                }
            }
            GlassEffectContainer(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { category in
                            CategoryChip(category: category, selected: model.query.category == category) {
                                model.query.category = category
                            }
                        }
                    }
                }
            }
            if model.query.mode == .all {
                Button { showsPoolInfo = true } label: {
                    Label("公开池不是全站历史", systemImage: "info.circle")
                        .font(.footnote)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .popover(isPresented: $showsPoolInfo) {
                    Text("公开池是最近 7 天可见动态，不是全站历史；搜索仅覆盖当前筛选范围。")
                        .font(.body)
                        .padding(24)
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
    }

    private var windowPicker: some View {
        Picker("时间窗", selection: $model.query.window) {
            Text("24 小时").tag(ItemsWindow.day)
            Text("7 天").tag(ItemsWindow.week)
        }
        .pickerStyle(.segmented)
        .frame(minHeight: 44)
    }

    private var modePicker: some View {
        Picker("内容范围", selection: $model.query.mode) {
            Text("精选").tag(ItemsMode.selected)
            Text("公开池").tag(ItemsMode.all)
        }
        .pickerStyle(.segmented)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var feedContent: some View {
        if model.message != nil && (!(model.isLoading && model.items.isEmpty) || model.retryAt != nil) {
            Section {
                LoadStatusView(isLoading: model.isLoading, message: model.message, retryAt: model.retryAt) {
                    await model.load(reload: true)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        }

        if model.isLoading && model.items.isEmpty {
            Section {
                ForEach(0..<8, id: \.self) { _ in
                    ArticleSkeletonRow()
                        .listRowBackground(ReaderTheme.surface(for: colorScheme))
                }
            } header: {
                Text("正在整理最新资讯")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("正在加载资讯")
        } else if model.items.isEmpty {
            Section {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: model.messageIsFailure ? "wifi.exclamationmark" : "newspaper")
                } description: {
                    Text(model.messageIsFailure ? "暂时无法获取内容。请检查网络，或使用上方重试。" : "试试更换关键词、分类，或扩大到最近 7 天。")
                } actions: {
                    if !model.messageIsFailure && model.query.window == .day {
                        Button("查看 7 天") { model.query.window = .week }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                    }
                }
            }
            .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(model.items, id: \.id) { item in
                    ReaderLink(route: .article(ArticleSnapshot(item: item))) {
                        ArticleRow(
                            article: ArticleSnapshot(item: item),
                            isRead: library.isRead(kind: "item", id: item.id),
                            selected: model.query.mode == .all && item.selected,
                            prefersPublishedTime: model.query.by == .published
                        )
                    }
                    .listRowBackground(ReaderTheme.surface(for: colorScheme))
                }
            } header: {
                HStack {
                    Text(model.request.q == nil ? (model.query.window == .day ? "过去 24 小时" : "最近 7 天") : "搜索结果")
                    Spacer()
                    Text("\(model.items.count) 条")
                        .monospacedDigit()
                }
                .font(.caption.weight(.medium))
                .textCase(nil)
            }
            Section {
                paginationFooter
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var emptyTitle: String {
        if model.messageIsFailure { return "暂时无法连接" }
        return model.request.q == nil ? "这段时间没有条目" : "没有找到符合条件的条目"
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if let pageError = model.pageError {
            LoadStatusView(isLoading: model.isPaging, message: "加载更多失败：\(pageError)", retryAt: model.retryAt) {
                if model.nextCursor != nil {
                    await model.loadMore()
                } else {
                    await model.load(reload: true)
                }
            }
        } else if model.nextCursor != nil {
            ProgressView("正在加载更多…")
                .font(.footnote)
                .frame(maxWidth: .infinity, minHeight: 44)
                .task(id: model.nextCursor) {
                    await model.loadMore()
                }
        } else {
            VStack(spacing: 6) {
                Text(model.hasMore || model.message?.hasPrefix("离线") == true ? "已显示本机缓存内容" : "已到本时间窗末尾")
                if model.hasMore { Button("重新验证首页") { Task { await model.load(reload: true) } } }
                Text("仅最近 7 天")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

private extension FeedViewModel {
    var messageIsFailure: Bool {
        guard let message else { return false }
        return !message.hasPrefix("更新于") && !message.hasPrefix("正在显示缓存")
    }
}

private struct CategoryChip: View {
    let category: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        if selected {
            chip.buttonStyle(.glassProminent)
        } else {
            chip.buttonStyle(.glass)
        }
    }

    private var chip: some View {
        Button(action: action) {
            Text(category.map(ReaderTheme.categoryName) ?? "全部类型")
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 6)
                .frame(minHeight: 44)
        }
        .buttonBorderShape(.capsule)
        .tint(ReaderTheme.accent)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ArticleSkeletonRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                RoundedRectangle(cornerRadius: 4).frame(width: 52, height: 12)
                Spacer()
                RoundedRectangle(cornerRadius: 4).frame(width: 64, height: 12)
            }
            RoundedRectangle(cornerRadius: 4).frame(height: 18)
            RoundedRectangle(cornerRadius: 4).frame(maxWidth: 220).frame(height: 18)
            RoundedRectangle(cornerRadius: 4).frame(height: 12)
            RoundedRectangle(cornerRadius: 4).frame(maxWidth: 150).frame(height: 12)
            RoundedRectangle(cornerRadius: 4).frame(width: 80, height: 12)
        }
        .foregroundStyle(.quaternary)
        .padding(.vertical, 12)
        .accessibilityHidden(true)
    }
}
