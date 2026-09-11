import SwiftUI

/// Plain lyrics for the playing track, following it as the queue advances.
struct LyricsSheet: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case loading
        case loaded(Lyrics)
        case unavailable
        case failed
    }

    @State private var phase: Phase = .loading
    @State private var tint: Color = Theme.surface

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch phase {
                case .loading:
                    ProgressView().tint(.white).frame(maxHeight: .infinity)
                case .loaded(let lyrics):
                    lyricsBody(lyrics)
                case .unavailable:
                    message("Lyrics aren't available for this song.")
                case .failed:
                    message("Couldn't load lyrics.", retry: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            LinearGradient(colors: [tint, Color.black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .task(id: player.current?.id) { await load() }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let item = player.current {
                Artwork(url: item.effectiveThumbnailUrl, size: 40, corner: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(item.displaySubtitle() ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Close lyrics")
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    private func lyricsBody(_ lyrics: Lyrics) -> some View {
        let rtl = Self.isRightToLeft(lyrics.text)
        return ScrollView {
            VStack(alignment: rtl ? .trailing : .leading, spacing: 24) {
                Text(lyrics.text)
                    .font(.system(size: 24, weight: .bold))
                    .lineSpacing(10)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(rtl ? .trailing : .leading)
                    .frame(maxWidth: .infinity, alignment: rtl ? .trailing : .leading)
                    .textSelection(.enabled)

                if let source = lyrics.source {
                    Text("Source: \(source)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    private func message(_ text: String, retry: Bool = false) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 34))
                .foregroundStyle(Theme.textSecondary)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
            if retry {
                Button("Try again") { Task { await load() } }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
        }
        .padding(.bottom, 40)
    }

    private func load() async {
        guard let item = player.current else { return }
        phase = .loading
        if let color = await ArtworkPalette.color(for: item.effectiveThumbnailUrl) {
            withAnimation(.easeInOut(duration: 0.4)) { tint = color }
        }
        do {
            let lyrics = try await APIClient.shared.lyrics(for: item.id)
            guard !Task.isCancelled else { return }
            phase = lyrics.map(Phase.loaded) ?? .unavailable
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
        }
    }

    /// Arabic / Persian / Hebrew lyrics read right-to-left, as in YouTube Music.
    static func isRightToLeft(_ text: String) -> Bool {
        var rtl = 0, ltr = 0
        for scalar in text.unicodeScalars.prefix(400) where scalar.properties.isAlphabetic {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: rtl += 1
            default: ltr += 1
            }
        }
        return rtl > ltr
    }
}
