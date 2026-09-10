import SwiftData
import SwiftUI

/// Reached from the player's "Add to Playlist". Free users see only Favourites;
/// "New Playlist" here goes through the same gate as the Library tab.
struct AddToPlaylistSheet: View {
    let item: MediaItem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreManager.self) private var store
    @Query(sort: \LocalPlaylist.createdAt) private var playlists: [LocalPlaylist]

    @State private var showPaywall = false
    @State private var showNewPlaylist = false
    @State private var freeLimit = RemoteConfig.fallback.freePlaylistLimit

    private var library: LibraryStore { LibraryStore(context: context) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(playlists) { playlist in
                        let icon = playlist.iconName.isEmpty ? (playlist.isDefault ? "heart.fill" : "music.note.list") : playlist.iconName
                        let color = Color(hex: playlist.colorHex.isEmpty ? (playlist.isDefault ? "#FF2D55" : "#AF52DE") : playlist.colorHex)

                        Button {
                            library.add(item, to: playlist)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: icon)
                                    .foregroundStyle(color)
                                    .frame(width: 26)
                                Text(playlist.name).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if library.contains(item, in: playlist) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        .listRowBackground(Theme.surface)
                    }
                }

                Section {
                    Button {
                        if library.canCreatePlaylist(isPro: store.isPro, freeLimit: freeLimit) {
                            showNewPlaylist = true
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        Label("New Playlist", systemImage: "plus")
                            .foregroundStyle(Theme.accent)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            library.ensureDefaultPlaylist()
            if let config = try? await APIClient.shared.config() {
                freeLimit = config.freePlaylistLimit
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environment(store).presentationDetents([.height(560)])
        }
        .sheet(isPresented: $showNewPlaylist) {
            PlaylistCustomizationSheet(defaultColorHex: library.distinctColor(for: "heart.fill")) { name, icon, color in
                let playlist = library.createPlaylist(named: name, iconName: icon, colorHex: color)
                library.add(item, to: playlist)
                dismiss()
            }
        }
    }
}
