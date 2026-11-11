import AVFoundation
import Foundation
import Observation
import UIKit

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

    // V1 named its YouTube downloads after the video ID.
    var isLegacyYouTubeDownload: Bool {
        MediaItem.isYouTubeVideoID(id) && audioFileName == "\(id).m4a"
    }

    var asMediaItem: MediaItem {
        let artworkURL = DownloadManager.localArtworkURL(for: id)
        return MediaItem(
            id: id,
            kind: isLegacyYouTubeDownload ? .video : .song,
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
        syncWithDisk()
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncWithDisk()
        }
    }

    // MARK: - Query Status

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

    func localAudioURL(for id: String) -> URL? {
        if let track = downloadedTracks.first(where: { $0.id == id }) {
            let file = Self.audioDirectory.appendingPathComponent(track.audioFileName)
            if FileManager.default.fileExists(atPath: file.path) {
                return file
            }
        }
        return Self.localAudioURL(for: id)
    }

    func localArtworkURL(for id: String) -> URL? {
        if let track = downloadedTracks.first(where: { $0.id == id }), let artName = track.artworkFileName {
            let file = Self.artworkDirectory.appendingPathComponent(artName)
            if FileManager.default.fileExists(atPath: file.path) {
                return file
            }
        }
        return Self.localArtworkURL(for: id)
    }

    func localArtworkImage(for id: String) -> UIImage? {
        guard let url = localArtworkURL(for: id) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    var totalStorageBytes: Int64 {
        downloadedTracks.reduce(into: 0) { $0 += $1.fileSizeBytes }
    }

    var formattedTotalStorage: String {
        ByteCountFormatter.string(fromByteCount: totalStorageBytes, countStyle: .file)
    }

    func importedAudioURL(for id: String) -> URL? {
        guard let track = track(for: id), !track.isLegacyYouTubeDownload else { return nil }
        return localAudioURL(for: id)
    }

    // MARK: - Import

    /// Copies user-selected audio or video files (e.g. picked via the Files app
    /// importer) into offline storage and registers them via `syncWithDisk`.
    func importMediaFiles(from urls: [URL]) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                let dest = Self.audioDirectory.appendingPathComponent(url.lastPathComponent)
                try? fm.removeItem(at: dest)
                try? fm.copyItem(at: url, to: dest)
            }
            await MainActor.run {
                self.syncWithDisk()
            }
        }
    }

    // MARK: - Deletion & Cleanup

    func deleteDownload(for id: String) {
        guard let track = track(for: id) else { return }
        removeFiles(for: track)
        downloadedTracks.removeAll { $0.id == id }
        saveMetadata()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func deleteAllDownloads() {
        for track in downloadedTracks {
            removeFiles(for: track)
        }
        downloadedTracks.removeAll()
        saveMetadata()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    private func removeFiles(for track: DownloadedTrack) {
        let audio = Self.audioDirectory.appendingPathComponent(track.audioFileName)
        try? FileManager.default.removeItem(at: audio)
        if let artworkName = track.artworkFileName {
            let artwork = Self.artworkDirectory.appendingPathComponent(artworkName)
            try? FileManager.default.removeItem(at: artwork)
        }
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

    /// Grabs a representative frame from a video asset to use as artwork when no
    /// embedded artwork metadata is present. Returns nil harmlessly for audio-only
    /// assets (no video track to sample).
    private nonisolated static func extractVideoFrame(from asset: AVURLAsset, durationSeconds: Double) -> Data? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let sampleSeconds = durationSeconds.isFinite && durationSeconds > 0 ? min(1, durationSeconds / 2) : 0
        let time = CMTime(seconds: sampleSeconds, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85)
    }

    /// Reconciles files on disk with the download registry:
    /// 1. Removes missing files deleted from the Files app.
    /// 2. Discovers new audio files added directly via the Files app, extracting title, artist, and embedded artwork.
    func syncWithDisk() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            var changed = false

            // 1. Check existing tracks against disk
            let currentTracks = await MainActor.run { self.downloadedTracks }
            let validTracks = currentTracks.filter { track in
                let file = Self.audioDirectory.appendingPathComponent(track.audioFileName)
                return fm.fileExists(atPath: file.path)
            }
            if validTracks.count != currentTracks.count {
                changed = true
            }

            // 2. Discover newly added files in Files app (audio and video — video
            // files are played back for their audio track, same as a song).
            let allowedExtensions: Set<String> = [
                "m4a", "mp3", "aac", "wav", "flac", "m4b", "aiff",
                "mp4", "mov", "m4v"
            ]

            // If user dropped files directly into the root TuneTube/OfflineMusic directory, move to audio/
            if let rootFiles = try? fm.contentsOfDirectory(at: Self.rootDirectory, includingPropertiesForKeys: nil) {
                for file in rootFiles where allowedExtensions.contains(file.pathExtension.lowercased()) {
                    let dest = Self.audioDirectory.appendingPathComponent(file.lastPathComponent)
                    try? fm.moveItem(at: file, to: dest)
                }
            }

            var newlyImported: [DownloadedTrack] = []
            if let audioFiles = try? fm.contentsOfDirectory(at: Self.audioDirectory, includingPropertiesForKeys: nil) {
                let existingFileNames = Set(validTracks.map(\.audioFileName))

                for fileURL in audioFiles where allowedExtensions.contains(fileURL.pathExtension.lowercased()) {
                    let fileName = fileURL.lastPathComponent
                    if !existingFileNames.contains(fileName) {
                        let asset = AVURLAsset(url: fileURL)
                        let common = asset.commonMetadata
                        let title = AVMetadataItem.metadataItems(from: common, withKey: AVMetadataKey.commonKeyTitle, keySpace: .common).first?.stringValue
                            ?? fileURL.deletingPathExtension().lastPathComponent
                        let artist = AVMetadataItem.metadataItems(from: common, withKey: AVMetadataKey.commonKeyArtist, keySpace: .common).first?.stringValue
                        let album = AVMetadataItem.metadataItems(from: common, withKey: AVMetadataKey.commonKeyAlbumName, keySpace: .common).first?.stringValue
                        let artworkData = AVMetadataItem.metadataItems(from: common, withKey: AVMetadataKey.commonKeyArtwork, keySpace: .common).first?.dataValue

                        let rawDuration = CMTimeGetSeconds(asset.duration)
                        let duration: Int? = (rawDuration.isFinite && rawDuration > 0) ? Int(rawDuration) : nil

                        let id: String
                        if fileName.hasSuffix(".m4a") && fileName.count > 4 {
                            let base = String(fileName.dropLast(4))
                            id = (base.contains(" ") || MediaItem.isYouTubeVideoID(base)) ? "imported_\(abs(fileName.hashValue))" : base
                        } else {
                            id = "imported_\(abs(fileName.hashValue))"
                        }

                        var artworkName: String? = nil
                        if let artworkData {
                            let artDest = Self.artworkDirectory.appendingPathComponent("\(id).jpg")
                            try? artworkData.write(to: artDest, options: .atomic)
                            artworkName = "\(id).jpg"
                        } else if let frameData = Self.extractVideoFrame(from: asset, durationSeconds: rawDuration) {
                            // No embedded artwork (typical for imported video files):
                            // grab a representative frame instead of leaving it blank,
                            // which would otherwise fall back to a guessed (and 404ing)
                            // remote YouTube thumbnail URL.
                            let artDest = Self.artworkDirectory.appendingPathComponent("\(id).jpg")
                            try? frameData.write(to: artDest, options: .atomic)
                            artworkName = "\(id).jpg"
                        }

                        let fileSize = (try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0

                        let importedTrack = DownloadedTrack(
                            id: id,
                            title: title,
                            subtitle: artist,
                            artistName: artist,
                            albumName: album,
                            durationSeconds: duration,
                            downloadedAt: (try? fm.attributesOfItem(atPath: fileURL.path)[.creationDate] as? Date) ?? Date(),
                            fileSizeBytes: fileSize,
                            audioFileName: fileName,
                            artworkFileName: artworkName
                        )

                        newlyImported.append(importedTrack)
                        changed = true
                    }
                }
            }

            if changed {
                let finalTracks = newlyImported + validTracks
                await MainActor.run {
                    self.downloadedTracks = finalTracks
                    self.saveMetadata()
                }
            }
        }
    }
}
