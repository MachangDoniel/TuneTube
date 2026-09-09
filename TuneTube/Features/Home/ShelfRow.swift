import SwiftUI

struct ShelfRow: View {
    let shelf: Shelf
    var onSelect: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(shelf.title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(shelf.items) { item in
                        MediaCard(item: item) { onSelect(item) }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// Placeholder shown while the first fetch is in flight.
struct ShelfSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.surfaceHigh)
                .frame(width: 140, height: 18)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: Theme.cardCorner)
                                .fill(Theme.surfaceHigh)
                                .frame(width: Theme.cardSize, height: Theme.cardSize)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.surfaceHigh)
                                .frame(width: 110, height: 12)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .redacted(reason: .placeholder)
    }
}
