import Foundation

enum APIError: LocalizedError {
    case badStatus(Int)
    case rateLimited
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "Server limit reached. Showing last loaded content."
        case .badStatus(let code):
            if code == 429 || code == 503 || code == 529 || code == 530 {
                return "Server limit reached. Showing last loaded content."
            }
            return "Server returned \(code)."
        case .transport:
            #if DEBUG
            return "Can't reach the API at \(AppConfig.apiBaseURL.absoluteString) or Cloudflare Worker."
            #else
            return "Can't reach TuneTube right now."
            #endif
        }
    }
}

/// Talks to the TuneTube Worker. Every read goes through `DiskCache` so a cold
/// launch with no network still shows the last known feed.
actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let cache = DiskCache()
    private var bearerToken: String?

    #if DEBUG
    private var currentBaseURL: URL = AppConfig.initialBaseURL
    private var isUsingFallback: Bool = false
    #else
    private let currentBaseURL: URL = AppConfig.initialBaseURL
    #endif

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Sets or clears the Bearer token for authenticated requests.
    func setBearerToken(_ token: String?) {
        self.bearerToken = token
    }

    /// Active base URL being used by the client.
    var activeBaseURL: URL {
        currentBaseURL
    }

    #if DEBUG
    /// Resets base URL back to the local Mac server (e.g. after restarting Wrangler).
    func resetToLocalServer() {
        currentBaseURL = AppConfig.localBaseURL
        isUsingFallback = false
        DebugLog.network.notice("Reset API base URL to local server: \(AppConfig.localBaseURL.absoluteString, privacy: .public)")
    }
    #endif

    private func url(for baseURL: URL, path: String, query: [String: String] = [:]) -> URL {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "gl", value: AppConfig.region))
        items.append(URLQueryItem(name: "hl", value: AppConfig.language))
        comps.queryItems = items
        return comps.url!
    }

    private func makeRequest(
        baseURL: URL,
        path: String,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        method: String = "GET",
        timeoutInterval: TimeInterval = 60.0
    ) -> URLRequest {
        var req = URLRequest(url: url(for: baseURL, path: path, query: query))
        req.httpMethod = method
        req.timeoutInterval = timeoutInterval
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearerToken {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        return req
    }

    private func execute<T: Decodable & Sendable>(
        _ type: T.Type,
        request: URLRequest,
        cacheKey: String?
    ) async throws -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        #if DEBUG
        NetworkLogger.logRequest(request)
        #endif

        do {
            let (data, response) = try await session.data(for: request)
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            #if DEBUG
            NetworkLogger.logResponse(response, data: data, duration: duration, for: request)
            #endif

            guard let http = response as? HTTPURLResponse else {
                throw APIError.badStatus(-1)
            }
            if http.statusCode == 429 || http.statusCode == 503 || http.statusCode == 529 || http.statusCode == 530 {
                #if DEBUG
                DebugLog.network.warning("⚠️ Cloudflare/Server limit reached (status \(http.statusCode)).")
                #endif
                throw APIError.rateLimited
            }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.badStatus(http.statusCode)
            }
            let value = try decoder.decode(T.self, from: data)
            if let cacheKey { await cache.write(data, for: cacheKey) }
            return value
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            #if DEBUG
            NetworkLogger.logError(error, duration: duration, for: request)
            #endif
            throw error
        }
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
        headers: [String: String] = [:],
        cacheKey: String?,
        ttl: TimeInterval? = nil,
        forceRefresh: Bool = false
    ) async throws -> T {
        // 1. Cache-First check: if not forcing refresh and fresh cached data exists, return instantly (0ms, 0 network)
        if !forceRefresh, let cacheKey, let ttl {
            if let freshData = await cache.read(for: cacheKey, maxAge: ttl),
               let cached = try? decoder.decode(T.self, from: freshData) {
                #if DEBUG
                DebugLog.network.notice("⚡️ Cache hit for '\(cacheKey, privacy: .public)' (TTL: \(Int(ttl))s). Skipping network call.")
                #endif
                return cached
            }
        }

        #if DEBUG
        let targetBaseURL = currentBaseURL
        let isAttemptingLocal = (!isUsingFallback && targetBaseURL == AppConfig.localBaseURL)
        let timeout: TimeInterval = isAttemptingLocal ? 5.0 : 60.0
        #else
        let targetBaseURL = currentBaseURL
        let timeout: TimeInterval = 60.0
        #endif

        let request = makeRequest(
            baseURL: targetBaseURL,
            path: path,
            query: query,
            headers: headers,
            timeoutInterval: timeout
        )

        do {
            return try await execute(type, request: request, cacheKey: cacheKey)
        } catch {
            #if DEBUG
            if isAttemptingLocal {
                DebugLog.network.notice("⚠️ Local server at \(targetBaseURL.absoluteString, privacy: .public) not connected within 5s (\(error.localizedDescription, privacy: .public)). Falling back to Cloudflare: \(AppConfig.productionBaseURL.absoluteString, privacy: .public)")
                self.currentBaseURL = AppConfig.productionBaseURL
                self.isUsingFallback = true

                let fallbackRequest = makeRequest(
                    baseURL: AppConfig.productionBaseURL,
                    path: path,
                    query: query,
                    headers: headers,
                    timeoutInterval: 60.0
                )
                do {
                    return try await execute(type, request: fallbackRequest, cacheKey: cacheKey)
                } catch let fallbackError {
                    if let cacheKey,
                       let data = await cache.readStale(for: cacheKey),
                       let cached = try? decoder.decode(T.self, from: data) {
                        return cached
                    }
                    throw fallbackError
                }
            }
            #endif

            if let cacheKey,
               let data = await cache.readStale(for: cacheKey),
               let cached = try? decoder.decode(T.self, from: data) {
                return cached
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
        do {
            let response = try await get(SearchResponse.self, path: "v1/search", query: q, cacheKey: key, ttl: TTL.search, forceRefresh: forceRefresh)
            if !response.shelves.isEmpty, let data = try? encoder.encode(response) {
                await cache.write(data, for: "search-last-loaded")
            }
            return response.shelves
        } catch {
            // If rate-limited or failed and this specific query isn't cached, fall back to last loaded search
            if let data = await cache.readStale(for: "search-last-loaded"),
               let cached = try? decoder.decode(SearchResponse.self, from: data) {
                #if DEBUG
                DebugLog.network.warning("Cloudflare limit or error on search. Serving last loaded search.")
                #endif
                return cached.shelves
            }
            throw error
        }
    }

    /// Returns the most recently loaded search results from cache if available.
    func lastLoadedSearch() async -> [Shelf]? {
        if let data = await cache.readStale(for: "search-last-loaded"),
           let cached = try? decoder.decode(SearchResponse.self, from: data) {
            return cached.shelves
        }
        return nil
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
        try await get(RemoteConfig.self, path: "v1/config", cacheKey: "config", ttl: TTL.config, forceRefresh: forceRefresh)
    }
}
