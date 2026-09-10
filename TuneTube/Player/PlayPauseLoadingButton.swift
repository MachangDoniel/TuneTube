import SwiftUI

/// Custom Play/Pause button that replaces the generic loading spinner with
/// a `| |` (pause) icon surrounded by an animated circling progress ring.
struct PlayPauseLoadingButton: View {
    let isPlaying: Bool
    let isLoading: Bool
    var iconSize: CGFloat = 38
    var frameSize: CGFloat = 52
    var ringLineWidth: CGFloat = 2.5

    @State private var isSpinning = false

    var body: some View {
        ZStack {
            if isLoading && !isPlaying {
                // Circling loading ring when waiting for track to buffer before playback starts
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(
                        Color.white,
                        style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                    )
                    .frame(width: frameSize - 6, height: frameSize - 6)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .onAppear {
                        withAnimation(
                            .linear(duration: 0.9).repeatForever(autoreverses: false)
                        ) {
                            isSpinning = true
                        }
                    }
                    .onDisappear {
                        isSpinning = false
                    }

                Image(systemName: "play.fill")
                    .font(.system(size: iconSize * 0.75))
                    .foregroundStyle(Color.white.opacity(0.8))
            } else {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: frameSize, height: frameSize)
        .contentShape(Rectangle())
    }
}
