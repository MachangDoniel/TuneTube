import Foundation
import YouTubeKit

/// Resolves direct, playable audio/media stream URLs for YouTube video IDs.
/// Uses YouTubeKit to extract streams compatible with native Apple AVPlayer.
actor StreamResolver {
    static let shared = StreamResolver()

    private struct CachedStream {
        let url: URL
        let expiresAt: Date
    }

    private var cache: [String: CachedStream] = [:]

    private init() {}

    /// Resolves the best available natively playable audio stream URL for `videoID`.
    /// Prefers high-bitrate AAC audio (itag 140: 128kbps / itag 139: 64kbps) for instant buffering,
    /// high audio fidelity, low battery consumption, and seamless background playback.
    func resolveStreamURL(for videoID: String) async throws -> URL {
        // Return valid cached URL if available
        if let cached = cache[videoID], cached.expiresAt > Date() {
            return cached.url
        }

        let video = YouTube(videoID: videoID)
        let streams = try await video.streams

        // 1. Prefer audio-only AAC streams (itag 140: 128kbps AAC / itag 139: 64kbps AAC).
        // Audio-only AAC streams buffer in milliseconds (~4MB for full track), require no video
        // decoding overhead, and play continuously in the background and on the lock screen.
        let playableAudio = streams
            .filterAudioOnly()
            .filter { $0.isNativelyPlayable }

        if let bestAudio = playableAudio.highestAudioBitrateStream() {
            cacheStream(videoID: videoID, url: bestAudio.url)
            return bestAudio.url
        }

        if let itag140 = streams.stream(withITag: 140) {
            cacheStream(videoID: videoID, url: itag140.url)
            return itag140.url
        }

        if let itag139 = streams.stream(withITag: 139) {
            cacheStream(videoID: videoID, url: itag139.url)
            return itag139.url
        }

        // 2. Fallback: Progressive muxed streams (itag 18: 360p / itag 22: 720p)
        let playableCombined = streams
            .filterVideoAndAudio()
            .filter { $0.isNativelyPlayable }

        if let bestCombined = playableCombined.first {
            cacheStream(videoID: videoID, url: bestCombined.url)
            return bestCombined.url
        }

        if let itag18 = streams.stream(withITag: 18) {
            cacheStream(videoID: videoID, url: itag18.url)
            return itag18.url
        }

        // 3. Fallback: Any natively playable stream
        if let anyPlayable = streams.first(where: { $0.isNativelyPlayable }) {
            cacheStream(videoID: videoID, url: anyPlayable.url)
            return anyPlayable.url
        }

        throw StreamError.noPlayableStreamFound
    }

    func getCachedStreamURL(for videoID: String) -> URL? {
        if let cached = cache[videoID], cached.expiresAt > Date() {
            return cached.url
        }
        return nil
    }

    private func cacheStream(videoID: String, url: URL) {
        // Stream URLs typically expire in ~6 hours; cache for 3 hours safely
        cache[videoID] = CachedStream(
            url: url,
            expiresAt: Date().addingTimeInterval(3 * 3600)
        )
    }

    func clearCache() {
        cache.removeAll()
    }
}

enum StreamError: LocalizedError {
    case noPlayableStreamFound

    var errorDescription: String? {
        switch self {
        case .noPlayableStreamFound:
            return "Unable to find a playable stream for this track."
        }
    }
}
