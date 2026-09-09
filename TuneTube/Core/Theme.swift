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
        background(
            ZStack {
                Theme.background
                Theme.backgroundGradient
            }
            .ignoresSafeArea()
        )
    }
}
