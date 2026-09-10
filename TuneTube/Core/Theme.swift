import SwiftUI

/// Dark, purple-tinted palette matching the reference design.
enum Theme {
    static let accent      = Color(red: 0.42, green: 0.36, blue: 0.95)
    static let background  = Color(red: 0.04, green: 0.03, blue: 0.08)
    static let surface     = Color(red: 0.09, green: 0.08, blue: 0.13)
    static let surfaceHigh = Color(red: 0.14, green: 0.13, blue: 0.19)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)

    /// The subtle purple wash behind the Home and Search screens.
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.13, green: 0.08, blue: 0.26), background],
            startPoint: .top,
            endPoint: .center
        )
    }

    static let cardSize: CGFloat = 160
    static let cardCorner: CGFloat = 12
}

extension View {
    /// Full-bleed screen background used by every tab.
    func screenBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ZStack {
                    Theme.background
                    Theme.backgroundGradient
                }
                .ignoresSafeArea()
            )
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 45, 85) // Fallback to pink
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

