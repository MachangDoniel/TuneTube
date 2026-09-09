import SwiftData
import SwiftUI

/// Detail screen for a user-created playlist (as opposed to a YouTube one).
struct LocalPlaylistView: View {
    let playlistId: UUID

    @Environment(\.modelContext) private var context
    @Environment(PlayerEngine.self) private var player
    @Environment(Navigator.self) private var navigator
    @Query private var playlists: [LocalPlaylist]

    init(playlistId: UUID) {
        self.playlistId = playlistId
        _playlists = Query(filter: #Predicate<LocalPlaylist> { $0.id == playlistId })
    }

    private var playlist: LocalPlaylist? { playlists.first }
    private var library: LibraryStore { LibraryStore(context: context) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: (playlist?.isDefault ?? false) ? "heart.fill" : "music.note.list")
                    .font(.system(size: 48))
                    .foregroundStyle((playlist?.isDefault ?? false) ? .pink : Theme.accent)
                    .frame(width: 160, height: 160)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 8)

                Text(playlist?.name ?? "")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                let tracks = playlist?.orderedTracks ?? []

                if tracks.isEmpty {
                    Text("No songs yet.\nUse “Add to Playlist” from any track.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 40)
                } else {
                    Button {
                        let items = tracks.map(\.asMediaItem)
                        if let first = items.first {
                            navigator.open(first, within: items, player: player)
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
                        let item = track.asMediaItem
                        TrackRow(item: item) {
                            navigator.open(item, within: tracks.map(\.asMediaItem), player: player)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                library.remove(track)
                            } label: { Label("Remove", systemImage: "trash") }
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}
