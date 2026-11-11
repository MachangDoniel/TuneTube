import Foundation

enum APIError: LocalizedError {
    case missingKey, unavailable, badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Set YOUTUBE_DATA_API_KEY in the app’s build settings to browse YouTube."
        case .unavailable: return "This item isn’t available through the YouTube Data API."
        case .badStatus(403), .badStatus(429): return "YouTube denied the request. Check your API key and quota."
        case .badStatus(let status): return "YouTube returned HTTP \(status)."
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    private struct Page<Item: Decodable>: Decodable {
        let items: [Item]
    }

    private struct Snippet: Decodable {
        let title: String
        let description: String?
        let channelTitle: String?
        let thumbnails: [String: Thumbnail]?
        let resourceId: ResourceID?

        struct Thumbnail: Decodable { let url: URL }
        var artwork: URL? {
            thumbnails?["high"]?.url ?? thumbnails?["medium"]?.url ?? thumbnails?["default"]?.url
        }

        func media(id: String, kind: MediaKind = .video) -> MediaItem {
            MediaItem(id: id, kind: kind, title: title, subtitle: channelTitle,
                      thumbnailUrl: artwork, artistName: channelTitle)
        }
    }

    private struct ResourceID: Decodable {
        let videoId: String?
        let channelId: String?
        let playlistId: String?
    }

    private struct SearchResult: Decodable {
        let id: ResourceID
        let snippet: Snippet
    }

    private struct Resource: Decodable {
        let id: String
        let snippet: Snippet
        let status: Status?
        let contentDetails: ContentDetails?

        struct Status: Decodable { let embeddable: Bool? }
        struct ContentDetails: Decodable {
            let relatedPlaylists: RelatedPlaylists?
            struct RelatedPlaylists: Decodable { let uploads: String? }
        }
    }

    private let session: URLSession
    private final class CachedPage {
        let data: Data
        let expiresAt = Date().addingTimeInterval(900)
        init(_ data: Data) { self.data = data }
    }

    private let cache = NSCache<NSURL, CachedPage>()

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
        cache.countLimit = 120
    }

    private func page<Item: Decodable>(
        _ endpoint: String, _ parameters: [String: String], forceRefresh: Bool = false
    ) async throws -> Page<Item> {
        var url = URLComponents()
        url.scheme = "https"
        url.host = "www.googleapis.com"
        url.path = "/youtube/v3/\(endpoint)"
        url.queryItems = parameters.sorted { $0.key < $1.key }.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        let decoder = JSONDecoder()
        guard let requestURL = url.url else { throw APIError.unavailable }
        let cacheKey = requestURL as NSURL
        if !forceRefresh, let cached = cache.object(forKey: cacheKey), cached.expiresAt > Date(),
           let page = try? decoder.decode(Page<Item>.self, from: cached.data) {
            return page
        }
        guard let key = AppConfig.youtubeAPIKey else { throw APIError.missingKey }
        var request = URLRequest(url: requestURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else { throw APIError.badStatus(status) }
        let result = try decoder.decode(Page<Item>.self, from: data)
        cache.setObject(CachedPage(data), forKey: cacheKey)
        return result
    }

    func home(forceRefresh: Bool = false) async throws -> [Shelf] {
        let result: Page<Resource> = try await page("videos", [
            "part": "snippet,status", "chart": "mostPopular", "videoCategoryId": "10",
            "regionCode": AppConfig.region, "maxResults": "25"
        ], forceRefresh: forceRefresh)
        return [Shelf(id: "popular", title: "Popular on YouTube", items: result.items
            .filter { $0.status?.embeddable == true }
            .map { $0.snippet.media(id: $0.id) })]
    }

    func search(_ query: String, type: String? = nil, forceRefresh: Bool = false) async throws -> [Shelf] {
        let resourceType: String
        switch type {
        case "artist", "artists": resourceType = "channel"
        case "playlist", "playlists": resourceType = "playlist"
        case "album", "albums": return []
        case nil, "all": resourceType = "video,channel,playlist"
        default: resourceType = "video"
        }
        var parameters = [
            "part": "snippet", "q": query, "type": resourceType, "maxResults": "25",
            "regionCode": AppConfig.region, "relevanceLanguage": AppConfig.language
        ]
        if resourceType == "video" {
            parameters["videoEmbeddable"] = "true"
            parameters["videoCategoryId"] = "10"
        }
        let result: Page<SearchResult> = try await page("search", parameters, forceRefresh: forceRefresh)
        let embeddable: Set<String>
        if resourceType.contains("video"), resourceType != "video" {
            let ids = result.items.compactMap { $0.id.videoId }
            embeddable = Set(try await playableVideos(ids, forceRefresh: forceRefresh).keys)
        } else {
            embeddable = Set(result.items.compactMap { $0.id.videoId })
        }
        let items = result.items.compactMap { item -> MediaItem? in
            if let id = item.id.videoId, embeddable.contains(id) { return item.snippet.media(id: id) }
            if let id = item.id.channelId { return item.snippet.media(id: id, kind: .artist) }
            if let id = item.id.playlistId { return item.snippet.media(id: id, kind: .playlist) }
            return nil
        }
        return [(MediaKind.video, "Videos"), (.artist, "Channels"), (.playlist, "Playlists")]
            .compactMap { kind, title -> Shelf? in
                let matches = items.filter { $0.kind == kind }
                return matches.isEmpty ? nil : Shelf(id: kind.rawValue, title: title, items: matches)
            }
    }

    func artist(_ browseId: String, forceRefresh: Bool = false) async throws -> ArtistDetail {
        let result: Page<Resource> = try await page("channels", [
            "part": "snippet,contentDetails", "id": browseId
        ], forceRefresh: forceRefresh)
        guard let channel = result.items.first else { throw APIError.unavailable }
        var shelves: [Shelf] = []
        if let uploads = channel.contentDetails?.relatedPlaylists?.uploads {
            let items = try await playlistTracks(uploads, forceRefresh: forceRefresh)
            shelves = [Shelf(id: uploads, title: "Uploads", items: items)]
        }
        return ArtistDetail(id: channel.id, name: channel.snippet.title,
                            description: channel.snippet.description, thumbnailUrl: channel.snippet.artwork,
                            subscribers: nil, shelves: shelves)
    }

    func playlist(_ playlistId: String, forceRefresh: Bool = false) async throws -> PlaylistDetail {
        let result: Page<Resource> = try await page("playlists", [
            "part": "snippet", "id": playlistId
        ], forceRefresh: forceRefresh)
        guard let playlist = result.items.first else { throw APIError.unavailable }
        let tracks = try await playlistTracks(playlistId, forceRefresh: forceRefresh)
        return PlaylistDetail(id: playlist.id, title: playlist.snippet.title,
                              subtitle: playlist.snippet.channelTitle, description: playlist.snippet.description,
                              thumbnailUrl: playlist.snippet.artwork, tracks: tracks)
    }

    private func playlistTracks(_ id: String, forceRefresh: Bool) async throws -> [MediaItem] {
        let result: Page<Resource> = try await page("playlistItems", [
            "part": "snippet", "playlistId": id, "maxResults": "50"
        ], forceRefresh: forceRefresh)
        let videos = result.items.compactMap { $0.snippet.resourceId?.videoId }
        let playable = try await playableVideos(videos, forceRefresh: forceRefresh)
        return videos.compactMap { playable[$0] }
    }

    private func playableVideos(_ videos: [String], forceRefresh: Bool) async throws -> [String: MediaItem] {
        guard !videos.isEmpty else { return [:] }
        let details: Page<Resource> = try await page("videos", [
            "part": "snippet,status", "id": Array(Set(videos)).sorted().joined(separator: ",")
        ], forceRefresh: forceRefresh)
        return Dictionary(uniqueKeysWithValues: details.items.filter {
            $0.status?.embeddable == true
        }.map { ($0.id, $0.snippet.media(id: $0.id)) })
    }

    func clearCaches() {
        cache.removeAllObjects()
    }
}
