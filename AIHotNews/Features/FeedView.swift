import SwiftUI

struct FeedView: View {
    @Bindable var model: FeedViewModel

    var body: some View {
        List {
            Section {
                Picker("时间窗", selection: $model.query.window) {
                    Text("24 小时").tag(ItemsWindow.day)
                    Text("7 天").tag(ItemsWindow.week)
                }
                .pickerStyle(.segmented)
                Picker("内容范围", selection: $model.query.mode) {
                    Text("精选").tag(ItemsMode.selected)
                    Text("公开池").tag(ItemsMode.all)
                }
                .pickerStyle(.segmented)
                Picker("分类", selection: $model.query.category) {
                    Text("全部类型").tag(String?.none)
                    Text("模型").tag(String?("ai-models"))
                    Text("产品").tag(String?("ai-products"))
                    Text("行业").tag(String?("industry"))
                    Text("论文").tag(String?("paper"))
                    Text("技巧").tag(String?("tip"))
                }
            } footer: {
                Text("仅浏览最近 7 天；公开池不是全站历史。搜索沿用当前筛选。")
            }
            if let validation = model.searchValidation {
                Text(validation).foregroundStyle(.secondary)
            } else {
                LoadStatusView(isLoading: model.isLoading, message: model.message, retryAt: model.retryAt) {
                    await model.load(reload: true)
                }
                if model.items.isEmpty && !model.isLoading {
                    ContentUnavailableView("暂无资讯", systemImage: "newspaper", description: Text("可重试，或调整时间窗和筛选条件。"))
                }
                ForEach(model.items, id: \.id) { item in
                    NavigationLink {
                        ArticleDetailView(
                            title: item.title,
                            originalTitle: item.originalTitle,
                            summary: item.summary,
                            reason: item.reason,
                            source: item.source.name,
                            originalURL: item.links.original,
                            aihotURL: item.links.aihot
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title).font(.headline).lineLimit(3)
                            if let summary = item.summary {
                                Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                            HStack {
                                Text(item.source.name)
                                Spacer()
                                Text(item.discoveredAt, style: .relative)
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
                if let pageError = model.pageError {
                    Text(pageError).font(.footnote).foregroundStyle(.secondary)
                }
                if model.nextCursor != nil {
                    Button {
                        Task { await model.loadMore() }
                    } label: {
                        if model.isPaging {
                            ProgressView("正在加载更多…")
                        } else {
                            Text(model.pageError == nil ? "加载更多" : "重试加载更多")
                        }
                    }
                    .disabled(model.isPaging || model.isLoading)
                } else if !model.items.isEmpty {
                    Text("当前可用内容已展示；刷新可检查更新。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("精选")
        .searchable(text: $model.searchText, prompt: "搜索最近内容（2–200 字）")
        .task(id: model.request) { await model.load(debounce: model.request.q != nil) }
        .refreshable { await model.load(reload: true) }
        .toolbar {
            Button { Task { await model.load(reload: true) } } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isLoading)
        }
    }
}
