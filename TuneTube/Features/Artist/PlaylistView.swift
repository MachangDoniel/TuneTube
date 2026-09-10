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
                    VStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { _ in
                            PlaylistTrackSkeleton()
                        }
                    }
                    .padding(.top, 12)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 38))
                            .foregroundStyle(Theme.textSecondary)
                        Text("No songs available")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(playlistId) }
    }
}

struct PlaylistTrackSkeleton: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.surface)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.surface)
                    .frame(width: 160, height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.surface)
                    .frame(width: 100, height: 12)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .opacity(pulse ? 0.45 : 0.85)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
    }
}
