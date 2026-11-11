import AVFoundation
import Combine
import Foundation
import MediaPlayer
import SwiftUI
import UIKit
import YouTubePlayerKit
import OSLog


/// Owns playback, background audio, remote lock-screen controls, and queue management.
///
/// Features a hybrid playback engine:
/// Plays imported files with AVPlayer and YouTube videos in the embedded player.
@MainActor
@Observable
final class PlayerEngine {
    static let shared = PlayerEngine()

    /// Native AVPlayer for true background audio and lock screen sound
    let avPlayer = AVPlayer()

    /// Embedded YouTube player for foreground video playback.
    let player: YouTubePlayer

    /// Indicates whether current playback is routed through native AVPlayer
    private(set) var isNativeAVPlayer = false

    var isVideoPlayerVisible = false {
        didSet {
            if !isVideoPlayerVisible && !isNativeAVPlayer { pause() }
        }
    }

    private(set) var queue: [MediaItem] = []
    private(set) var index: Int = 0
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isLoading = false
    /// True once the last track in the queue has played to its end. The next
    /// play request restarts the current track instead of resuming at the end.
    private(set) var hasEnded = false

    /// True once something has been loaded, so the mini player can appear.
    var hasTrack: Bool { current != nil }
    var current: MediaItem? { queue.indices.contains(index) ? queue[index] : nil }

    /// Set while the user drags the scrubber so polling doesn't fight the gesture.
    var isScrubbing = false
    private var isSeeking = false

    var hasNext: Bool {
        index + 1 < queue.count
    }

    /// Previous always does something: skip back, or restart the first track.
    var hasPrevious: Bool { current != nil }

    /// Neighbours of the current track, for the swipeable artwork carousel.
    var previousItem: MediaItem? { queue.indices.contains(index - 1) ? queue[index - 1] : nil }
    var nextItem: MediaItem? { queue.indices.contains(index + 1) ? queue[index + 1] : nil }

    // MARK: Queue modes

    enum RepeatMode: CaseIterable { case off, all, one }

    private(set) var repeatMode: RepeatMode = .off
    private(set) var isShuffled = false
    /// The queue in its original order while shuffled, so unshuffling restores it.
    private var unshuffledQueue: [MediaItem]?

    // MARK: - Sleep Timer

    public enum SleepTimerOption: Equatable, CaseIterable {
        case off
        case min15
        case min30
        case min45
        case min60
        case endOfTrack

        public static var allCases: [SleepTimerOption] {
            [.off, .min15, .min30, .min45, .min60, .endOfTrack]
        }

        public var title: String {
            switch self {
            case .off: return "Off"
            case .min15: return "15 min"
            case .min30: return "30 min"
            case .min45: return "45 min"
            case .min60: return "60 min"
            case .endOfTrack: return "End of track"
            }
        }
    }

    private(set) var sleepTimerOption: SleepTimerOption = .off
    private(set) var sleepTimerRemainingSeconds: Int?
    private var sleepTimerTask: Task<Void, Never>?

    func setSleepTimer(_ option: SleepTimerOption) {
        sleepTimerTask?.cancel()
        sleepTimerOption = option

        guard option != .off else {
            sleepTimerRemainingSeconds = nil
            return
        }

        if case .endOfTrack = option {
            sleepTimerRemainingSeconds = nil
            return
        }

        var minutes = 15
        switch option {
        case .min15: minutes = 15
        case .min30: minutes = 30
        case .min45: minutes = 45
        case .min60: minutes = 60
        default: break
        }

        var remaining = minutes * 60
        sleepTimerRemainingSeconds = remaining

        sleepTimerTask = Task { [weak self] in
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remaining -= 1
                self?.sleepTimerRemainingSeconds = remaining
            }
            guard !Task.isCancelled else { return }
            self?.pause()
            self?.sleepTimerOption = .off
            self?.sleepTimerRemainingSeconds = nil
        }
    }


    private var intendedPlaying = false
    private var ticker: AnyCancellable?
    private var playbackStateCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var timeObserverToken: Any?
    private var currentLoadTask: Task<Void, Never>?
    private var currentExpectedDuration: Double?

    /// Cached so we don't refetch lock-screen artwork on every Now Playing update.
    private var artworkCache: (id: String, artwork: MPMediaItemArtwork)?

    private var needsFreshLoadOnResume = false

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
                allowsPictureInPictureMediaPlayback: false,
                automaticallyAdjustsContentInsets: true
            ),
            isLoggingEnabled: false
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
        let newQueue = playable.isEmpty ? [item] : playable

        if isShuffled {
            // Tapped track first, the rest of its context shuffled behind it.
            unshuffledQueue = newQueue
            var rest = newQueue
            if let i = rest.firstIndex(of: item) { rest.remove(at: i) }
            queue = [item] + rest.shuffled()
            index = 0
        } else {
            unshuffledQueue = nil
            queue = newQueue
            index = queue.firstIndex(of: item) ?? 0
        }
        loadCurrent()
    }

    func next() {
        guard hasNext else { return }
        index += 1
        loadCurrent()
    }

    /// Jump to a row in the Up Next list.
    func playFromQueue(at position: Int) {
        guard queue.indices.contains(position) else { return }
        index = position
        loadCurrent()
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        let playing = current
        queue.move(fromOffsets: source, toOffset: destination)
        if let playing, let i = queue.firstIndex(of: playing) { index = i }
    }

    /// Removes upcoming/previous rows. The playing track can't be removed.
    func removeFromQueue(at offsets: IndexSet) {
        let playing = current
        let removed = offsets.filter { $0 != index }.map { queue[$0] }
        queue.remove(atOffsets: IndexSet(offsets.filter { $0 != index }))
        unshuffledQueue?.removeAll { removed.contains($0) }
        if let playing, let i = queue.firstIndex(of: playing) { index = i }
    }

    func playNext(_ item: MediaItem) {
        guard item.isPlayable, current != nil else { return play(item) }
        queue.insert(item, at: index + 1)
        unshuffledQueue?.append(item)
    }

    func addToQueue(_ item: MediaItem) {
        guard item.isPlayable, current != nil else { return play(item) }
        queue.append(item)
        unshuffledQueue?.append(item)
    }

    func toggleShuffle() {
        isShuffled.toggle()
        guard let playing = current else { return }
        if isShuffled {
            unshuffledQueue = queue
            queue = Array(queue[...index]) + queue[(index + 1)...].shuffled()
        } else if let original = unshuffledQueue {
            // Restore the original order; keep anything added while shuffled at the end.
            let originalIDs = Set(original.map(\.id))
            let stillQueued = Set(queue.map(\.id))
            queue = original.filter { stillQueued.contains($0.id) }
                + queue.filter { !originalIDs.contains($0.id) }
            index = queue.firstIndex(of: playing) ?? 0
            unshuffledQueue = nil
        }
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    private func trackDidFinish() {
        if repeatMode == .one {
            restartCurrent()
        } else if hasNext {
            next()
        } else if repeatMode == .all, queue.count > 1 {
            index = 0
            loadCurrent()
        } else {
            parkAtEnd()
        }
    }

    private func parkAtEnd() {
        pause()
        hasEnded = true
        if duration > 0 { currentTime = duration }
        updateNowPlaying()
    }

    /// Resumes playback, restarting the track if it already finished.
    func resume() {
        guard current != nil, isNativeAVPlayer ||
            (isVideoPlayerVisible && UIApplication.shared.applicationState != .background) else { return }
        intendedPlaying = true
        configureAudioSession()

        if hasEnded || (duration > 0 && currentTime >= duration - 0.5) {
            restartCurrent()
        } else if isNativeAVPlayer {
            if avPlayer.currentItem != nil {
                avPlayer.play()
                isPlaying = true
            } else {
                loadCurrent()
            }
        } else if needsFreshLoadOnResume {
            needsFreshLoadOnResume = false
            loadCurrent()
        } else {
            isPlaying = true
            Task { try? await player.play() }
        }
        updateNowPlaying()
    }

    private func restartCurrent() {
        hasEnded = false
        currentTime = 0
        isPlaying = true

        if isNativeAVPlayer {
            guard avPlayer.currentItem != nil else {
                loadCurrent()
                return
            }
            isSeeking = true
            avPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isSeeking = false
                    guard self.intendedPlaying else { return }
                    self.avPlayer.play()
                    self.updateNowPlaying()
                }
            }
        } else {
            // Keep tick() from reading the old end position before the seek lands.
            isSeeking = true
            Task {
                try? await player.seek(to: .init(value: 0, unit: .seconds), allowSeekAhead: true)
                try? await player.play()
                try? await Task.sleep(nanoseconds: 350_000_000)
                isSeeking = false
                updateNowPlaying()
            }
        }
    }

    func pause() {
        intendedPlaying = false
        if isLoading && !isNativeAVPlayer { needsFreshLoadOnResume = true }
        isLoading = false
        currentLoadTask?.cancel()
        if isNativeAVPlayer {
            avPlayer.pause()
        } else {
            Task { try? await player.pause() }
        }
        isPlaying = false
        updateNowPlaying()
    }

    func previous() {
        // Platform convention: restart current track before skipping back.
        if currentTime > 3 || index == 0 {
            seek(to: 0)
            return
        }
        index -= 1
        loadCurrent()
    }

    /// Swiping the artwork always changes track (no restart-first rule).
    func skipToPreviousTrack() {
        guard index > 0 else { return }
        index -= 1
        loadCurrent()
    }

    private func loadCurrent() {
        guard let item = current else { return }

        // Immediately silence and stop any currently playing audio/video from the previous track
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        Task { try? await player.pause() }

        // Immediately reset player progress, state, and UI representations
        currentTime = 0
        isPlaying = false
        isLoading = true
        hasEnded = false
        intendedPlaying = true
        needsFreshLoadOnResume = false
        isSeeking = false

        let expDur = item.durationSeconds.flatMap { Double($0) } ?? 0
        currentExpectedDuration = expDur > 0 ? expDur : nil
        duration = expDur
        configureAudioSession()
        RecentStore.shared.record(item)
        currentLoadTask?.cancel()
        let localURL = DownloadManager.shared.importedAudioURL(for: item.id)
        isNativeAVPlayer = localURL != nil
        updateNowPlaying()
        if let localURL {
            avPlayer.replaceCurrentItem(with: AVPlayerItem(url: localURL))
            avPlayer.play()
            return
        }
        guard isVideoPlayerVisible, UIApplication.shared.applicationState != .background,
              MediaItem.isYouTubeVideoID(item.id) else {
            isLoading = false
            intendedPlaying = false
            needsFreshLoadOnResume = true
            return
        }

        currentLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await player.load(source: .video(id: item.id))
                guard !Task.isCancelled, current?.id == item.id else { return }
                try await Task.sleep(for: .seconds(15))
                guard current?.id == item.id, isLoading else { return }
            } catch {
                guard !Task.isCancelled, current?.id == item.id else { return }
            }
            pause()
            needsFreshLoadOnResume = true
        }
    }

    func togglePlayPause() {
        if isPlaying || isLoading {
            pause()
        } else {
            resume()
        }
    }

    func seek(to seconds: Double) {
        hasEnded = false
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
                guard let self, !self.isScrubbing, !self.isSeeking, self.isNativeAVPlayer, !self.isLoading, self.avPlayer.currentItem != nil else { return }
                let seconds = time.seconds
                if !seconds.isNaN && seconds >= 0 {
                    if self.duration > 0 {
                        self.currentTime = min(seconds, self.duration)
                    } else {
                        self.currentTime = seconds
                    }
                }
                if let currentItem = self.avPlayer.currentItem {
                    let dur = currentItem.duration.seconds
                    if !dur.isNaN && dur > 0 {
                        // Guard against AVFoundation DASH fragmented MP4 double-counting bug (~2x)
                        if let expected = self.currentExpectedDuration, expected > 0 {
                            if dur > expected * 1.5 {
                                self.duration = expected
                            } else {
                                self.duration = dur
                            }
                        } else {
                            self.duration = dur
                        }
                    }
                }

                // Dual-guarantee auto-advance at the end of track
                if self.duration > 0, self.currentTime >= self.duration - 0.5, self.isPlaying {
                    self.trackDidFinish()
                    return
                }
                if self.avPlayer.timeControlStatus == .playing {
                    self.isPlaying = true
                    self.isLoading = false
                } else if self.avPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                    self.isLoading = true
                } else if self.avPlayer.timeControlStatus == .paused {
                    self.isPlaying = false
                    if !self.intendedPlaying {
                        self.isLoading = false
                    }
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
                    if !self.intendedPlaying {
                        self.isLoading = false
                    }
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
            .sink { [weak self] notification in
                // Ignore stale end events from an item that was already replaced
                // (e.g. the periodic observer advanced first), which would skip a track.
                guard let self, self.isNativeAVPlayer,
                      let endedItem = notification.object as? AVPlayerItem,
                      endedItem === self.avPlayer.currentItem else { return }
                self.trackDidFinish()
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

                    guard self.isVideoPlayerVisible,
                          UIApplication.shared.applicationState != .background else {
                        self.pause()
                        return
                    }
                case .buffering:
                    if !self.isPlaying {
                        self.isLoading = true
                    }
                case .paused:
                    self.isPlaying = false
                    if !self.intendedPlaying {
                        self.isLoading = false
                    }
                case .ended:
                    // tick() may already have advanced to the next track, which is loading.
                    guard !self.isLoading else { return }
                    self.isPlaying = false
                    self.trackDidFinish()
                default:
                    break
                }
                self.updateNowPlaying()
            }
    }

    // MARK: - Background Audio Handling

    private func setupBackgroundHandling() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                guard let self, !isNativeAVPlayer else { return }
                pause()
            }
            .store(in: &cancellables)
    }

    private func startTicker() {
        ticker = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.tick() }
            }
    }

    private func tick() async {
        guard hasTrack, !isScrubbing, !isSeeking, !isNativeAVPlayer, !isLoading else { return }

        if let time = try? await player.getCurrentTime() {
            let newTime = time.converted(to: .seconds).value
            if newTime > 0 || currentTime < 1.0 {
                if newTime > 0 && newTime != currentTime {
                    isLoading = false
                }
                currentTime = newTime
            }
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
            if sleepTimerOption == .endOfTrack {
                pause()
                setSleepTimer(.off)
                return
            }
            trackDidFinish()
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
            Task { @MainActor in self?.resume() }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
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

        // Skip ±10s is left disabled: when enabled, iOS shows it on the lock screen
        // in place of previous/next, which the autoplay queue depends on.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false

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
        guard isNativeAVPlayer, let item = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
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
        if let localImage = DownloadManager.shared.localArtworkImage(for: item.id) {
            let artwork = MPMediaItemArtwork(boundsSize: localImage.size) { _ in localImage }
            self.artworkCache = (item.id, artwork)
            self.updateNowPlaying()
            return
        }

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
