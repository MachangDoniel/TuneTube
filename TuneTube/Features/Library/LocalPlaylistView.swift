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
    @State private var showEditSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                let icon = playlist?.iconName.isEmpty == false ? playlist!.iconName : ((playlist?.isDefault ?? false) ? "heart.fill" : "music.note.list")
                let color = Color(hex: playlist?.colorHex.isEmpty == false ? playlist!.colorHex : ((playlist?.isDefault ?? false) ? "#FF2D55" : "#AF52DE"))

                Image(systemName: icon)
                    .font(.system(size: 52))
                    .foregroundStyle(color)
                    .frame(width: 160, height: 160)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(color.opacity(0.35), lineWidth: 1.5)
                    )
                    .shadow(color: color.opacity(0.2), radius: 12, y: 4)
                    .padding(.top, 8)

                Text(playlist?.name ?? "")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                let tracks = playlist?.orderedTracks ?? []

                if tracks.isEmpty {
                    VStack(spacing: 8) {
                        Text("No songs yet.")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Use “Add to Playlist” from any track.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
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
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let p = playlist, !p.isDefault {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showEditSheet = true
                    } label: {
                        Text("Edit")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let p = playlist {
                PlaylistCustomizationSheet(playlist: p) { name, icon, color in
                    library.updatePlaylist(p, name: name, iconName: icon, colorHex: color)
                }
            }
        }
    }
}
