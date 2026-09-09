import MediaPlayer
import SwiftData
import SwiftUI
import YouTubePlayerKit

struct PlayerView: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss

    @State private var scrubValue: Double = 0
    @State private var showActions = false
    @State private var showAddToPlaylist = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .accessibilityLabel("Close player")
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer(minLength: 0)

            // The embed stays visible and unobstructed. This is both a YouTube
            // embed requirement and the App Review position: we are not
            // re-hosting content, we are showing YouTube's own player.
            YouTubePlayerView(player.player) { state in
                switch state {
                case .idle:  Color.black.overlay(ProgressView().tint(.white))
                case .ready: EmptyView()
                case .error: Color.black.overlay(
                    Text("Can't play this track")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                )
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)

            Spacer(minLength: 0)

            VStack(spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.current?.title ?? "")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                        Text(player.current?.displaySubtitle() ?? "")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button { showActions = true } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .accessibilityLabel("More options")
                }

                scrubber

                HStack(spacing: 56) {
                    Button { player.previous() } label: {
                        Image(systemName: "backward.end.fill").font(.system(size: 26))
                    }
                    .accessibilityLabel("Previous track")

                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 34))
                            .frame(width: 40)
                    }
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                    Button { player.next() } label: {
                        Image(systemName: "forward.end.fill").font(.system(size: 26))
                    }
                    .accessibilityLabel("Next track")
                }
                .foregroundStyle(Theme.textPrimary)

                // System volume, not player volume: iOS makes the HTML5 volume
                // property read-only, so binding a slider to the embed does nothing.
                SystemVolumeSlider()
                    .frame(height: 28)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.14, green: 0.14, blue: 0.15).ignoresSafeArea())
        .confirmationDialog("", isPresented: $showActions) {
            Button("Go to Artist") { goToArtist() }
            Button("Add to Playlist") { showAddToPlaylist = true }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showAddToPlaylist) {
            if let item = player.current {
                AddToPlaylistSheet(item: item)
            }
        }
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { player.isScrubbing ? scrubValue : player.currentTime },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    player.isScrubbing = editing
                    // Seek on release only; seeking per-frame thrashes the iframe.
                    if !editing { player.seek(to: scrubValue) }
                }
            )
            .tint(.white)

            HStack {
                Text(Self.time(player.isScrubbing ? scrubValue : player.currentTime))
                Spacer()
                Text(Self.time(player.duration))
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private func goToArtist() {
        guard let name = player.current?.artistName else { return }
        dismiss()
        navigator.selectedTab = .search
        navigator.pendingArtistSearch = name
    }

    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

/// `MPVolumeView` wrapper — the only supported way to change output volume.
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.tintColor = .white
        return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
