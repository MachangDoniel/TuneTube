import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(StoreManager.self) private var store
    @Environment(Navigator.self) private var navigator

    @Query(sort: \LocalPlaylist.createdAt) private var playlists: [LocalPlaylist]

    @State private var showPaywall = false
    @State private var showNewPlaylist = false
    @State private var playlistToEdit: LocalPlaylist?
    @State private var freeLimit = RemoteConfig.fallback.freePlaylistLimit

    private var library: LibraryStore { LibraryStore(context: context) }

    var body: some View {
        VStack(spacing: 0) {
            header

            if playlists.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(playlists) { playlist in
                        Button {
                            navigator.push(.localPlaylist(id: playlist.id))
                        } label: {
                            playlistRow(playlist)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.white.opacity(0.06))
                        .swipeActions(edge: .trailing) {
                            if !playlist.isDefault {
                                Button(role: .destructive) {
                                    library.delete(playlist)
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                            Button {
                                playlistToEdit = playlist
                            } label: { Label("Edit", systemImage: "pencil") }
                            .tint(Theme.accent)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .task {
            library.ensureDefaultPlaylist()
            if let config = try? await APIClient.shared.config() {
                freeLimit = config.freePlaylistLimit
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environment(store)
                .presentationDetents([.height(560)])
        }
        .sheet(isPresented: $showNewPlaylist) {
            PlaylistCustomizationSheet(defaultColorHex: library.distinctColor(for: "heart.fill")) { name, icon, color in
                library.createPlaylist(named: name, iconName: icon, colorHex: color)
            }
        }
        .sheet(item: $playlistToEdit) { playlist in
            PlaylistCustomizationSheet(playlist: playlist) { name, icon, color in
                library.updatePlaylist(playlist, name: name, iconName: icon, colorHex: color)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Library")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your Playlists")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button(action: attemptCreate) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent.opacity(0.85), in: Circle())
            }
            .accessibilityLabel("New playlist")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// The single paywall trigger: a free user already has Favourites, so any
    /// second playlist requires Pro.
    private func attemptCreate() {
        if library.canCreatePlaylist(isPro: store.isPro, freeLimit: freeLimit) {
            showNewPlaylist = true
        } else {
            showPaywall = true
        }
    }

    private func playlistRow(_ playlist: LocalPlaylist) -> some View {
        let icon = playlist.iconName.isEmpty ? (playlist.isDefault ? "heart.fill" : "music.note.list") : playlist.iconName
        let color = Color(hex: playlist.colorHex.isEmpty ? (playlist.isDefault ? "#FF2D55" : "#AF52DE") : playlist.colorHex)

        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 46, height: 46)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(playlist.tracks.count) \(playlist.tracks.count == 1 ? "song" : "songs")")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "music.note")
                .font(.system(size: 30))
                .foregroundStyle(Theme.accent)
                .frame(width: 78, height: 78)
                .background(Theme.surface, in: Circle())
            Text("Your music, your way")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("Playlists you create will appear here.\nTap + to build your first one.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
