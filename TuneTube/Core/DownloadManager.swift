import Foundation
import Observation
import UIKit

enum DownloadState: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case failed(error: String)

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }

    var isDownloaded: Bool {
        self == .downloaded
    }
}

struct DownloadedTrack: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let artistName: String?
    let albumName: String?
    let durationSeconds: Int?
    let downloadedAt: Date
    let fileSizeBytes: Int64
    let audioFileName: String
    let artworkFileName: String?

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        artistName: String? = nil,
        albumName: String? = nil,
        durationSeconds: Int? = nil,
        downloadedAt: Date = Date(),
        fileSizeBytes: Int64 = 0,
        audioFileName: String,
        artworkFileName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artistName = artistName
        self.albumName = albumName
        self.durationSeconds = durationSeconds
        self.downloadedAt = downloadedAt
        self.fileSizeBytes = fileSizeBytes
        self.audioFileName = audioFileName
        self.artworkFileName = artworkFileName
    }

    var asMediaItem: MediaItem {
        let artworkURL = DownloadManager.localArtworkURL(for: id)
        return MediaItem(
            id: id,
            kind: .song,
            title: title,
            subtitle: subtitle,
            thumbnailUrl: artworkURL,
            durationSeconds: durationSeconds,
            playlistId: nil,
            artistName: artistName,
            albumName: albumName
        )
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
}

@MainActor
@Observable
final class DownloadManager {
    static let shared = DownloadManager()

    private(set) var downloadedTracks: [DownloadedTrack] = []
    private var downloadStates: [String: DownloadState] = [:]
    private var activeTasks: [String: Task<Void, Never>] = [:]

    private nonisolated static let rootDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("OfflineMusic", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDir = dir
        try? mutableDir.setResourceValues(resourceValues)
        return dir
    }()

    private nonisolated static var audioDirectory: URL {
        let dir = rootDirectory.appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private nonisolated static var artworkDirectory: URL {
        let dir = rootDirectory.appendingPathComponent("artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private nonisolated static var metadataURL: URL {
        rootDirectory.appendingPathComponent("metadata.json")
    }

    private init() {
        loadMetadata()
    }

    // MARK: - Query Status

    func status(for id: String) -> DownloadState {
        if let state = downloadStates[id] {
            return state
        }
        return isDownloaded(id) ? .downloaded : .notDownloaded
    }

    func isDownloaded(_ id: String) -> Bool {
        guard downloadedTracks.contains(where: { $0.id == id }) else { return false }
        return localAudioURL(for: id) != nil
    }

    func track(for id: String) -> DownloadedTrack? {
        downloadedTracks.first { $0.id == id }
    }

    nonisolated static func localAudioURL(for id: String) -> URL? {
        let file = audioDirectory.appendingPathComponent("\(id).m4a")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           let size = attrs[.size] as? UInt64, size > 100_000 {
            return file
        }
        return nil
    }

    nonisolated static func localArtworkURL(for id: String) -> URL? {
        let file = artworkDirectory.appendingPathComponent("\(id).jpg")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           let size = attrs[.size] as? UInt64, size > 500 {
            return file
        }
        return nil
    }

    nonisolated static func localArtworkImage(for id: String) -> UIImage? {
        guard let url = localArtworkURL(for: id) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    nonisolated func localAudioURL(for id: String) -> URL? {
        Self.localAudioURL(for: id)
    }

    nonisolated func localArtworkURL(for id: String) -> URL? {
        Self.localArtworkURL(for: id)
    }

    nonisolated func localArtworkImage(for id: String) -> UIImage? {
        Self.localArtworkImage(for: id)
    }

    var totalStorageBytes: Int64 {
        downloadedTracks.reduce(into: 0) { $0 += $1.fileSizeBytes }
    }

    var formattedTotalStorage: String {
        ByteCountFormatter.string(fromByteCount: totalStorageBytes, countStyle: .file)
    }

    // MARK: - Download Execution

    func startDownload(item: MediaItem) {
        guard !isDownloaded(item.id) else { return }
        if let current = downloadStates[item.id], current.isDownloading { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        downloadStates[item.id] = .downloading(progress: 0.05)

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.performDownload(for: item)
                self.downloadStates[item.id] = .downloaded
                self.activeTasks[item.id] = nil
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                if !Task.isCancelled {
                    print("[DownloadManager] Download failed for \(item.title): \(error)")
                    self.downloadStates[item.id] = .failed(error: error.localizedDescription)
                    self.activeTasks[item.id] = nil
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }

        activeTasks[item.id] = task
    }

    private func performDownload(for item: MediaItem) async throws {
        let destAudioURL = Self.audioDirectory.appendingPathComponent("\(item.id).m4a")
        let destArtworkURL = Self.artworkDirectory.appendingPathComponent("\(item.id).jpg")

        // 1. Audio file acquisition
        // If StreamResolver has already cached this track, copy it immediately (<0.01s)
        if let cachedLocalURL = await StreamResolver.shared.getCachedAudioFileURL(for: item.id),
           let attrs = try? FileManager.default.attributesOfItem(atPath: cachedLocalURL.path),
           let size = attrs[.size] as? UInt64, size > 100_000 {
            try? FileManager.default.removeItem(at: destAudioURL)
            try FileManager.default.copyItem(at: cachedLocalURL, to: destAudioURL)
            StreamResolver.sanitizeFragmentedMP4(at: destAudioURL)
            downloadStates[item.id] = .downloading(progress: 0.85)
        } else {
            // Resolve stream URL and download with progress
            downloadStates[item.id] = .downloading(progress: 0.15)
            let streamURL = try await StreamResolver.shared.resolveStreamURL(for: item.id)

            downloadStates[item.id] = .downloading(progress: 0.35)
            var request = URLRequest(url: streamURL)
            request.timeoutInterval = 60

            let (tempURL, response) = try await URLSession.shared.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (httpResponse.statusCode == 200 || httpResponse.statusCode == 206) else {
                throw URLError(.badServerResponse)
            }

            try? FileManager.default.removeItem(at: destAudioURL)
            try FileManager.default.moveItem(at: tempURL, to: destAudioURL)
            StreamResolver.sanitizeFragmentedMP4(at: destAudioURL)
            downloadStates[item.id] = .downloading(progress: 0.85)
        }

        guard let audioAttrs = try? FileManager.default.attributesOfItem(atPath: destAudioURL.path),
              let audioSize = audioAttrs[.size] as? UInt64, audioSize > 100_000 else {
            throw URLError(.cannotCreateFile)
        }

        // 2. Artwork image download
        var savedArtworkName: String? = nil
        if let thumbURL = item.effectiveThumbnailUrl {
            do {
                let (artData, _) = try await URLSession.shared.data(from: thumbURL)
                if !artData.isEmpty {
                    try artData.write(to: destArtworkURL, options: .atomic)
                    savedArtworkName = "\(item.id).jpg"
                    if UIImage(data: artData) != nil {
                        _ = ImageLoader.shared.cached(destArtworkURL) // warmup
                    }
                }
            } catch {
                print("[DownloadManager] Artwork download failed: \(error)")
            }
        }

        downloadStates[item.id] = .downloading(progress: 0.98)

        // 3. Metadata persistence
        let newTrack = DownloadedTrack(
            id: item.id,
            title: item.title,
            subtitle: item.subtitle,
            artistName: item.artistName,
            albumName: item.albumName,
            durationSeconds: item.durationSeconds,
            downloadedAt: Date(),
            fileSizeBytes: Int64(audioSize),
            audioFileName: "\(item.id).m4a",
            artworkFileName: savedArtworkName
        )

        // Remove any existing entry and place fresh track at top
        downloadedTracks.removeAll { $0.id == item.id }
        downloadedTracks.insert(newTrack, at: 0)
        saveMetadata()
    }

    // MARK: - Deletion & Cleanup

    func cancelDownload(for id: String) {
        activeTasks[id]?.cancel()
        activeTasks[id] = nil
        downloadStates[id] = .notDownloaded
    }

    func deleteDownload(for id: String) {
        cancelDownload(for: id)

        let audioFile = Self.audioDirectory.appendingPathComponent("\(id).m4a")
        let artworkFile = Self.artworkDirectory.appendingPathComponent("\(id).jpg")

        try? FileManager.default.removeItem(at: audioFile)
        try? FileManager.default.removeItem(at: artworkFile)

        downloadedTracks.removeAll { $0.id == id }
        downloadStates[id] = .notDownloaded
        saveMetadata()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func deleteAllDownloads() {
        for track in downloadedTracks {
            cancelDownload(for: track.id)
            let audioFile = Self.audioDirectory.appendingPathComponent("\(track.id).m4a")
            let artworkFile = Self.artworkDirectory.appendingPathComponent("\(track.id).jpg")
            try? FileManager.default.removeItem(at: audioFile)
            try? FileManager.default.removeItem(at: artworkFile)
            downloadStates[track.id] = .notDownloaded
        }
        downloadedTracks.removeAll()
        saveMetadata()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    // MARK: - Persistence

    private func saveMetadata() {
        do {
            let data = try JSONEncoder().encode(downloadedTracks)
            try data.write(to: Self.metadataURL, options: .atomic)
        } catch {
            print("[DownloadManager] Save metadata error: \(error)")
        }
    }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: Self.metadataURL),
              let tracks = try? JSONDecoder().decode([DownloadedTrack].self, from: data) else {
            return
        }

        // Verify that audio files still exist on disk
        self.downloadedTracks = tracks.filter { track in
            let file = Self.audioDirectory.appendingPathComponent(track.audioFileName)
            return FileManager.default.fileExists(atPath: file.path)
        }
    }
}
