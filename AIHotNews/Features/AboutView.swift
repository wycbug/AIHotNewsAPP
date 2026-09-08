import SwiftUI

struct AboutView: View {
    let container: AppContainer
    @State private var isClearing = false
    @State private var cacheMessage: String?
    @State private var confirmClear = false

    var body: some View {
        List {
            Section("关于") {
                Text("AI 圈速览").font(.title2.bold())
                Text("本应用不是 AIHOT 官方产品。")
                Text("本应用读取 aihot.news 的公开只读接口，展示摘要、推荐理由与链接。标题翻译和摘要可能由自动化系统生成，重要事实请打开原文核对。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("免费 · 无广告 · 无登录")
                Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                    .font(.caption).foregroundStyle(.secondary)
                Link("公开使用规则", destination: URL(string: "https://aihot.news/terms")!)
                Link("数据接入说明", destination: URL(string: "https://aihot.news/agent")!)
            }
            Section {
                if let notice = container.cacheNotice {
                    Text(notice).font(.footnote).foregroundStyle(.secondary)
                }
                Button("清除网络缓存", role: .destructive) { confirmClear = true }
                    .disabled(isClearing)
                if isClearing { ProgressView() }
                if let cacheMessage { Text(cacheMessage).font(.footnote) }
            } header: {
                Text("本机缓存")
            } footer: {
                Text("缓存仅供本机阅读，不提供全库镜像或批量导出。清除后已打开的页面可继续显示，再次访问时重新请求。")
            }
            Section("当前版本范围") {
                Text("已提供资讯、热点事件和日报的基础浏览。本机收藏与已读的数据结构已准备，收藏操作、已读标记、同步和后台刷新尚未开放。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("我的")
        .confirmationDialog("清除本机网络缓存？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清除缓存", role: .destructive) {
                Task {
                    isClearing = true
                    defer { isClearing = false }
                    do {
                        try await container.repository.clearCache()
                        cacheMessage = "网络缓存已清除。"
                    } catch {
                        cacheMessage = "清除失败：\(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
