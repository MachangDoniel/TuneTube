import SwiftUI

struct SearchView: View {
    @State private var model = SearchViewModel()
    @Environment(PlayerEngine.self) private var player
    @Environment(Navigator.self) private var navigator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Search")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16)

                searchField

                if model.shelves.isEmpty && !model.isSearching {
                    browseSection
                } else {
                    ForEach(model.shelves) { shelf in
                        ShelfSection(shelf: shelf) { item in
                            navigator.open(item, within: shelf.items, player: player)
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .task {
            await model.loadConfig()
            consumePendingArtist()
        }
        .onChange(of: navigator.pendingArtistSearch) { _, _ in consumePendingArtist() }
    }

    private func consumePendingArtist() {
        guard let name = navigator.pendingArtistSearch else { return }
        navigator.pendingArtistSearch = nil
        model.searchNow(name)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("Search for songs, albums, or artists...", text: $model.query)
                .foregroundStyle(Theme.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onChange(of: model.query) { _, _ in model.queryChanged() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("BROWSE BY MOOD")
                FlowChips(chips: model.config.moodChips) { chip in
                    model.searchNow(chip.label)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("TRENDING SEARCHES").padding(.bottom, 8)
                ForEach(model.config.trendingSearches) { t in
                    Button { model.searchNow(t.label) } label: {
                        HStack(spacing: 12) {
                            Text(t.emoji)
                            Text(t.label)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.vertical, 13)
                        .padding(.horizontal, 14)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Color.white.opacity(0.06))
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
        }
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 16)
    }
}

/// Wrapping chip row. `Layout` keeps it simple without measuring by hand.
struct FlowChips: View {
    let chips: [MoodChip]
    var onTap: (MoodChip) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(chips) { chip in
                Button { onTap(chip) } label: {
                    HStack(spacing: 6) {
                        Text(chip.emoji)
                        Text(chip.label)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.surface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Vertical list section used by Search and detail screens.
struct ShelfSection: View {
    let shelf: Shelf
    var onSelect: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(shelf.title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)
            ForEach(shelf.items) { item in
                TrackRow(item: item) { onSelect(item) }
            }
        }
    }
}

struct TrackRow: View {
    let item: MediaItem
    var subtitlePreference: MediaItem.SubtitlePreference = .automatic
    var trailingIcon: String?
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Artwork(url: item.thumbnailUrl, size: 46,
                        corner: item.kind == .artist ? 23 : 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let sub = item.displaySubtitle(preferring: subtitlePreference) {
                        Text(sub)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
