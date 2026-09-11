import SwiftData
import SwiftUI
import YouTubePlayerKit

/// Full-screen player, laid out after YouTube Music: big artwork, title, a
/// scrollable row of action chips, scrubber, transport, and Up next / Lyrics tabs.
struct PlayerView: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(Navigator.self) private var navigator
    @Environment(\.modelContext) private var context

    private var library: LibraryStore { LibraryStore(context: context) }

    @State private var showAddToPlaylist = false
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var dragOffset: CGFloat = 0
    /// Translation at which the current pull-down was recognised; offsets are
    /// measured from here so the player doesn't jump by the recognition distance.
    @State private var dismissDragBase: CGFloat?
    @State private var isFavourite = false
    @State private var tint: Color = Color(white: 0.14)
    @State private var seekFlash: SeekFlash?
    /// Horizontal drag of the artwork carousel, and which axis the current drag locked to.
    @State private var swipeOffset: CGFloat = 0
    @State private var dragAxis: Axis?

    private enum SeekFlash: Equatable { case back, forward }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, max(geometry.safeAreaInsets.top + 4, 50))

                if player.current == nil {
                    emptyStateView
                } else {
                    playerContent(geometry: geometry)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
            .offset(y: max(0, dragOffset))
            // Global space: this view moves with the drag, so local coordinates would
            // shift under the finger and make the offset jitter.
            .gesture(
                DragGesture(minimumDistance: 25, coordinateSpace: .global)
                    .onChanged { value in updateDismissDrag(value.translation.height) }
                    .onEnded { value in
                        endDismissDrag(value.translation.height,
                                       predicted: value.predictedEndTranslation.height)
                    }
            )
        }
        .ignoresSafeArea()
        // The player stays mounted off-screen, so resync when the track changes or
        // the player opens (the song may have been unfavourited from Library).
        .onChange(of: player.current?.id, initial: true) { syncFavourite() }
        .onChange(of: navigator.showPlayer) { syncFavourite() }
        .task(id: player.current?.effectiveThumbnailUrl) { await updateTint() }
        .sheet(isPresented: $showAddToPlaylist) {
            if let item = player.current {
                AddToPlaylistSheet(item: item)
            }
        }
        .sheet(isPresented: $showQueue) { UpNextSheet() }
        .sheet(isPresented: $showLyrics) { LyricsSheet() }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [tint, tint.opacity(0.55), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func updateTint() async {
        let url = player.current?.effectiveThumbnailUrl
        if let cached = ArtworkPalette.cachedColor(for: url) {
            tint = cached
            return
        }
        guard let color = await ArtworkPalette.color(for: url), !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.6)) { tint = color }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 4) {
            Button { closePlayer() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close player")

            Spacer()

            AirPlayButton()
                .frame(width: 40, height: 40)
                .accessibilityLabel("AirPlay")

            moreMenu
        }
        .foregroundStyle(Theme.textPrimary)
        .overlay {
            if player.current != nil { displayModeToggle }
        }
    }

    /// Song / Video switch, drawn as two icons in a capsule.
    private var displayModeToggle: some View {
        HStack(spacing: 2) {
            ForEach(PlayerDisplayMode.allCases, id: \.self) { mode in
                let selected = navigator.playerDisplayMode == mode
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        navigator.playerDisplayMode = mode
                        player.setDisplayMode(mode)
                    }
                } label: {
                    Image(systemName: mode == .song ? "headphones" : "play.rectangle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? Color.black : Theme.textSecondary)
                        .frame(width: 42, height: 28)
                        .background(selected ? Color.white : Color.clear, in: Capsule())
                }
                .accessibilityLabel(mode.rawValue)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.12), in: Capsule())
    }

    private var moreMenu: some View {
        Menu {
            if player.current != nil {
                Button { player.startMix(); showQueue = true } label: {
                    Label("Start mix", systemImage: "dot.radiowaves.left.and.right")
                }
                Button { showAddToPlaylist = true } label: {
                    Label("Add to playlist", systemImage: "text.badge.plus")
                }
                Button { showLyrics = true } label: {
                    Label("Lyrics", systemImage: "quote.bubble")
                }
                if player.current?.artistName != nil {
                    Button { goToArtist() } label: {
                        Label("Go to artist", systemImage: "person")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More options")
    }

    // MARK: - Player content

    private func playerContent(geometry: GeometryProxy) -> some View {
        let side = min(geometry.size.width - 32, geometry.size.height * 0.42)

        return VStack(spacing: 0) {
            Spacer(minLength: 12)

            media(side: side, width: geometry.size.width - 32,
                  // Far enough that the neighbouring covers sit just off-screen at rest.
                  step: max(side + 20, (geometry.size.width + side) / 2 + 8))

            Spacer(minLength: 16)

            VStack(alignment: .leading, spacing: 18) {
                titleBlock
                    .padding(.horizontal, 24)

                actionChips

                PlayerControls()
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 12)

            bottomTabs
                .padding(.bottom, max(geometry.safeAreaInsets.bottom, 20))
        }
    }

    // MARK: Media

    private func media(side: CGFloat, width: CGFloat, step: CGFloat) -> some View {
        let isVideo = navigator.playerDisplayMode == .video
        let videoHeight = width * 9 / 16

        return ZStack {
            if let item = player.current {
                artworkCarousel(item, side: side, step: step)
                    .opacity(isVideo ? 0 : 1)
                    .allowsHitTesting(!isVideo)
            }

            // Must stay mounted: it's the iframe player for video mode.
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
            .frame(width: width, height: videoHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isVideo ? 1 : 0)
            .allowsHitTesting(isVideo)
        }
        // Same height in both modes (the video is centred in the artwork's slot),
        // so switching Song/Video never shifts the title and controls.
        .frame(height: max(side, videoHeight))
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: navigator.playerDisplayMode)
    }

    /// Current cover with the previous/next covers parked either side. Swipe left
    /// for the next track, right for the previous one.
    private func artworkCarousel(_ item: MediaItem, side: CGFloat, step: CGFloat) -> some View {
        ZStack {
            if let previous = player.previousItem {
                artworkImage(previous, side: side)
                    .offset(x: swipeOffset - step)
            }

            artworkImage(item, side: side)
                .overlay(alignment: seekFlash == .back ? .leading : .trailing) {
                    if let seekFlash {
                        Image(systemName: seekFlash == .back ? "gobackward.10" : "goforward.10")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(24)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .offset(x: swipeOffset)

            if let next = player.nextItem {
                artworkImage(next, side: side)
                    .offset(x: swipeOffset + step)
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        // Double-tap left/right half to skip back/forward 10s, like YouTube.
        .onTapGesture(count: 2) { location in
            seek(location.x < side / 2 ? .back : .forward)
        }
        .gesture(artworkDrag(step: step))
        .accessibilityAction(named: "Next track") { player.next() }
        .accessibilityAction(named: "Previous track") { player.skipToPreviousTrack() }
        .accessibilityAction(named: "Skip back 10 seconds") { seek(.back) }
        .accessibilityAction(named: "Skip forward 10 seconds") { seek(.forward) }
    }

    private func artworkImage(_ item: MediaItem, side: CGFloat) -> some View {
        CachedImage(url: item.effectiveThumbnailUrl, contentMode: .fill) {
            Theme.surfaceHigh.overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.textSecondary)
            )
        }
        .frame(width: side, height: side)
        .scaleEffect(item.thumbnailLetterboxScale)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        // New identity per track, so CachedImage seeds from the memory cache on
        // its first frame instead of briefly showing the old cover.
        .id(item.id)
    }

    /// Locks to an axis on the first movement: horizontal swipes the carousel,
    /// vertical falls through to pull-down-to-close.
    private func artworkDrag(step: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                let t = value.translation
                if dragAxis == nil {
                    dragAxis = abs(t.width) > abs(t.height) ? .horizontal : .vertical
                }
                if dragAxis == .horizontal {
                    // Rubber-band when there's no track in that direction.
                    let blocked = (t.width < 0 && player.nextItem == nil)
                        || (t.width > 0 && player.previousItem == nil)
                    swipeOffset = blocked ? t.width / 4 : t.width
                } else {
                    updateDismissDrag(t.height)
                }
            }
            .onEnded { value in
                let axis = dragAxis
                dragAxis = nil
                if axis == .horizontal {
                    finishSwipe(predictedWidth: value.predictedEndTranslation.width, step: step)
                } else {
                    endDismissDrag(value.translation.height,
                                   predicted: value.predictedEndTranslation.height)
                }
            }
    }

    private func finishSwipe(predictedWidth: CGFloat, step: CGFloat) {
        // Predicted end includes velocity, so a quick flick counts as well as a long drag.
        let threshold = step * 0.35
        let direction: CGFloat
        if predictedWidth < -threshold, player.nextItem != nil {
            direction = -1
        } else if predictedWidth > threshold, player.previousItem != nil {
            direction = 1
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { swipeOffset = 0 }
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.22)) {
            swipeOffset = direction * step
        } completion: {
            // The neighbour is now centred: swap the track and recentre in one
            // un-animated step, so the swap itself is invisible.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if direction < 0 { player.next() } else { player.skipToPreviousTrack() }
                swipeOffset = 0
            }
        }
    }

    private func seek(_ direction: SeekFlash) {
        direction == .back ? player.backward10() : player.forward10()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.15)) { seekFlash = direction }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard seekFlash == direction else { return }
            withAnimation(.easeIn(duration: 0.25)) { seekFlash = nil }
        }
    }

    // MARK: Title & chips

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(player.current?.title ?? "")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Button { goToArtist() } label: {
                Text(player.current?.displaySubtitle() ?? "")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .disabled(player.current?.artistName == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let current = player.current {
                    Button { toggleFavourite(current) } label: {
                        ChipLabel(
                            systemName: isFavourite ? "heart.fill" : "heart",
                            title: isFavourite ? "Favourited" : "Favourite",
                            iconColor: isFavourite ? .pink : Theme.textPrimary
                        )
                        .symbolEffect(.bounce, value: isFavourite)
                    }
                    .accessibilityLabel(isFavourite ? "Remove from Favourites" : "Add to Favourites")

                    Button { showLyrics = true } label: {
                        ChipLabel(systemName: "quote.bubble", title: "Lyrics")
                    }

                    Button { showAddToPlaylist = true } label: {
                        ChipLabel(systemName: "text.badge.plus", title: "Save")
                    }

                    if let url = URL(string: "https://music.youtube.com/watch?v=\(current.id)") {
                        ShareLink(item: url, subject: Text(current.title)) {
                            ChipLabel(systemName: "arrowshape.turn.up.right", title: "Share")
                        }
                    }

                    Button { player.startMix(); showQueue = true } label: {
                        ChipLabel(systemName: "dot.radiowaves.left.and.right", title: "Mix")
                    }
                }
            }
            .buttonStyle(PressScaleStyle(scale: 0.94))
            .padding(.horizontal, 24)
        }
    }

    // MARK: Bottom tabs

    private var bottomTabs: some View {
        HStack(spacing: 0) {
            tabButton("UP NEXT") { showQueue = true }
            tabButton("LYRICS") { showLyrics = true }
        }
        .padding(.horizontal, 24)
        .contentShape(Rectangle())
        // Swipe up from the bottom opens the queue.
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                if value.translation.height < -40 { showQueue = true }
            }
        )
    }

    private func tabButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    // MARK: - Actions

    private func toggleFavourite(_ item: MediaItem) {
        // Flip the local state first so the heart reacts on the same frame, then persist.
        let newValue = !isFavourite
        withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) {
            isFavourite = newValue
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        library.setFavourite(item, newValue)
    }

    private func updateDismissDrag(_ translation: CGFloat) {
        if dismissDragBase == nil { dismissDragBase = max(0, translation) }
        dragOffset = max(0, translation - (dismissDragBase ?? 0))
    }

    private func endDismissDrag(_ translation: CGFloat, predicted: CGFloat) {
        let base = dismissDragBase ?? 0
        dismissDragBase = nil
        // Close on a long pull or a quick downward flick.
        if translation - base > 100 || predicted - base > 260 {
            closePlayer()
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                dragOffset = 0
            }
        }
    }

    private func closePlayer() {
        // Slide away from wherever the drag left it; only reset the drag offset
        // once off-screen, or it springs back up while sliding down.
        withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
            navigator.showPlayer = false
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { dragOffset = 0 }
        }
    }

    private func syncFavourite() {
        isFavourite = player.current.map { library.isFavourite($0) } ?? false
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

/// Capsule chip in the row under the title (Favourite, Lyrics, Save, Share, Mix).
private struct ChipLabel: View {
    let systemName: String
    let title: String
    var iconColor: Color = Theme.textPrimary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Color.white.opacity(0.12), in: Capsule())
        .contentShape(Capsule())
    }
}
