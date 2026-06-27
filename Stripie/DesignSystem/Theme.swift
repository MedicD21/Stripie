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

// MARK: - Color extensions (map to asset catalog)

extension Color {
    static let stripieAccent      = Color("StripieAccent", bundle: nil)
    static let stripieBackground  = Color("StripieBackground", bundle: nil)
    static let stripieCard        = Color("StripieCard", bundle: nil)
}
