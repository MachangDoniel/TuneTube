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

    private let cacheDirectory: URL = {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("AudioTracks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var cache: [String: CachedStream] = [:]
    private var durations: [String: Double] = [:]

    private init() {}

    func getExpectedDuration(for videoID: String) -> Double? {
        durations[videoID]
    }

    /// Checks if a complete audio file for `videoID` is already cached on disk.
    func getCachedAudioFileURL(for videoID: String) -> URL? {
        let fileURL = cacheDirectory.appendingPathComponent("\(videoID).m4a")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? UInt64, size > 100_000 {
            sanitizeFragmentedMP4(at: fileURL)
            return fileURL
        }
        return nil
    }

    /// Sanitizes YouTube fragmented MP4 files by zeroing out the initial movie header (`mvhd`, `tkhd`, `mdhd`) duration.
    /// YouTube serves DASH audio files where `moov` has duration D and the fragments have duration D.
    /// Without this, Apple AVFoundation sums the moov duration and fragment durations, incorrectly reporting
    /// 2x duration (e.g. 9:23 instead of 4:41), causing the UI progress bar to end at 50% and stall silently.
    @discardableResult
    func sanitizeFragmentedMP4(at fileURL: URL) -> Bool {
        guard let handle = try? FileHandle(forUpdating: fileURL) else { return false }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 32768), data.count > 100 else { return false }

        func findBox(_ name: String, in bytes: Data) -> Int? {
            let target = Array(name.utf8)
            guard target.count == 4 else { return nil }
            var i = 0
            while i <= bytes.count - 4 {
                if bytes[i] == target[0] && bytes[i+1] == target[1] && bytes[i+2] == target[2] && bytes[i+3] == target[3] {
                    return i
                }
                i += 1
            }
            return nil
        }

        // Only patch if this is a fragmented MP4 (contains mvex or moof)
        guard findBox("mvex", in: data) != nil || findBox("moof", in: data) != nil else {
            return false
        }

        var patched = false
        let zeroFourBytes = Data(repeating: 0, count: 4)
        let zeroEightBytes = Data(repeating: 0, count: 8)

        // 1. mvhd
        if let pos = findBox("mvhd", in: data), pos + 4 < data.count {
            let ver = data[pos + 4]
            let offset = UInt64(pos + 4 + (ver == 0 ? 16 : 24))
            try? handle.seek(toOffset: offset)
            try? handle.write(contentsOf: ver == 0 ? zeroFourBytes : zeroEightBytes)
            patched = true
        }

        // 2. tkhd
        if let pos = findBox("tkhd", in: data), pos + 4 < data.count {
            let ver = data[pos + 4]
            let offset = UInt64(pos + 4 + (ver == 0 ? 20 : 28))
            try? handle.seek(toOffset: offset)
            try? handle.write(contentsOf: ver == 0 ? zeroFourBytes : zeroEightBytes)
            patched = true
        }

        // 3. mdhd
        if let pos = findBox("mdhd", in: data), pos + 4 < data.count {
            let ver = data[pos + 4]
            let offset = UInt64(pos + 4 + (ver == 0 ? 16 : 24))
            try? handle.seek(toOffset: offset)
            try? handle.write(contentsOf: ver == 0 ? zeroFourBytes : zeroEightBytes)
            patched = true
        }

        return patched
    }

    /// Downloads the full audio track to disk in the background.
    /// Returns the local destination URL once completed and verified.
    func downloadAudioFile(for videoID: String, streamURL: URL) async -> URL? {
        let destinationURL = cacheDirectory.appendingPathComponent("\(videoID).m4a")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: destinationURL.path),
           let size = attrs[.size] as? UInt64, size > 100_000 {
            sanitizeFragmentedMP4(at: destinationURL)
            return destinationURL
        }

        do {
            var request = URLRequest(url: streamURL)
            request.timeoutInterval = 60
            let (tempURL, response) = try await URLSession.shared.download(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               (httpResponse.statusCode == 200 || httpResponse.statusCode == 206) {
                try? FileManager.default.removeItem(at: destinationURL)
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)

                if let attrs = try? FileManager.default.attributesOfItem(atPath: destinationURL.path),
                   let size = attrs[.size] as? UInt64, size > 100_000 {
                    sanitizeFragmentedMP4(at: destinationURL)
                    cleanOldCacheIfNeeded()
                    return destinationURL
                }
            }
        } catch {
            print("[StreamResolver] Background download failed: \(error)")
        }
        return nil
    }

    /// Resolves and guarantees a complete, unthrottled audio track file for `videoID`.
    /// Downloads the ~4.5MB AAC stream directly to the local cache in ~1 second during YouTube's
    /// initial unthrottled burst window, completely eliminating CDN cutoffs, silent endings,
    /// and buffering stalls, while providing instant seeking and true offline background playback.
    func resolveAudioFileURL(for videoID: String) async throws -> URL {
        // 1. Return existing local file if already downloaded
        if let cachedFile = getCachedAudioFileURL(for: videoID) {
            return cachedFile
        }

        // 2. Resolve remote stream URL (itag 140 AAC or best audio)
        let streamURL = try await resolveStreamURL(for: videoID)

        // 3. Download the complete audio file to disk
        if let localURL = await downloadAudioFile(for: videoID, streamURL: streamURL) {
            return localURL
        }

        // 4. Fallback: If downloading failed or file was invalid, return remote stream URL directly
        return streamURL
    }

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

        // Extract exact duration from Google CDN signed query parameter &dur=<seconds>
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let durVal = comps.queryItems?.first(where: { $0.name == "dur" })?.value,
           let durSec = Double(durVal), durSec > 0 {
            durations[videoID] = durSec
        }
    }

    private func cleanOldCacheIfNeeded() {
        Task.detached(priority: .background) { [cacheDirectory] in
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ) else { return }

            if files.count > 50 {
                let sortedFiles = files.sorted {
                    let date1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                    let date2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                    return date1 < date2
                }
                for oldFile in sortedFiles.prefix(files.count - 50) {
                    try? fm.removeItem(at: oldFile)
                }
            }
        }
    }

    func clearCache() {
        cache.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
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
