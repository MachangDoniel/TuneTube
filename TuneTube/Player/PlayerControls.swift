import AVKit
import SwiftUI

/// Scrubber + times + transport row. Split out of `PlayerView` so the twice-a-
/// second progress updates only re-render this block, not the whole player.
struct PlayerControls: View {
    @Environment(PlayerEngine.self) private var player

    var body: some View {
        VStack(spacing: 18) {
            PlayerScrubberView()
                .id(player.current?.id)
            TransportRow()
        }
    }
}

// MARK: - Scrubber

struct PlayerScrubberView: View {
    @Environment(PlayerEngine.self) private var player
    @State private var scrubValue: Double = 0

    var body: some View {
        let displayTime = player.isScrubbing ? scrubValue : (player.isLoading ? 0 : player.currentTime)

        VStack(spacing: 4) {
            ScrubberBar(
                value: Binding(get: { displayTime }, set: { scrubValue = $0 }),
                range: 0...max(player.duration, 1),
                isDragging: player.isScrubbing,
                onEditingChanged: { editing in
                    guard !player.isLoading else { return }
                    if editing, !player.isScrubbing { scrubValue = displayTime }
                    player.isScrubbing = editing
                    if !editing { player.seek(to: scrubValue) }
                }
            )
            .disabled(player.isLoading)

            HStack {
                Text(PlayerView.time(displayTime))
                Spacer()
                Text(PlayerView.time(player.duration))
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(player.isScrubbing ? Theme.textPrimary : Theme.textSecondary)
        }
    }
}

/// Thin YouTube-Music-style bar: the track thickens and the thumb grows while dragging.
struct ScrubberBar: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let isDragging: Bool
    var onEditingChanged: (Bool) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let span = max(range.upperBound - range.lowerBound, 1)
            let progress = min(max((value - range.lowerBound) / span, 0), 1)
            let thumb: CGFloat = isDragging ? 16 : 11
            let track: CGFloat = isDragging ? 6 : 3

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2)).frame(height: track)
                Capsule().fill(Color.white).frame(width: max(track, width * progress), height: track)
                Circle()
                    .fill(Color.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: width * progress - thumb / 2)
            }
            .frame(height: 28)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: isDragging)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        onEditingChanged(true)
                        let p = min(max(g.location.x / width, 0), 1)
                        value = range.lowerBound + p * span
                    }
                    .onEnded { _ in onEditingChanged(false) }
            )
        }
        .frame(height: 28)
    }
}

// MARK: - Transport

struct TransportRow: View {
    @Environment(PlayerEngine.self) private var player

    var body: some View {
        HStack(spacing: 0) {
            ModeButton(
                systemName: "shuffle",
                isOn: player.isShuffled,
                label: player.isShuffled ? "Shuffle on" : "Shuffle off"
            ) { player.toggleShuffle() }

            Spacer(minLength: 0)

            Button { player.previous() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 30))
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Previous track")

            Spacer(minLength: 0)

            PlayCircleButton(isPlaying: player.isPlaying, isLoading: player.isLoading) {
                player.togglePlayPause()
            }

            Spacer(minLength: 0)

            Button { player.next() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 30))
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .disabled(!player.hasNext)
            .opacity(player.hasNext ? 1 : 0.35)
            .accessibilityLabel("Next track")

            Spacer(minLength: 0)

            ModeButton(
                systemName: player.repeatMode == .one ? "repeat.1" : "repeat",
                isOn: player.repeatMode != .off,
                label: repeatLabel
            ) { player.cycleRepeatMode() }
        }
        .foregroundStyle(Theme.textPrimary)
        .sensoryFeedback(.selection, trigger: player.isShuffled)
        .sensoryFeedback(.selection, trigger: player.repeatMode)
    }

    private var repeatLabel: String {
        switch player.repeatMode {
        case .off: return "Repeat off"
        case .all: return "Repeat all"
        case .one: return "Repeat one"
        }
    }
}

/// Shuffle / repeat: dimmed when off, white with a dot underneath when on.
private struct ModeButton: View {
    let systemName: String
    let isOn: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                Circle()
                    .frame(width: 4, height: 4)
                    .opacity(isOn ? 1 : 0)
            }
            .foregroundStyle(isOn ? Theme.textPrimary : Theme.textSecondary)
            .frame(width: 48, height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }
}

/// The big white disc with a black glyph. While buffering, a ring spins around it.
struct PlayCircleButton: View {
    let isPlaying: Bool
    let isLoading: Bool
    var diameter: CGFloat = 72
    let action: () -> Void

    @State private var spin = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.white)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: diameter * 0.4, weight: .bold))
                    .foregroundStyle(Color.black)
                    // Optical centring: the play triangle looks left-heavy.
                    .offset(x: isPlaying ? 0 : diameter * 0.03)
                    .contentTransition(.symbolEffect(.replace))

                if isLoading && !isPlaying {
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .padding(-6)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .onAppear {
                            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
                        }
                        .onDisappear { spin = false }
                }
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.92))
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.85

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - AirPlay

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor(Theme.accent)
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
