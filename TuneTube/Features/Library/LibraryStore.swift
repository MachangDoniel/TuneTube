import Foundation
import SwiftData

/// Library rules in one place, so the paywall gate can't drift between the
/// Library tab and the "Add to Playlist" sheet.
@MainActor
struct LibraryStore {
    static let defaultPlaylistName = "Favourites"

    let context: ModelContext

    /// Guarantees the free-tier playlist exists. Safe to call on every launch.
    @discardableResult
    func ensureDefaultPlaylist() -> LocalPlaylist {
        if let existing = try? context.fetch(
            FetchDescriptor<LocalPlaylist>(predicate: #Predicate { $0.isDefault })
        ).first {
            return existing
        }
        let favourites = LocalPlaylist(name: Self.defaultPlaylistName, isDefault: true)
        context.insert(favourites)
        try? context.save()
        return favourites
    }

    func allPlaylists() -> [LocalPlaylist] {
        let descriptor = FetchDescriptor<LocalPlaylist>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Free users get exactly the seeded Favourites list; anything beyond that
    /// is the paywall trigger.
    func canCreatePlaylist(isPro: Bool, freeLimit: Int) -> Bool {
        isPro || allPlaylists().count < max(1, freeLimit)
    }

    @discardableResult
    func createPlaylist(named name: String) -> LocalPlaylist {
        let playlist = LocalPlaylist(name: name)
        context.insert(playlist)
        try? context.save()
        return playlist
    }

    func delete(_ playlist: LocalPlaylist) {
        guard !playlist.isDefault else { return }   // Favourites is permanent
        context.delete(playlist)
        try? context.save()
    }

    func contains(_ item: MediaItem, in playlist: LocalPlaylist) -> Bool {
        playlist.tracks.contains { $0.videoId == item.id }
    }

    func add(_ item: MediaItem, to playlist: LocalPlaylist) {
        guard !contains(item, in: playlist) else { return }
        let track = LocalTrack(from: item)
        track.playlist = playlist
        context.insert(track)
        try? context.save()
    }

    func remove(_ track: LocalTrack) {
        context.delete(track)
        try? context.save()
    }

    func toggleFavourite(_ item: MediaItem) {
        let favourites = ensureDefaultPlaylist()
        if let existing = favourites.tracks.first(where: { $0.videoId == item.id }) {
            remove(existing)
        } else {
            add(item, to: favourites)
        }
    }

    func isFavourite(_ item: MediaItem) -> Bool {
        contains(item, in: ensureDefaultPlaylist())
    }
}
