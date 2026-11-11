import Foundation

enum APIError: LocalizedError {
    case catalogUnavailable
    case upstream(String)

    var errorDescription: String? {
        switch self {
        case .catalogUnavailable:
            return "The YouTube Music catalog is unavailable."
        case .upstream(let message):
            if message.contains("HTTP 429") {
                return "YouTube Music is limiting requests. Try again shortly."
            }
            return "Could not load from YouTube Music. Try again shortly."
        }
    }
}

/// Loads the YouTube Music catalog directly and reuses device-local responses.
actor APIClient {
    static let shared = APIClient()

    private let catalog: DirectMusicCatalog
    private let decoder = JSONDecoder()
    private let cache = DiskCache()

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        catalog = DirectMusicCatalog(session: session)
    }

    /// Fetch + decode, writing through to the disk cache. On failure, fall back
    /// to the cached copy rather than showing an empty screen. A nil `cacheKey`
    /// skips the disk cache (one-shot responses like continuation pages).
    enum TTL {
        static let home: TimeInterval = 3600       // 1 hour
        static let search: TimeInterval = 900      // 15 minutes
        static let artist: TimeInterval = 86400    // 24 hours
        static let playlist: TimeInterval = 21600  // 6 hours
        static let category: TimeInterval = 21600  // 6 hours
        static let config: TimeInterval = 3600     // 1 hour
    }

    /// Fetch + decode, writing through to the disk cache.
    /// Uses Cache-First strategy when `ttl` is provided to eliminate redundant network calls.
    private func get<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        query: [String: String] = [:],
        cacheKey: String?,
        ttl: TimeInterval? = nil,
        forceRefresh: Bool = false
    ) async throws -> T {
        let region = AppConfig.region
        let language = AppConfig.language
        let scopedKey = cacheKey.map { "direct-\(region)-\(language)-\($0)" }
        if !forceRefresh, let scopedKey, let ttl,
           let data = await cache.read(for: scopedKey, maxAge: ttl),
           let value = try? decoder.decode(T.self, from: data) {
            return value
        }

        var parameters = query
        parameters["gl"] = region
        parameters["hl"] = language
        do {
            let data = try await catalog.load(path: path, query: parameters)
            try Task.checkCancellation()
            let value = try decoder.decode(T.self, from: data)
            if let scopedKey { await cache.write(data, for: scopedKey) }
            return value
        } catch {
            try Task.checkCancellation()
            if let scopedKey,
               let data = await cache.readStale(for: scopedKey),
               let value = try? decoder.decode(T.self, from: data) {
                return value
            }
            throw error
        }
    }

    func home(forceRefresh: Bool = false) async throws -> [Shelf] {
        try await get(HomeResponse.self, path: "v1/home", cacheKey: "home", ttl: TTL.home, forceRefresh: forceRefresh).shelves
    }

    func search(_ query: String, type: String? = nil, forceRefresh: Bool = false) async throws -> [Shelf] {
        var q = ["q": query]
        if let type { q["type"] = type }
        let key = "search-\(query.lowercased())-\(type ?? "all")"
        return try await get(SearchResponse.self, path: "v1/search", query: q,
                             cacheKey: key, ttl: TTL.search, forceRefresh: forceRefresh).shelves
    }

    func artist(_ browseId: String, forceRefresh: Bool = false) async throws -> ArtistDetail {
        try await get(ArtistDetail.self, path: "v1/artist/\(browseId)",
                      cacheKey: "artist-\(browseId)", ttl: TTL.artist, forceRefresh: forceRefresh)
    }

    func playlist(_ playlistId: String, forceRefresh: Bool = false) async throws -> PlaylistDetail {
        try await get(PlaylistDetail.self, path: "v1/playlist/\(playlistId)",
                      cacheKey: "playlist-\(playlistId)", ttl: TTL.playlist, forceRefresh: forceRefresh)
    }

    func category(_ key: String, forceRefresh: Bool = false) async throws -> [Shelf] {
        struct CategoryResponse: Codable { let shelves: [Shelf] }
        return try await get(CategoryResponse.self, path: "v1/category/\(key)",
                             cacheKey: "category-\(key)", ttl: TTL.category, forceRefresh: forceRefresh).shelves
    }

    func radio(for videoId: String, continuation: String? = nil) async throws -> RadioPage {
        try await get(RadioPage.self, path: "v1/radio/\(videoId)",
                      query: continuation.map { ["continuation": $0] } ?? [:],
                      cacheKey: continuation == nil ? "radio-\(videoId)" : nil)
    }

    func lyrics(for videoId: String) async throws -> Lyrics? {
        try await get(LyricsResponse.self, path: "v1/lyrics/\(videoId)",
                      cacheKey: "lyrics-\(videoId)").lyrics
    }

    func config(forceRefresh: Bool = false) async throws -> RemoteConfig {
        struct CatalogConfig: Codable, Sendable {
            let moodChips: [MoodChip]
            let trendingSearches: [TrendingSearch]
        }
        let config = try await get(CatalogConfig.self, path: "v1/config",
                                   cacheKey: "config", ttl: TTL.config, forceRefresh: forceRefresh)
        let fallback = RemoteConfig.fallback
        return RemoteConfig(moodChips: config.moodChips, trendingSearches: config.trendingSearches,
                            hiddenShelfIds: fallback.hiddenShelfIds, minSupportedBuild: fallback.minSupportedBuild,
                            freePlaylistLimit: fallback.freePlaylistLimit, paywall: fallback.paywall)
    }

    /// Drops every cached response. Called when the content region or language
    /// changes, since each cached body was fetched for the previous `gl`/`hl`.
    func clearCaches() async {
        await cache.clearAll()
    }
}
