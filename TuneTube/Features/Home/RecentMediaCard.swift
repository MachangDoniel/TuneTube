import SwiftUI

/// Distinct horizontal pill-style visualization card for Recently Played tracks.
///
/// Designed with a compact horizontal layout (image on the left, titles in the center,
/// play badge on the right) to visually differentiate it from the standard square shelf cards.
struct RecentMediaCard: View {
    let item: MediaItem
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Artwork(url: item.thumbnailUrl, size: 48, corner: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    if let sub = item.displaySubtitle() {
                        Text(sub)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Theme.accent.opacity(0.9), in: Circle())
            }
            .padding(6)
            .frame(width: 220, height: 60)
            .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recent: \(item.title)")
    }
}
