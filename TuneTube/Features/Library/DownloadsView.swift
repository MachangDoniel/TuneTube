import SwiftUI

struct DownloadsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Navigator.self) private var navigator
    @Environment(PlayerEngine.self) private var player

    @State private var downloadManager = DownloadManager.shared
    @State private var searchQuery = ""
    @State private var showDeleteAllAlert = false
    @State private var trackToRemove: DownloadedTrack?
    @State private var itemToAddToPlaylist: MediaItem?

    private var tracks: [DownloadedTrack] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return downloadManager.downloadedTracks
        }
        return downloadManager.downloadedTracks.filter { track in
            track.title.localizedCaseInsensitiveContains(searchQuery) ||
            (track.artistName?.localizedCaseInsensitiveContains(searchQuery) ?? false) ||
            (track.albumName?.localizedCaseInsensitiveContains(searchQuery) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if downloadManager.downloadedTracks.isEmpty {
                emptyState
            } else {
                searchBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSummary

                        if !tracks.isEmpty {
                            actionButtons
                        }

                        trackList
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle("Downloaded")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !downloadManager.downloadedTracks.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteAllAlert = true
                        } label: {
                            Label("Remove All Downloads", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
        }
        .confirmationDialog(
            "Remove All Downloads",
            isPresented: $showDeleteAllAlert,
            titleVisibility: .visible
        ) {
            Button("Remove All (\(downloadManager.downloadedTracks.count) songs)", role: .destructive) {
                downloadManager.deleteAllDownloads()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all \(downloadManager.formattedTotalStorage) of offline music from your device.")
        }
        .confirmationDialog(
            "Remove Download",
            isPresented: Binding(
                get: { trackToRemove != nil },
                set: { if !$0 { trackToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let track = trackToRemove {
                Button("Remove Download", role: .destructive) {
                    downloadManager.deleteDownload(for: track.id)
                    trackToRemove = nil
                }
            }
            Button("Cancel", role: .cancel) {
                trackToRemove = nil
            }
        } message: {
            if let track = trackToRemove {
                Text("Remove “\(track.title)” (\(track.formattedSize)) from offline storage?")
            }
        }
        .sheet(item: $itemToAddToPlaylist) { item in
            AddToPlaylistSheet(item: item)
        }
        .onAppear {
            downloadManager.syncWithDisk()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
                .font(.system(size: 14))

            TextField("Filter downloaded songs...", text: $searchQuery)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .autocorrectionDisabled()

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                        .font(.system(size: 15))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Header Summary

    private var headerSummary: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color(hex: "#007AFF"))
                .frame(width: 54, height: 54)
                .background(Color(hex: "#007AFF").opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Offline Storage")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text("\(downloadManager.downloadedTracks.count) songs • \(downloadManager.formattedTotalStorage) used")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - Action Buttons (Play All / Shuffle)

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                let items = tracks.map(\.asMediaItem)
                if let first = items.first {
                    navigator.open(first, within: items, player: player)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Play All")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.plain)

            Button {
                let items = tracks.map(\.asMediaItem)
                if let random = items.randomElement() {
                    if !player.isShuffled { player.toggleShuffle() }
                    navigator.open(random, within: items, player: player)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Shuffle")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Track List

    private var trackList: some View {
        LazyVStack(spacing: 2) {
            ForEach(tracks) { track in
                let item = track.asMediaItem
                downloadRow(track: track, item: item)
                    .contextMenu {
                        Button {
                            navigator.open(item, within: tracks.map(\.asMediaItem), player: player)
                        } label: { Label("Play", systemImage: "play.fill") }

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

                        Button(role: .destructive) {
                            trackToRemove = track
                        } label: { Label("Remove Download", systemImage: "trash") }
                    }
            }
        }
    }

    private func downloadRow(track: DownloadedTrack, item: MediaItem) -> some View {
        HStack(spacing: 8) {
            // Main tap area to play the track
            Button {
                navigator.open(item, within: tracks.map(\.asMediaItem), player: player)
            } label: {
                HStack(spacing: 12) {
                    CachedImage(url: item.thumbnailUrl, contentMode: .fill) {
                        Rectangle()
                            .fill(Theme.surface)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Theme.textSecondary)
                            )
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            if let artist = track.artistName ?? track.subtitle {
                                Text(artist)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }

                            Text("•")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textSecondary.opacity(0.6))

                            Text(track.formattedSize)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary.opacity(0.8))
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Trailing actions: Download badge (with confirm) & More menu
            HStack(spacing: 2) {
                Button {
                    trackToRemove = track
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "#007AFF"))
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        navigator.open(item, within: tracks.map(\.asMediaItem), player: player)
                    } label: { Label("Play", systemImage: "play.fill") }

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

                    Button(role: .destructive) {
                        trackToRemove = track
                    } label: { Label("Remove Download", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
                .frame(width: 84, height: 84)
                .background(Theme.surface, in: Circle())

            Text("No Downloads Yet")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("Download songs to listen offline anytime\nwithout using cellular data or Wi-Fi.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
