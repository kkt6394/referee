import SwiftUI

enum RefereeTheme {
    enum Colors {
        static let background = Color(uiColor: .systemGroupedBackground)
        static let surface = Color(uiColor: .secondarySystemGroupedBackground)
        static let primaryText = Color.primary
        static let secondaryText = Color.secondary
        static let accent = Color(red: 0.08, green: 0.42, blue: 0.94)
        static let success = Color.green
        static let warning = Color.orange
        static let blocking = Color.red
    }

    enum Spacing {
        static let compact: CGFloat = 6
        static let standard: CGFloat = 12
        static let comfortable: CGFloat = 18
        static let spacious: CGFloat = 24
    }

    enum CornerRadius {
        static let control: CGFloat = 12
        static let card: CGFloat = 20
        static let hero: CGFloat = 26
    }

    enum Typography {
        static let section = Font.headline.weight(.semibold)
        static let cardTitle = Font.title3.weight(.bold)
        static let status = Font.subheadline.weight(.semibold)
        static let supporting = Font.callout
        static let hero = Font.system(size: 56, weight: .bold, design: .rounded)
    }
}

private struct RefereeCardModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RefereeTheme.Colors.surface,
                        in: RoundedRectangle(cornerRadius: RefereeTheme.CornerRadius.card,
                                             style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: RefereeTheme.CornerRadius.card, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.05), radius: 12, y: 5)
    }
}

extension View {
    func refereeCard(padding: CGFloat = RefereeTheme.Spacing.comfortable) -> some View {
        modifier(RefereeCardModifier(padding: padding))
    }

    func refereeGroupedSurface() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(RefereeTheme.Colors.background)
            .tint(RefereeTheme.Colors.accent)
    }
}
