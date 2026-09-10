import AVFoundation
import Combine
import Foundation
import MediaPlayer
import SwiftUI
import UIKit
import YouTubePlayerKit

/// Owns playback, background audio, remote lock-screen controls, and queue management.
///
/// Features a hybrid playback engine:
///  * Primary: Native `AVPlayer` with direct audio/video stream resolution via `YouTubeKit`
///    (delivering true uninterrupted background audio, lock screen sound, and low battery consumption,
///    matching the MuseTube/Musi architecture).
///  * Fallback: Embedded `YouTubePlayerKit` iframe player if stream extraction is unavailable.
@MainActor
@Observable
final class PlayerEngine {
    static let shared = PlayerEngine()

    /// Native AVPlayer for true background audio and lock screen sound
    let avPlayer = AVPlayer()

    /// Embedded YouTube web player instance (used as fallback or for embedded web playback)
    let player: YouTubePlayer

    /// Indicates whether current playback is routed through native AVPlayer
    private(set) var isNativeAVPlayer = false

    /// Current display mode (Song or Video)
    var displayMode: PlayerDisplayMode = .song

    /// Cached stream URL for background handoff or native playback
    private var currentResolvedStreamURL: URL?
    private var currentResolvedItemID: String?

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
    private var isSeeking = false

    var hasNext: Bool {
        index + 1 < queue.count
    }

    var hasPrevious: Bool {
        index > 0 || currentTime > 3
    }

    private var intendedPlaying = false
    private var ticker: AnyCancellable?
    private var playbackStateCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var timeObserverToken: Any?
    private var currentLoadTask: Task<Void, Never>?

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
                fullscreenMode: .system,
                allowsInlineMediaPlayback: true,
                allowsAirPlayForMediaPlayback: true,
                allowsPictureInPictureMediaPlayback: true,
                automaticallyAdjustsContentInsets: true
            )
        )

        configureAudioSession()
        configureRemoteCommands()
        setupAVPlayerObservers()
        setupBackgroundHandling()
        observePlaybackState()
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
        // Platform convention: restart current track before skipping back.
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard index > 0 else { return }
        index -= 1
        loadCurrent()
    }

    private func loadCurrent() {
        guard let item = current else { return }
        isLoading = true
        intendedPlaying = true
        currentTime = 0
        duration = Double(item.durationSeconds ?? 0)
        configureAudioSession()
        RecentStore.shared.record(item)
        updateNowPlaying()

        currentResolvedStreamURL = nil
        currentResolvedItemID = item.id

        currentLoadTask?.cancel()
        currentLoadTask = Task { [weak self] in
            guard let self else { return }

            let isAppInBackground = UIApplication.shared.applicationState == .background
            if self.displayMode == .song || isAppInBackground {
                // SONG MODE: Direct native AVPlayer for instant playback, zero battery drain, and flawless background audio
                self.isNativeAVPlayer = true
                try? await self.player.pause()

                do {
                    let streamURL = try await StreamResolver.shared.resolveStreamURL(for: item.id)
                    guard !Task.isCancelled, self.current?.id == item.id else { return }
                    self.currentResolvedStreamURL = streamURL
                    self.currentResolvedItemID = item.id

                    let playerItem = AVPlayerItem(url: streamURL)
                    playerItem.preferredForwardBufferDuration = 0
                    self.avPlayer.automaticallyWaitsToMinimizeStalling = true
                    self.avPlayer.replaceCurrentItem(with: playerItem)
                    self.configureAudioSession()
                    self.avPlayer.play()
                    self.isPlaying = true
                    self.isLoading = false
                    self.updateNowPlaying()
                } catch {
                    print("[PlayerEngine] Native stream error: \(error). Falling back to iframe...")
                    guard !Task.isCancelled, self.current?.id == item.id else { return }
                    self.isNativeAVPlayer = false
                    self.avPlayer.pause()
                    self.avPlayer.replaceCurrentItem(with: nil)
                    try? await self.player.load(source: .video(id: item.id))
                    self.isPlaying = true
                    self.isLoading = false
                    self.updateNowPlaying()
                }
            } else {
                // VIDEO MODE: Official video rendered via YouTube web player in foreground
                self.isNativeAVPlayer = false
                self.avPlayer.pause()
                self.avPlayer.replaceCurrentItem(with: nil)

                do {
                    try await self.player.load(source: .video(id: item.id))
                    guard !Task.isCancelled, self.current?.id == item.id else { return }
                    self.isPlaying = true
                    self.isLoading = false
                    self.updateNowPlaying()
                    self.injectBackgroundAudioFix()
                } catch {
                    print("[PlayerEngine] Video iframe load error: \(error)")
                }

                // Pre-resolve stream in background so AVPlayer is instantly ready when backgrounding
                if let streamURL = try? await StreamResolver.shared.resolveStreamURL(for: item.id) {
                    guard !Task.isCancelled, self.current?.id == item.id else { return }
                    self.currentResolvedStreamURL = streamURL
                    self.currentResolvedItemID = item.id
                }
            }
        }
    }

    func setDisplayMode(_ mode: PlayerDisplayMode) {
        guard displayMode != mode else { return }
        displayMode = mode
        guard let item = current else { return }

        let targetTime = currentTime
        let wasPlaying = isPlaying || intendedPlaying

        if mode == .song {
            // Switching from Video to Song: seamlessly move playback from YouTube iframe to native AVPlayer
            Task { [weak self] in
                guard let self else { return }
                try? await self.player.pause()
                self.isNativeAVPlayer = true

                let streamURL: URL
                if let cached = self.currentResolvedStreamURL, self.currentResolvedItemID == item.id {
                    streamURL = cached
                } else if let resolved = try? await StreamResolver.shared.resolveStreamURL(for: item.id) {
                    self.currentResolvedStreamURL = resolved
                    self.currentResolvedItemID = item.id
                    streamURL = resolved
                } else {
                    return
                }

                let playerItem = AVPlayerItem(url: streamURL)
                playerItem.preferredForwardBufferDuration = 0
                self.avPlayer.automaticallyWaitsToMinimizeStalling = true
                self.avPlayer.replaceCurrentItem(with: playerItem)
                let cmTime = CMTime(seconds: targetTime, preferredTimescale: 600)
                await self.avPlayer.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
                self.configureAudioSession()
                if wasPlaying {
                    self.avPlayer.play()
                    self.isPlaying = true
                }
                self.updateNowPlaying()
            }
        } else {
            // Switching from Song to Video: seamlessly move playback from native AVPlayer to YouTube iframe video
            Task { [weak self] in
                guard let self else { return }
                self.avPlayer.pause()
                self.isNativeAVPlayer = false

                do {
                    try await self.player.load(source: .video(id: item.id))
                    try? await self.player.seek(to: .init(value: targetTime, unit: .seconds), allowSeekAhead: true)
                    self.configureAudioSession()
                    if wasPlaying {
                        try? await self.player.play()
                        self.isPlaying = true
                    }
                    self.updateNowPlaying()
                    self.injectBackgroundAudioFix()
                } catch {
                    print("[PlayerEngine] Switch to video failed: \(error)")
                }
            }
        }
    }

    // MARK: - Transport

    func togglePlayPause() {
        if isNativeAVPlayer {
            if isPlaying {
                intendedPlaying = false
                avPlayer.pause()
                isPlaying = false
            } else {
                intendedPlaying = true
                configureAudioSession()
                avPlayer.play()
                isPlaying = true
            }
            updateNowPlaying()
        } else {
            Task {
                if isPlaying {
                    intendedPlaying = false
                    try? await player.pause()
                    isPlaying = false
                } else {
                    intendedPlaying = true
                    configureAudioSession()
                    try? await player.play()
                    isPlaying = true
                }
                updateNowPlaying()
            }
        }
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        isSeeking = true
        if isNativeAVPlayer {
            let cmTime = CMTime(seconds: seconds, preferredTimescale: 600)
            avPlayer.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isSeeking = false
                    self.updateNowPlaying()
                }
            }
        } else {
            Task {
                try? await player.seek(to: .init(value: seconds, unit: .seconds), allowSeekAhead: true)
                try? await Task.sleep(nanoseconds: 350_000_000)
                isSeeking = false
                updateNowPlaying()
            }
        }
    }

    func forward10() {
        let target = min(currentTime + 10, duration > 0 ? duration : currentTime + 10)
        seek(to: target)
    }

    func backward10() {
        let target = max(currentTime - 10, 0)
        seek(to: target)
    }

    // MARK: - Native AVPlayer Setup & Observers

    private func setupAVPlayerObservers() {
        // Periodic time observer for continuous scrubber synchronization
        let interval = CMTime(value: 1, timescale: 2) // 0.5s
        timeObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, !self.isScrubbing, !self.isSeeking, self.isNativeAVPlayer else { return }
                let seconds = time.seconds
                if !seconds.isNaN && seconds >= 0 {
                    self.currentTime = seconds
                }
                if let currentItem = self.avPlayer.currentItem {
                    let dur = currentItem.duration.seconds
                    if !dur.isNaN && dur > 0 {
                        self.duration = dur
                    }
                }
                if self.avPlayer.timeControlStatus == .playing {
                    self.isPlaying = true
                    self.isLoading = false
                } else if self.avPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                    self.isLoading = true
                } else if self.avPlayer.timeControlStatus == .paused {
                    self.isPlaying = false
                    self.isLoading = false
                }
                self.updateNowPlaying()
            }
        }

        // KVO observer on timeControlStatus for instant play/pause/buffer state updates
        avPlayer.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, self.isNativeAVPlayer else { return }
                switch status {
                case .playing:
                    self.isPlaying = true
                    self.isLoading = false
                    self.intendedPlaying = true
                case .paused:
                    self.isPlaying = false
                    self.isLoading = false
                case .waitingToPlayAtSpecifiedRate:
                    if !self.isPlaying {
                        self.isLoading = true
                    }
                @unknown default:
                    break
                }
                self.updateNowPlaying()
            }
            .store(in: &cancellables)

        // Rate observer for rock-solid play/pause state reflection
        avPlayer.publisher(for: \.rate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rate in
                guard let self, self.isNativeAVPlayer else { return }
                self.isPlaying = (rate > 0)
                if rate > 0 {
                    self.isLoading = false
                    self.intendedPlaying = true
                }
                self.updateNowPlaying()
            }
            .store(in: &cancellables)

        // Item track completion notification
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isNativeAVPlayer else { return }
                self.next()
            }
            .store(in: &cancellables)

        // Audio session interruptions (e.g. incoming phone call)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let userInfo = notification.userInfo,
                      let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

                switch type {
                case .began:
                    self.isPlaying = false
                    self.updateNowPlaying()
                case .ended:
                    if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                        if options.contains(.shouldResume) && self.intendedPlaying {
                            self.configureAudioSession()
                            if self.isNativeAVPlayer {
                                self.avPlayer.play()
                            } else {
                                Task { try? await self.player.play() }
                            }
                            self.isPlaying = true
                            self.updateNowPlaying()
                        }
                    }
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - State Observation (Fallback IFrame)

    private func observePlaybackState() {
        playbackStateCancellable?.cancel()
        playbackStateCancellable = player.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self, !self.isNativeAVPlayer else { return }
                switch state {
                case .playing:
                    self.isPlaying = true
                    self.isLoading = false
                    self.intendedPlaying = true
                case .paused:
                    self.isPlaying = false
                    self.isLoading = false
                case .buffering:
                    if !self.isPlaying {
                        self.isLoading = true
                    }
                case .ended:
                    self.isPlaying = false
                    self.isLoading = false
                    self.next()
                default:
                    break
                }
                self.updateNowPlaying()
            }
    }

    // MARK: - Background Audio Handling

    private func injectBackgroundAudioFix() {
        let script = """
        (function() {
            try {
                Object.defineProperty(document, 'visibilityState', { get: function() { return 'visible'; }, configurable: true });
                Object.defineProperty(document, 'hidden', { get: function() { return false; }, configurable: true });
                document.addEventListener('visibilitychange', function(e) { e.stopImmediatePropagation(); }, true);
                if ('audioSession' in navigator) {
                    navigator.audioSession.type = 'playback';
                }
            } catch(e) {}
        })();
        """
        Task {
            try? await player.evaluate(javaScript: YouTubePlayer.JavaScript(script))
        }
    }

    private func setupBackgroundHandling() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                guard let self, self.intendedPlaying, let item = self.current else { return }

                self.configureAudioSession()

                if self.isNativeAVPlayer {
                    // Already playing via native AVPlayer (Song mode) -> Continues playing smoothly
                    self.avPlayer.play()
                } else {
                    // Currently playing via YouTube iframe (Video mode).
                    // WebKit is suspended by iOS in background!
                    // Hand off to native AVPlayer immediately at the exact current position:
                    let targetTime = self.currentTime
                    self.isNativeAVPlayer = true
                    Task {
                        try? await self.player.pause()

                        let streamURL: URL
                        if let cached = self.currentResolvedStreamURL, self.currentResolvedItemID == item.id {
                            streamURL = cached
                        } else if let resolved = try? await StreamResolver.shared.resolveStreamURL(for: item.id) {
                            self.currentResolvedStreamURL = resolved
                            self.currentResolvedItemID = item.id
                            streamURL = resolved
                        } else {
                            return
                        }

                        let playerItem = AVPlayerItem(url: streamURL)
                        playerItem.preferredForwardBufferDuration = 0
                        self.avPlayer.automaticallyWaitsToMinimizeStalling = true
                        self.avPlayer.replaceCurrentItem(with: playerItem)
                        let cmTime = CMTime(seconds: targetTime, preferredTimescale: 600)
                        await self.avPlayer.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
                        self.configureAudioSession()
                        self.avPlayer.play()
                        self.isPlaying = true
                        self.updateNowPlaying()
                    }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                guard let self, self.intendedPlaying else { return }

                if self.displayMode == .video && self.isNativeAVPlayer {
                    // Returning to foreground in Video mode: hand back to YouTube iframe video
                    let targetTime = self.currentTime
                    self.avPlayer.pause()
                    self.isNativeAVPlayer = false
                    Task {
                        try? await self.player.seek(to: .init(value: targetTime, unit: .seconds), allowSeekAhead: true)
                        try? await self.player.play()
                        self.isPlaying = true
                        self.updateNowPlaying()
                    }
                } else if self.isNativeAVPlayer {
                    self.avPlayer.play()
                    self.updateNowPlaying()
                } else {
                    Task {
                        try? await self.player.play()
                        self.updateNowPlaying()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Polling

    private func startTicker() {
        ticker = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.tick() }
            }
    }

    private func tick() async {
        guard hasTrack, !isScrubbing, !isSeeking, !isNativeAVPlayer else { return }

        if let time = try? await player.getCurrentTime() {
            let newTime = time.converted(to: .seconds).value
            if newTime > 0 && newTime != currentTime {
                isLoading = false
            }
            currentTime = newTime
        }

        if isPlaying {
            isLoading = false
        }

        if duration <= 0, let d = try? await player.getDuration() {
            duration = d.converted(to: .seconds).value
            updateNowPlaying()
        }

        // Advance at the end of track
        if duration > 0, currentTime >= duration - 1.0, isPlaying {
            next()
        }
        updateNowPlaying()
    }

    // MARK: - Now Playing / Lock Screen

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("[PlayerEngine] Audio session error: \(error)")
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.intendedPlaying = true
                self.configureAudioSession()
                if self.isNativeAVPlayer {
                    self.avPlayer.play()
                    self.isPlaying = true
                } else {
                    try? await self.player.play()
                    self.isPlaying = true
                }
                self.updateNowPlaying()
            }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.intendedPlaying = false
                if self.isNativeAVPlayer {
                    self.avPlayer.pause()
                    self.isPlaying = false
                } else {
                    try? await self.player.pause()
                    self.isPlaying = false
                }
                self.updateNowPlaying()
            }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayPause()
            }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.forward10() }
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.backward10() }
            return .success
        }

        // Lock screen and Control Center scrubber slider drag handling
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                self.seek(to: posEvent.positionTime)
            }
            return .success
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

    /// Fetches thumbnail once per track for lock screen.
    private func loadArtwork(for item: MediaItem) {
        guard let url = item.effectiveThumbnailUrl else { return }
        Task { [weak self] in
            guard let image = await ImageLoader.shared.image(for: url) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            guard let self, self.current?.id == item.id else { return }
            self.artworkCache = (item.id, artwork)
            self.updateNowPlaying()
        }
    }
}
