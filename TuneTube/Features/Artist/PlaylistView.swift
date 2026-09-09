import SwiftUI

@MainActor
@Observable
final class PlaylistViewModel {
    private(set) var detail: PlaylistDetail?
    private(set) var isLoading = true

    func load(_ id: String) async {
        isLoading = true
        detail = try? await APIClient.shared.playlist(id)
        isLoading = false
    }
}

struct PlaylistView: View {
    let playlistId: String
    let title: String

    @State private var model = PlaylistViewModel()
    @Environment(PlayerEngine.self) private var player
    @Environment(Navigator.self) private var navigator

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Artwork(url: model.detail?.thumbnailUrl, size: 180)
                    .padding(.top, 8)

                Text(model.detail?.title ?? title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if let tracks = model.detail?.tracks, !tracks.isEmpty {
                    Button {
                        if let first = tracks.first(where: { $0.isPlayable }) {
                            navigator.open(first, within: tracks, player: player)
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .padding(.horizontal, 16)

                    ForEach(tracks) { track in
                        TrackRow(item: track) {
                            navigator.open(track, within: tracks, player: player)
                        }
                    }
                } else if model.isLoading {
                    ProgressView().tint(Theme.textSecondary).padding(.top, 40)
                }
            }
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(playlistId) }
    }
}
