import AVFoundation
import Foundation

/// Keeps the app's `AVAudioSession` actively producing audio in the background.
///
/// Under iOS `UIBackgroundModes: ["audio"]`, iOS allows apps to run in the background
/// only while an active audio client in the host app process is outputting sound.
/// Since `WKWebView` runs out-of-process, this silent audio player keeps the main
/// app process awake so WebKit media playback and MPRemoteCommandCenter do not suspend
/// when the user locks the screen or switches apps.
final class SilentAudioPlayer {
    static let shared = SilentAudioPlayer()

    private var audioPlayer: AVAudioPlayer?
    private(set) var isRunning = false

    private init() {
        setupAudioPlayer()
    }

    private func setupAudioPlayer() {
        let wavData = createSilentWAVData()
        do {
            let player = try AVAudioPlayer(data: wavData)
            player.numberOfLoops = -1 // Loop infinitely
            player.volume = 1.0       // Full volume of inaudible -80dBFS micro-waveform to keep audio engine active
            player.prepareToPlay()
            audioPlayer = player
        } catch {
            print("[SilentAudioPlayer] Initialization error: \(error)")
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            if type == .ended {
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) && self.isRunning {
                        self.audioPlayer?.play()
                    }
                }
            }
        }
    }

    func play() {
        configureSession()
        guard !isRunning else {
            if audioPlayer?.isPlaying == false {
                audioPlayer?.play()
            }
            return
        }
        audioPlayer?.play()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        audioPlayer?.pause()
        isRunning = false
    }

    private func configureSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Do NOT include .mixWithOthers: setting mixWithOthers forfeits primary playback
            // privileges and causes iOS to suspend the app when backgrounded or locked.
            try session.setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.allowAirPlay, .allowBluetoothHFP, .allowBluetoothA2DP]
            )
            try session.setActive(true)
        } catch {
            print("[SilentAudioPlayer] Audio session error: \(error)")
        }
    }

    /// Generates a valid 2-second 44.1kHz 16-bit mono PCM WAV file containing an inaudible
    /// 20Hz micro-waveform (amplitude 3 / 32767 = -80.7 dBFS).
    ///
    /// CoreAudio's silence detection circuit inspects hardware audio buffers for non-zero PCM energy.
    /// Pure zero buffers are detected as idle and suspended after ~14s by iOS power management.
    /// Non-zero PCM energy ensures the audio route and background execution stay active indefinitely.
    private func createSilentWAVData() -> Data {
        let sampleRate: Int32 = 44100
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let durationSeconds: Int32 = 2
        let numSamples = Int(sampleRate * durationSeconds)
        let subchunk2Size = Int32(numSamples * Int(numChannels) * Int(bitsPerSample / 8))
        let chunkSize = 36 + subchunk2Size

        var data = Data()

        // RIFF header
        data.append(contentsOf: [UInt8]("RIFF".utf8))
        var cs = chunkSize.littleEndian
        data.append(Data(bytes: &cs, count: 4))
        data.append(contentsOf: [UInt8]("WAVE".utf8))

        // fmt subchunk
        data.append(contentsOf: [UInt8]("fmt ".utf8))
        var subchunk1Size = Int32(16).littleEndian
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat = Int16(1).littleEndian // PCM
        data.append(Data(bytes: &audioFormat, count: 2))
        var nc = numChannels.littleEndian
        data.append(Data(bytes: &nc, count: 2))
        var sr = sampleRate.littleEndian
        data.append(Data(bytes: &sr, count: 4))
        var byteRate = (sampleRate * Int32(numChannels) * Int32(bitsPerSample / 8)).littleEndian
        data.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = (numChannels * (bitsPerSample / 8)).littleEndian
        data.append(Data(bytes: &blockAlign, count: 2))
        var bps = bitsPerSample.littleEndian
        data.append(Data(bytes: &bps, count: 2))

        // data subchunk
        data.append(contentsOf: [UInt8]("data".utf8))
        var sc2 = subchunk2Size.littleEndian
        data.append(Data(bytes: &sc2, count: 4))

        // Inaudible 20Hz micro-sine waveform (-80.7 dBFS). Completely inaudible,
        // yet provides active non-zero PCM energy to satisfy iOS power management.
        for i in 0..<numSamples {
            let angle = 2.0 * Double.pi * 20.0 * Double(i) / Double(sampleRate)
            let sampleVal = Int16(round(sin(angle) * 3.0))
            var sampleLE = sampleVal.littleEndian
            data.append(Data(bytes: &sampleLE, count: 2))
        }

        return data
    }
}
