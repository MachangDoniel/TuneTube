import Foundation
import Observation

/// Local cache store for recently played tracks, capped at 50 items.
///
/// Deduplicates entries, promotes replayed tracks to the top, and persists
/// to disk so recent tracks are available across app launches.
@MainActor
@Observable
final class RecentStore {
    static let shared = RecentStore()

    private let maxLimit = 50
    private let storageKey = "tunetube_recently_played_tracks"

    private(set) var items: [MediaItem] = []

    private init() {
        load()
    }

    /// Records a played track, keeping only the 50 most recent unique items.
    func record(_ item: MediaItem) {
        guard item.isPlayable else { return }

        // Remove duplicate if already present, then insert at the top
        var updated = items.filter { $0.id != item.id }
        updated.insert(item, at: 0)

        if updated.count > maxLimit {
            updated = Array(updated.prefix(maxLimit))
        }

        items = updated
        save()
    }

    /// Loads the recently played tracks from local storage.
    func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([MediaItem].self, from: data) else {
            return
        }
        let newItems = Array(decoded.prefix(maxLimit))
        if items != newItems {
            items = newItems
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
