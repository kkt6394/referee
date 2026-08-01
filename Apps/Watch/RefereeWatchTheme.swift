import SwiftUI

enum RefereeWatchTheme {
    enum Colors {
        static let background = Color.black
        static let surface = Color(white: 0.10)
        static let elevatedSurface = Color(white: 0.16)
        static let primaryText = Color.white
        static let secondaryText = Color(white: 0.72)
        static let outline = Color.white.opacity(0.12)
        static let accent = Color(red: 0.20, green: 0.55, blue: 1.00)
        static let success = Color(red: 0.24, green: 0.82, blue: 0.45)
        static let warning = Color(red: 1.00, green: 0.63, blue: 0.16)
        static let danger = Color(red: 1.00, green: 0.27, blue: 0.25)
        static let card = Color(red: 1.00, green: 0.82, blue: 0.20)
    }

    enum Layout {
        static let compactSpacing: CGFloat = 4
        static let standardSpacing: CGFloat = 8
        static let sectionSpacing: CGFloat = 10
        static let horizontalPadding: CGFloat = 8
        static let minimumTouchTarget: CGFloat = 44
        static let liveActionHeight: CGFloat = 52
        static let cornerRadius: CGFloat = 14
    }

    enum Typography {
        static let period = Font.caption2.weight(.heavy)
        static let clock = Font.system(size: 40, weight: .bold, design: .rounded)
        static let score = Font.system(size: 26, weight: .bold, design: .rounded)
        static let team = Font.caption2.weight(.semibold)
        static let status = Font.caption2.weight(.semibold)
        static let action = Font.caption2.weight(.heavy)
    }
}
