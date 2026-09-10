import SwiftUI

struct MiniPlayerView: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(Navigator.self) private var navigator

    var body: some View {
        if let item = player.current {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Artwork thumbnail with rounded corners
                    Artwork(url: item.effectiveThumbnailUrl, size: 42, corner: 10)

                    // Song title & artist
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)

                        Text(item.displaySubtitle() ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Previous Track Button
                    Button {
                        player.previous()
                    } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 32, height: 32)
                    }
                    .disabled(!player.hasPrevious)
                    .opacity(player.hasPrevious ? 1.0 : 0.35)
                    .accessibilityLabel("Previous track")

                    // Play / Pause Button
                    Button {
                        player.togglePlayPause()
                    } label: {
                        PlayPauseLoadingButton(
                            isPlaying: player.isPlaying,
                            isLoading: player.isLoading,
                            iconSize: 18,
                            frameSize: 32,
                            ringLineWidth: 2
                        )
                    }
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                    // Next Track Button
                    Button {
                        player.next()
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 32, height: 32)
                    }
                    .disabled(!player.hasNext)
                    .opacity(player.hasNext ? 1.0 : 0.35)
                    .accessibilityLabel("Next track")
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)

                // Sleek progress bar across the bottom
                GeometryReader { geo in
                    let progress = player.duration > 0 ? min(1.0, max(0.0, player.currentTime / player.duration)) : 0.0
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 2.5)

                        Capsule()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: max(0, geo.size.width * progress), height: 2.5)
                    }
                }
                .frame(height: 2.5)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
            .background(
                Color(red: 0.16, green: 0.16, blue: 0.18).opacity(0.96),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                    navigator.showPlayer = true
                }
            }
        }
    }
}
