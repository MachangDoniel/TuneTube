import MediaPlayer
import SwiftData
import SwiftUI
import YouTubePlayerKit

struct PlayerView: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(Navigator.self) private var navigator
    @Environment(\.modelContext) private var context

    private var library: LibraryStore { LibraryStore(context: context) }

    @State private var showActions = false
    @State private var showAddToPlaylist = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top Bar: Down chevron icon at top left, grabber pill at top center
                HStack {
                    Button { closePlayer() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.12), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .highPriorityGesture(TapGesture().onEnded { closePlayer() })
                    .accessibilityLabel("Close player")

                    Spacer()

                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 38, height: 5)
                        .contentShape(Rectangle().size(width: 60, height: 24))
                        .onTapGesture { closePlayer() }

                    Spacer()

                    // Symmetrical frame so the grabber pill stays perfectly centered
                    Color.clear
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal, 20)
                .padding(.top, max(geometry.safeAreaInsets.top + 8, 54))

                if player.current == nil {
                    emptyStateView
                } else {
                    playerContentView(geometry: geometry)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.11, green: 0.11, blue: 0.12).ignoresSafeArea())
            .offset(y: max(0, dragOffset))
            .gesture(
                DragGesture(minimumDistance: 25)
                    .onChanged { value in
                        if value.translation.height > 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 100 {
                            closePlayer()
                        }
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .confirmationDialog("", isPresented: $showActions) {
            Button("Go to Artist") { goToArtist() }
            Button("Add to Playlist") { showAddToPlaylist = true }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showAddToPlaylist) {
            if let item = player.current {
                AddToPlaylistSheet(item: item)
            }
        }
    }

    // MARK: - Player Content

    private func playerContentView(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Song / Video Toggle
            HStack(spacing: 0) {
                ForEach(PlayerDisplayMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            navigator.playerDisplayMode = mode
                            player.setDisplayMode(mode)
                        }
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(navigator.playerDisplayMode == mode ? Theme.textPrimary : Theme.textSecondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                            .background(
                                navigator.playerDisplayMode == mode ? Color.white.opacity(0.18) : Color.clear,
                                in: Capsule()
                            )
                    }
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.08), in: Capsule())
            .padding(.top, 10)
            .padding(.bottom, 6)

            Spacer()

            // Media Display Area: Live YouTube Video or Square Artwork Card
            VStack(spacing: 14) {
                if let item = player.current {
                    if navigator.playerDisplayMode == .video {
                        YouTubePlayerView(player.player) { state in
                            switch state {
                            case .idle:
                                Color.black.overlay(ProgressView().tint(.white))
                            case .ready:
                                EmptyView()
                            case .error:
                                Color.black.overlay(
                                    Text("Can't play this track")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Theme.textSecondary)
                                )
                            }
                        }
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                        .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 8)
                        .padding(.horizontal, 20)
                    } else {
                        let cardSize = min(geometry.size.width - 48, geometry.size.height * 0.40)
                        ZStack {
                            Theme.surfaceHigh

                            CachedImage(url: item.effectiveThumbnailUrl, contentMode: .fill) {
                                Theme.surfaceHigh
                                    .overlay(
                                        Image(systemName: "music.note")
                                            .font(.system(size: 52))
                                            .foregroundStyle(Theme.textSecondary)
                                    )
                            }
                        }
                        .frame(width: cardSize, height: cardSize)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                        .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 8)
                        .id(item.id)
                    }
                }

                // Previous and Next directly at the bottom of the video preview with button labels
                HStack {
                    Button { player.previous() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left.2")
                                .font(.system(size: 13, weight: .bold))
                            Text("Prev")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.12), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .disabled(!player.hasPrevious)
                    .opacity(player.hasPrevious ? 1.0 : 0.35)
                    .accessibilityLabel("Previous track")

                    Spacer()

                    Button { player.next() } label: {
                        HStack(spacing: 6) {
                            Text("Next")
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: "chevron.right.2")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.12), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .disabled(!player.hasNext)
                    .opacity(player.hasNext ? 1.0 : 0.35)
                    .accessibilityLabel("Next track")
                }
                .padding(.horizontal, 20)
            }

            Spacer()

            // Metadata & Controls
            VStack(spacing: 18) {
                // Song name on the left, Love button & 3-dot options at the right side
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.current?.title ?? "")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)

                        Text(player.current?.displaySubtitle() ?? "")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()

                    // Favorite Love Button
                    if let current = player.current {
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) {
                                library.toggleFavourite(current)
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } label: {
                            let isFav = library.isFavourite(current)
                            Image(systemName: isFav ? "heart.fill" : "heart")
                                .font(.system(size: 22))
                                .foregroundStyle(isFav ? .pink : Theme.textSecondary)
                                .scaleEffect(isFav ? 1.08 : 1.0)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(library.isFavourite(current) ? "Remove from Favourites" : "Add to Favourites")
                    }

                    Button { showActions = true } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("More options")
                }

                // Scrubber with circular thumb head
                scrubber

                // Transport controls: Previous, Rewind 10, Play/Pause with loading ring, Forward 10, Next
                transportControls
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 44)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "music.note")
                .font(.system(size: 52))
                .foregroundStyle(Theme.accent)
                .frame(width: 96, height: 96)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))

            VStack(spacing: 8) {
                Text("Nothing Playing")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Pick a song or video from Home or Search to begin playback.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        PlayerScrubberView()
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: 0) {
            // Rewind 10 seconds
            Button {
                player.backward10()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 26))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    player.previous()
                }
            )
            .accessibilityLabel("Rewind 10 seconds")

            // Play / Pause with circling loading indicator
            Button { player.togglePlayPause() } label: {
                PlayPauseLoadingButton(
                    isPlaying: player.isPlaying,
                    isLoading: player.isLoading,
                    iconSize: 36,
                    frameSize: 56
                )
                .frame(maxWidth: .infinity)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            // Forward 10 seconds
            Button {
                player.forward10()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 26))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    player.next()
                }
            )
            .accessibilityLabel("Forward 10 seconds")
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.vertical, 8)
    }

    private func closePlayer() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
            navigator.showPlayer = false
        }
    }

    private func goToArtist() {
        guard let name = player.current?.artistName else { return }
        closePlayer()
        navigator.selectedTab = .search
        navigator.pendingArtistSearch = name
    }

    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

/// Custom slider featuring a sleek, circular thumb head.
struct CustomCircularSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onEditingChanged: (Bool) -> Void

    private let thumbSize: CGFloat = 13

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let progress = max(0, min(1, (value - range.lowerBound) / max(1, range.upperBound - range.lowerBound)))
            let thumbX = progress * (totalWidth - thumbSize)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 3.5)

                Capsule()
                    .fill(Color.white)
                    .frame(width: thumbX + thumbSize / 2, height: 3.5)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.35), radius: 2.5, y: 1)
                    .offset(x: thumbX)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        onEditingChanged(true)
                        let newProgress = max(0, min(1, gesture.location.x / totalWidth))
                        value = range.lowerBound + newProgress * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 24)
    }
}

/// Isolated scrubber subview so high-frequency updates don't churn parent layout.
struct PlayerScrubberView: View {
    @Environment(PlayerEngine.self) private var player
    @State private var scrubValue: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            CustomCircularSlider(
                value: Binding(
                    get: { player.isScrubbing ? scrubValue : player.currentTime },
                    set: { scrubValue = $0 }
                ),
                range: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    player.isScrubbing = editing
                    if !editing { player.seek(to: scrubValue) }
                }
            )

            HStack {
                Text(PlayerView.time(player.isScrubbing ? scrubValue : player.currentTime))
                Spacer()
                Text(PlayerView.time(player.duration))
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
        }
    }
}
