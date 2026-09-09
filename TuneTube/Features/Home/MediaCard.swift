import SwiftUI

/// Square artwork tile used in every horizontal shelf.
///
/// Title and subtitle sit ON the artwork behind a bottom scrim, which is how the
/// reference design reads. The `.fill` + `.clipped()` pairing produces the
/// cropped-video look: YouTube serves 16:9 thumbnails, and squaring them is
/// exactly why the artwork bleeds past the card edges.
struct MediaCard: View {
    let item: MediaItem
    var size: CGFloat = Theme.cardSize
    var onTap: () -> Void

    private var isCircular: Bool { item.kind == .artist }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                Artwork(url: item.thumbnailUrl, size: size,
                        corner: isCircular ? size / 2 : Theme.cardCorner)

                if !isCircular {
                    // Scrim only where text sits, so artwork stays legible.
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.15), .black.opacity(0.8)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
                    .allowsHitTesting(false)
                }

                HStack(alignment: .bottom, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let sub = item.displaySubtitle() {
                            Text(sub)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)

                    Spacer(minLength: 0)

                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Theme.accent.opacity(0.92), in: Circle())
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .frame(width: size, alignment: .leading)
            }
            .frame(width: size, height: size)
            // Artist tiles keep their label outside the circle.
            .overlay(alignment: .bottom) {
                if isCircular {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .frame(width: size)
                        .offset(y: 20)
                }
            }
            .padding(.bottom, isCircular ? 22 : 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title)\(item.displaySubtitle().map { ", \($0)" } ?? "")")
    }
}

struct Artwork: View {
    let url: URL?
    var size: CGFloat
    var corner: CGFloat = Theme.cardCorner

    var body: some View {
        CachedImage(url: url) {
            Theme.surfaceHigh.overlay(
                Image(systemName: "music.note")
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
            )
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}
