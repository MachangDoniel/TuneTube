import Foundation

enum MediaKind: String, Codable, Sendable {
    case song, video, album, playlist, artist
}

struct MediaItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let kind: MediaKind
    let title: String
    let subtitle: String?
    let thumbnailUrl: URL?
    let durationSeconds: Int?
    let playlistId: String?
    let artistName: String?
    let albumName: String?

    /// Artist pages show the album under the track; everywhere else the artist
    /// reads better. The server sends both so the client can choose.
    func displaySubtitle(preferring preference: SubtitlePreference = .automatic) -> String? {
        switch preference {
        case .album:  return albumName ?? subtitle
        case .artist: return artistName ?? subtitle
        case .automatic: return subtitle ?? artistName
        }
    }

    enum SubtitlePreference { case automatic, artist, album }

    var isPlayable: Bool { kind == .song || kind == .video }
}

struct Shelf: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let items: [MediaItem]
}

struct HomeResponse: Codable, Sendable { let shelves: [Shelf] }
struct SearchResponse: Codable, Sendable { let shelves: [Shelf] }

struct ArtistDetail: Codable, Sendable {
    let id: String
    let name: String
    let description: String?
    let thumbnailUrl: URL?
    let subscribers: String?
    let shelves: [Shelf]
}

struct PlaylistDetail: Codable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let description: String?
    let thumbnailUrl: URL?
    let tracks: [MediaItem]
}

// MARK: - Remote config

struct MoodChip: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let label: String
    let emoji: String
}

struct TrendingSearch: Codable, Hashable, Identifiable, Sendable {
    var id: String { label }
    let label: String
    let emoji: String
}

struct PaywallConfig: Codable, Sendable {
    let title: String
    let subtitle: String
    let lifetimeProductId: String
    let weeklyProductId: String
    let highlightedProductId: String
    let termsUrl: URL
    let privacyUrl: URL
}

struct RemoteConfig: Codable, Sendable {
    let moodChips: [MoodChip]
    let trendingSearches: [TrendingSearch]
    let hiddenShelfIds: [String]
    let minSupportedBuild: Int
    let freePlaylistLimit: Int
    let paywall: PaywallConfig

    static let fallback = RemoteConfig(
        moodChips: [],
        trendingSearches: [],
        hiddenShelfIds: [],
        minSupportedBuild: 1,
        freePlaylistLimit: 1,
        paywall: PaywallConfig(
            title: "Unlock Pro",
            subtitle: "Access your full library without limits and keep your music experience uninterrupted.",
            lifetimeProductId: "com.tunetube.pro.lifetime",
            weeklyProductId: "com.tunetube.pro.weekly",
            highlightedProductId: "com.tunetube.pro.lifetime",
            termsUrl: URL(string: "https://example.com/terms")!,
            privacyUrl: URL(string: "https://example.com/privacy")!
        )
    )
}
