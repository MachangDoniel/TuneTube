import AVFoundation
import Combine
import Foundation
import MediaPlayer
import SwiftUI
import UIKit
import YouTubePlayerKit

/// Owns the single, app-lifetime YouTube embed and the playback queue.
///
/// Two deliberate constraints, both verified against the platform:
///
///  * ONE `YouTubePlayer` for the app's lifetime. Recreating it per track tears
///    down and reloads the whole iframe, which flashes and re-buffers.
///  * Playback stops when the app backgrounds. WKWebView loses its media
///    playback assertion on background and there is no entitlement for it
///    outside browser apps, so we persist position and resume on return rather
///    than pretending background audio works.
@MainActor
@Observable
final class PlayerEngine {
    static let shared = PlayerEngine()

    /// Handed to `YouTubePlayerView`. Not observed directly; we drive our own state.
    let player: YouTubePlayer

    private(set) var queue: [MediaItem] = []
    private(set) var index: Int = 0
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isLoading = false

    /// True once something has been loaded, so the mini player can appear.
    var hasTrack: Bool { current != nil }
    var current: MediaItem? { queue.indices.contains(index) ? queue[index] : nil }

    /// Set while the user drags the scrubber so polling doesn't fight the gesture.
    var isScrubbing = false

    private var ticker: AnyCancellable?
    /// Cached so we don't refetch lock-screen artwork on every Now Playing update.
    private var artworkCache: (id: String, artwork: MPMediaItemArtwork)?

    private init() {
        player = YouTubePlayer(
            source: nil,
            parameters: .init(
                autoPlay: true,
                showControls: true,
                showFullscreenButton: true
            ),
            configuration: .init(
                // .system fullscreen is what surfaces iOS's native video
                // controls — and with them the Picture in Picture button, which
                // is the only way to reach PiP for a cross-origin iframe.
                fullscreenMode: .system,
                allowsInlineMediaPlayback: true,
                allowsAirPlayForMediaPlayback: true,
                // Picture in Picture is our supported route to background audio:
                // once the video is in PiP, iOS grants a real media assertion and
                // playback survives backgrounding and the lock screen.
                allowsPictureInPictureMediaPlayback: true,
                automaticallyAdjustsContentInsets: true
            )
        )
        configureAudioSession()
        configureRemoteCommands()
        startTicker()
    }

    // MARK: - Queue control

    func play(_ item: MediaItem, in context: [MediaItem] = []) {
        let playable = (context.isEmpty ? [item] : context).filter(\.isPlayable)
        queue = playable.isEmpty ? [item] : playable
        index = queue.firstIndex(of: item) ?? 0
        loadCurrent()
    }

    func next() {
        guard index + 1 < queue.count else { return }
        index += 1
        loadCurrent()
    }

    func previous() {
        // Match the platform convention: restart the track before skipping back.
        if currentTime > 3 {
            Task { try? await player.seek(to: .init(value: 0, unit: .seconds)) }
            return
        }
        guard index > 0 else { return }
        index -= 1
        loadCurrent()
    }

    private func loadCurrent() {
        guard let item = current else { return }
        isLoading = true
        currentTime = 0
        duration = Double(item.durationSeconds ?? 0)
        Task {
            try? await player.load(source: .video(id: item.id))
            isPlaying = true
            isLoading = false
            updateNowPlaying()
        }
    }

    // MARK: - Transport

    func togglePlayPause() {
        Task {
            if isPlaying {
                try? await player.pause()
                isPlaying = false
            } else {
                try? await player.play()
                isPlaying = true
            }
            updateNowPlaying()
        }
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        Task { try? await player.seek(to: .init(value: seconds, unit: .seconds)) }
    }

    // MARK: - Polling
    //
    // We poll rather than subscribe: the iframe bridge's state publishers are
    // chatty and version-sensitive, and a 0.5s poll is enough for a scrubber.

    private func startTicker() {
        ticker = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.tick() }
            }
    }

    private func tick() async {
        guard hasTrack, !isScrubbing else { return }

        if let time = try? await player.getCurrentTime() {
            currentTime = time.converted(to: .seconds).value
        }
        if duration <= 0, let d = try? await player.getDuration() {
            duration = d.converted(to: .seconds).value
        }

        // Advance at the end of the track. The embed reports a duration a second
        // longer than the audio in practice, so allow a small margin.
        if duration > 0, currentTime >= duration - 1.0, isPlaying {
            next()
        }
        updateNowPlaying()
    }

    // MARK: - Now Playing / lock screen

    private func configureAudioSession() {
        // Plain .playback, deliberately WITHOUT .mixWithOthers: mixing makes us
        // a secondary audio session, and a secondary session does not get
        // background-audio privileges. We need to be the primary audio app.
        // The silent keeper and the WebView both live inside this one app
        // session, so they coexist without interrupting each other.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }; return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }; return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }; return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }; return .success
        }
    }

    private func updateNowPlaying() {
        guard let item = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: item.artistName ?? item.displaySubtitle() ?? "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]
        if let album = item.albumName { info[MPMediaItemPropertyAlbumTitle] = album }
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork = artworkCache?.id == item.id ? artworkCache?.artwork : nil {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if artworkCache?.id != item.id { loadArtwork(for: item) }
    }

    /// Fetches the thumbnail once per track and hands it to the lock screen.
    private func loadArtwork(for item: MediaItem) {
        guard let url = item.thumbnailUrl else { return }
        Task { [weak self] in
            // Shares ImageLoader's cache with the UI, so the lock screen usually
            // gets the image with no extra network request at all.
            guard let image = await ImageLoader.shared.image(for: url) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            guard let self, self.current?.id == item.id else { return }
            self.artworkCache = (item.id, artwork)
            self.updateNowPlaying()
        }
    }
}
