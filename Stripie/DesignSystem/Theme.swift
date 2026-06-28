import SwiftUI

/// Design tokens for Stripie. Extend this as the design system matures.
enum StripieTheme {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs:  CGFloat = 8
        static let sm:  CGFloat = 12
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum CornerRadius {
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let pill: CGFloat = 999
    }

    enum Font {
        static let displayLarge = SwiftUI.Font.system(size: 56, weight: .thin, design: .rounded)
        static let displayMedium = SwiftUI.Font.system(size: 40, weight: .light, design: .rounded)
        static let heading = SwiftUI.Font.title2.weight(.semibold)
        static let body = SwiftUI.Font.body
        static let caption = SwiftUI.Font.caption
    }
}

// MARK: - Palette (ported from The Good Kitchen mobile app: mobile/lib/theme.ts)
//
// Each token resolves automatically for light/dark via the active UITraitCollection,
// so SwiftUI views pick up the right value from `@Environment(\.colorScheme)` with no
// per-view branching. Hex values are kept identical to the mobile app so the two
// apps share one visual identity.

private enum TGKPalette {
    // (light, dark) hex pairs — mirrors LIGHT_COLORS / DARK_COLORS in mobile/lib/theme.ts
    static let page          = (light: "DDEADE", dark: "1F2F3D")
    static let surface       = (light: "E8F3E9", dark: "1B2D3D")
    static let card          = (light: "F0F7F0", dark: "24394C")
    static let cardAlt       = (light: "E5EFE6", dark: "2A4358")
    static let text          = (light: "0A1C0E", dark: "EDF5FB")
    static let textMuted     = (light: "34543C", dark: "AFC2D3")
    static let border        = (light: "A8C1AA", dark: "3D556B")
    static let inputBg       = (light: "FFFFFF", dark: "1B2D3D")
    static let inputBorder   = (light: "B8CEB9", dark: "4B6478")
    static let placeholder   = (light: "5A7460", dark: "8EA6B8")
    static let primary       = (light: "7BB289", dark: "F2A067")
    static let primaryText   = (light: "1C120A", dark: "1C120A")
    static let danger        = (light: "B91C1C", dark: "F87171")
    static let chipBg        = (light: "D8E7DC", dark: "2A4358")
    static let gold          = (light: "4F825D", dark: "F2A067")
    static let success       = (light: "16A34A", dark: "4ADE80")
    static let warning       = (light: "D97706", dark: "FBBF24")
    static let income        = (light: "16A34A", dark: "4ADE80")
    static let expense       = (light: "DC2626", dark: "F87171")
    static let tgkGreen       = (light: "4F825D", dark: "7FB069")
    static let tgkBlue        = (light: "579CC3", dark: "579CC3")
}

extension Color {
    /// Builds a Color that resolves a (light, dark) hex pair per the active appearance.
    fileprivate static func tgkDynamic(_ pair: (light: String, dark: String)) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? pair.dark : pair.light)
        })
    }

    // Surfaces
    static let tgkPage        = tgkDynamic(TGKPalette.page)
    static let tgkSurface     = tgkDynamic(TGKPalette.surface)
    static let tgkCard        = tgkDynamic(TGKPalette.card)
    static let tgkCardAlt     = tgkDynamic(TGKPalette.cardAlt)

    // Text
    static let tgkText        = tgkDynamic(TGKPalette.text)
    static let tgkTextMuted   = tgkDynamic(TGKPalette.textMuted)
    static let tgkPlaceholder = tgkDynamic(TGKPalette.placeholder)

    // Lines & inputs
    static let tgkBorder      = tgkDynamic(TGKPalette.border)
    static let tgkInputBg     = tgkDynamic(TGKPalette.inputBg)
    static let tgkInputBorder = tgkDynamic(TGKPalette.inputBorder)

    // Brand / accent
    static let tgkPrimary     = tgkDynamic(TGKPalette.primary)
    static let tgkPrimaryText = tgkDynamic(TGKPalette.primaryText)
    static let tgkChipBg      = tgkDynamic(TGKPalette.chipBg)
    static let tgkGold        = tgkDynamic(TGKPalette.gold)
    static let tgkGreen       = tgkDynamic(TGKPalette.tgkGreen)
    static let tgkBlue        = tgkDynamic(TGKPalette.tgkBlue)

    // Semantic status
    static let tgkDanger      = tgkDynamic(TGKPalette.danger)
    static let tgkSuccess     = tgkDynamic(TGKPalette.success)
    static let tgkWarning     = tgkDynamic(TGKPalette.warning)
    static let tgkIncome      = tgkDynamic(TGKPalette.income)
    static let tgkExpense     = tgkDynamic(TGKPalette.expense)

    // Back-compat aliases for existing call sites
    static let stripieAccent     = tgkPrimary
    static let stripieBackground = tgkPage
    static let stripieCard       = tgkCard
}

// MARK: - Hex initializer

extension UIColor {
    /// Creates a UIColor from a 6-digit RGB hex string (no leading `#`).
    fileprivate convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
