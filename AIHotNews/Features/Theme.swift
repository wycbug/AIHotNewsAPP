import SwiftUI

@MainActor
enum ReaderTheme {
    static let accent = Color.accentColor
    static let cornerRadius: CGFloat = 8
    static let readingWidth: CGFloat = 760
    static let spacing: CGFloat = 16

    static func background(for scheme: ColorScheme) -> Color {
        if scheme == .light {
            return Color(red: 247 / 255, green: 246 / 255, blue: 243 / 255)
        }
#if os(iOS)
        return Color(uiColor: .systemGroupedBackground)
#else
        return Color(nsColor: .windowBackgroundColor)
#endif
    }

    static func surface(for scheme: ColorScheme) -> Color {
#if os(iOS)
        return Color(uiColor: .secondarySystemGroupedBackground)
#else
        return scheme == .light ? .white : Color(nsColor: .controlBackgroundColor)
#endif
    }

    static func accentForeground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 4 / 255, green: 47 / 255, blue: 46 / 255) : .white
    }

    static func categoryName(_ category: String?) -> String {
        switch category {
        case "ai-models": "模型"
        case "ai-products": "产品"
        case "industry": "行业"
        case "paper": "论文"
        case "tip": "技巧"
        case .some(let value): value
        case .none: "资讯"
        }
    }

    static func categoryColor(_ category: String?) -> Color {
        switch category {
        case "ai-products": .blue
        case "industry": .orange
        case "paper": .indigo
        case "tip": .green
        default: accent
        }
    }
}

private struct ReaderBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
#if os(iOS)
            .listSectionSpacing(16)
#endif
            .scrollContentBackground(.hidden)
            .background(ReaderTheme.background(for: colorScheme).ignoresSafeArea())
            .tint(ReaderTheme.accent)
    }
}

extension View {
    func readerBackground() -> some View {
        modifier(ReaderBackground())
    }
}
