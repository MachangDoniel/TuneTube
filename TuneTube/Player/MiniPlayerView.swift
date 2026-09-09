import SwiftUI

struct MiniPlayerView: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(Navigator.self) private var navigator

    var body: some View {
        if let item = player.current {
            HStack(spacing: 10) {
                Artwork(url: item.thumbnailUrl, size: 38, corner: 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(item.displaySubtitle() ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button { player.previous() } label: {
                    Image(systemName: "backward.end.fill")
                }
                .accessibilityLabel("Previous track")

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 22)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button { player.next() } label: {
                    Image(systemName: "forward.end.fill")
                }
                .accessibilityLabel("Next track")
            }
            .font(.system(size: 17))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surfaceHigh)
            .contentShape(Rectangle())
            .onTapGesture { navigator.showPlayer = true }
        }
    }
}
