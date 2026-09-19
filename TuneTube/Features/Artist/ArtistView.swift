import SwiftUI

@MainActor
@Observable
final class ArtistViewModel {
    private(set) var detail: ArtistDetail?
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    func load(_ browseId: String) async {
        isLoading = true
        do { detail = try await APIClient.shared.artist(browseId) }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

struct ArtistView: View {
    let browseId: String
    let name: String

    @State private var model = ArtistViewModel()
    @State private var itemToAddToPlaylist: MediaItem?
    @State private var itemToRemoveDownload: MediaItem?
    @Environment(PlayerEngine.self) private var player
    @Environment(Navigator.self) private var navigator

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Artwork(url: model.detail?.thumbnailUrl, size: 160, corner: 80)
                    .padding(.top, 8)

                Text(model.detail?.name ?? name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                if let subs = model.detail?.subscribers {
                    Text(subs)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }

                if model.isLoading && model.detail == nil {
                    VStack(spacing: 8) {
                        ForEach(0..<5, id: \.self) { _ in
                            PlaylistTrackSkeleton()
                        }
                    }
                    .padding(.top, 16)
                }

                ForEach(model.detail?.shelves ?? []) { shelf in
                    if shelf.items.contains(where: { $0.isPlayable }) {
                        // Song shelves read better as a list, with the album as
                        // the subtitle (matching how artist pages present tracks).
                        VStack(alignment: .leading, spacing: 6) {
                            Text(shelf.title)
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                            ForEach(shelf.items) { item in
                                TrackRow(item: item,
                                         subtitlePreference: .album,
                                         trailingIcon: "plus.circle") {
                                    navigator.open(item, within: shelf.items, player: player)
                                } trailingMenu: {
                                    AnyView(
                                        Group {
                                            Button {
                                                player.playNext(item)
                                            } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }

                                            Button {
                                                player.addToQueue(item)
                                            } label: { Label("Add to Queue", systemImage: "text.badge.plus") }

                                            Button {
                                                itemToAddToPlaylist = item
                                            } label: { Label("Add to Playlist", systemImage: "plus.rectangle.on.folder") }

                                            Divider()

                                            if DownloadManager.shared.isDownloaded(item.id) {
                                                Button(role: .destructive) {
                                                    itemToRemoveDownload = item
                                                } label: { Label("Remove Download", systemImage: "trash") }
                                            } else {
                                                Button {
                                                    DownloadManager.shared.startDownload(item: item)
                                                } label: { Label("Download", systemImage: "arrow.down.circle") }
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    } else {
                        ShelfRow(shelf: shelf) { item in
                            navigator.open(item, within: shelf.items, player: player)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .confirmationDialog(
            "Remove Download",
            isPresented: Binding(
                get: { itemToRemoveDownload != nil },
                set: { if !$0 { itemToRemoveDownload = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = itemToRemoveDownload {
                Button("Remove Download", role: .destructive) {
                    DownloadManager.shared.deleteDownload(for: item.id)
                    itemToRemoveDownload = nil
                }
            }
            Button("Cancel", role: .cancel) {
                itemToRemoveDownload = nil
            }
        } message: {
            if let item = itemToRemoveDownload {
                if let track = DownloadManager.shared.track(for: item.id) {
                    Text("Remove “\(item.title)” (\(track.formattedSize)) from offline storage?")
                } else {
                    Text("Remove “\(item.title)” from offline storage?")
                }
            }
        }
        .sheet(item: $itemToAddToPlaylist) { item in
            AddToPlaylistSheet(item: item)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(browseId) }
    }
}
