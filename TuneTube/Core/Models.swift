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

    init(
        id: String,
        kind: MediaKind,
        title: String,
        subtitle: String? = nil,
        thumbnailUrl: URL? = nil,
        durationSeconds: Int? = nil,
        playlistId: String? = nil,
        artistName: String? = nil,
        albumName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.thumbnailUrl = thumbnailUrl
        self.durationSeconds = durationSeconds
        self.playlistId = playlistId
        self.artistName = artistName
        self.albumName = albumName
    }

    /// Full-resolution artwork URL.
    /// Upscales Google / YouTube Music thumbnails to 544x544 for crystal-clear display on large screens,
    /// and falls back to standard YouTube thumbnail if none was provided.
    var effectiveThumbnailUrl: URL? {
        if let thumbnailUrl {
            let str = thumbnailUrl.absoluteString
            if str.contains("googleusercontent.com") {
                let upscaled = str
                    .replacingOccurrences(of: "=w\\d+-h\\d+", with: "=w544-h544", options: .regularExpression)
                    .replacingOccurrences(of: "=s\\d+", with: "=s544", options: .regularExpression)
                return URL(string: upscaled) ?? thumbnailUrl
            }
            return thumbnailUrl
        }
        if !id.isEmpty && (kind == .song || kind == .video) {
            return URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
        }
        return nil
    }

    /// The plain `hqdefault.jpg` fallback is 4:3 with black bars above and below
    /// the 16:9 frame. Scale it by this to crop the bars off in a square.
    var thumbnailLetterboxScale: CGFloat {
        guard let url = effectiveThumbnailUrl, url.host == "i.ytimg.com", url.query == nil,
              url.lastPathComponent == "hqdefault.jpg" else { return 1 }
        return 4.0 / 3.0
    }

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

/// A page of a track's radio ("<Song> Mix"). `continuation` fetches the next page.
struct RadioPage: Codable, Sendable {
    let title: String?
    let tracks: [MediaItem]
    let continuation: String?
}

struct Lyrics: Codable, Sendable {
    let text: String
    let source: String?
}

struct LyricsResponse: Codable, Sendable {
    let lyrics: Lyrics?
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
