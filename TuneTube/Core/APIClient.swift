import Foundation

enum APIError: LocalizedError {
    case badStatus(Int)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "Server returned \(code)."
        case .transport:
            #if DEBUG
            return "Can't reach the API at \(AppConfig.apiBaseURL.absoluteString). "
                 + "Is the Worker running with --ip 0.0.0.0?"
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
    private let cache = DiskCache()
    private var bearerToken: String?

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Sets or clears the Bearer token for authenticated requests.
    func setBearerToken(_ token: String?) {
        self.bearerToken = token
    }

    private func url(_ path: String, _ query: [String: String] = [:]) -> URL {
        var comps = URLComponents(url: AppConfig.apiBaseURL.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "gl", value: AppConfig.region))
        items.append(URLQueryItem(name: "hl", value: AppConfig.language))
        comps.queryItems = items
        return comps.url!
    }

    private func makeRequest(
        path: String,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        method: String = "GET"
    ) -> URLRequest {
        var req = URLRequest(url: url(path, query))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearerToken {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        return req
    }

    /// Fetch + decode, writing through to the disk cache. On failure, fall back
    /// to the cached copy rather than showing an empty screen.
    private func get<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        cacheKey: String
    ) async throws -> T {
        let request = makeRequest(path: path, query: query, headers: headers)
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
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.badStatus(http.statusCode)
            }
            let value = try decoder.decode(T.self, from: data)
            await cache.write(data, for: cacheKey)
            return value
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            #if DEBUG
            NetworkLogger.logError(error, duration: duration, for: request)
            #endif

            if let data = await cache.read(for: cacheKey),
               let cached = try? decoder.decode(T.self, from: data) {
                return cached
            }
            throw error
        }
    }

    func home() async throws -> [Shelf] {
        try await get(HomeResponse.self, path: "v1/home", cacheKey: "home").shelves
    }

    func search(_ query: String, type: String? = nil) async throws -> [Shelf] {
        var q = ["q": query]
        if let type { q["type"] = type }
        // Searches are transient; key the cache per query so back-navigation is instant.
        return try await get(SearchResponse.self, path: "v1/search", query: q,
                             cacheKey: "search-\(query.lowercased())-\(type ?? "all")").shelves
    }

    func artist(_ browseId: String) async throws -> ArtistDetail {
        try await get(ArtistDetail.self, path: "v1/artist/\(browseId)",
                      cacheKey: "artist-\(browseId)")
    }

    func playlist(_ playlistId: String) async throws -> PlaylistDetail {
        try await get(PlaylistDetail.self, path: "v1/playlist/\(playlistId)",
                      cacheKey: "playlist-\(playlistId)")
    }

    func category(_ key: String) async throws -> [Shelf] {
        struct CategoryResponse: Codable { let shelves: [Shelf] }
        return try await get(CategoryResponse.self, path: "v1/category/\(key)",
                             cacheKey: "category-\(key)").shelves
    }

    func config() async throws -> RemoteConfig {
        try await get(RemoteConfig.self, path: "v1/config", cacheKey: "config")
    }
}
