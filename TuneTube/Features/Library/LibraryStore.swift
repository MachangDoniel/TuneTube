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
    func createPlaylist(
        named name: String,
        iconName: String = "heart.fill",
        colorHex: String? = nil
    ) -> LocalPlaylist {
        let chosenColor = colorHex ?? distinctColor(for: iconName)
        let playlist = LocalPlaylist(name: name, isDefault: false, iconName: iconName, colorHex: chosenColor)
        context.insert(playlist)
        try? context.save()
        return playlist
    }

    func updatePlaylist(_ playlist: LocalPlaylist, name: String, iconName: String, colorHex: String) {
        playlist.name = name
        playlist.iconName = iconName
        playlist.colorHex = colorHex
        try? context.save()
    }

    func distinctColor(for icon: String) -> String {
        let palette = [
            "#FF2D55", // Pink
            "#AF52DE", // Purple
            "#007AFF", // Blue
            "#FF9500", // Orange
            "#34C759", // Green
            "#30B0C7", // Teal
            "#FF3B30", // Red
            "#FFCC00", // Yellow
            "#5856D6"  // Indigo
        ]
        let usedColors = Set(allPlaylists().map(\.colorHex))
        for color in palette {
            if !usedColors.contains(color) {
                return color
            }
        }
        return palette[allPlaylists().count % palette.count]
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
        context.insert(track)
        // Append through the parent so `playlist.tracks` (and any view observing
        // it) updates immediately, rather than after SwiftData syncs the inverse.
        playlist.tracks.append(track)
        try? context.save()
    }

    func remove(_ track: LocalTrack) {
        context.delete(track)
        try? context.save()
    }

    func setFavourite(_ item: MediaItem, _ favourite: Bool) {
        let favourites = ensureDefaultPlaylist()
        if favourite {
            add(item, to: favourites)
        } else {
            let matches = favourites.tracks.filter { $0.videoId == item.id }
            favourites.tracks.removeAll { $0.videoId == item.id }
            matches.forEach(context.delete)
            try? context.save()
        }
    }

    func isFavourite(_ item: MediaItem) -> Bool {
        contains(item, in: ensureDefaultPlaylist())
    }
}
