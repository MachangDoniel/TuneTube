import SwiftUI

@MainActor
@Observable
final class ArtistViewModel {
    private(set) var detail: ArtistDetail?
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    func load(_ browseId: String) async {
        isLoading = true
        do { detail = try await APIClient.shared.artist(browseId) }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

struct ArtistView: View {
    let browseId: String
    let name: String

    @State private var model = ArtistViewModel()
    @Environment(PlayerEngine.self) private var player
    @Environment(Navigator.self) private var navigator

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Artwork(url: model.detail?.thumbnailUrl, size: 160, corner: 80)
                    .padding(.top, 8)

                Text(model.detail?.name ?? name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                if let subs = model.detail?.subscribers {
                    Text(subs)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }

                if model.isLoading && model.detail == nil {
                    VStack(spacing: 8) {
                        ForEach(0..<5, id: \.self) { _ in
                            PlaylistTrackSkeleton()
                        }
                    }
                    .padding(.top, 16)
                }

                ForEach(model.detail?.shelves ?? []) { shelf in
                    if shelf.items.contains(where: { $0.isPlayable }) {
                        // Song shelves read better as a list, with the album as
                        // the subtitle (matching how artist pages present tracks).
                        VStack(alignment: .leading, spacing: 6) {
                            Text(shelf.title)
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                            ForEach(shelf.items) { item in
                                TrackRow(item: item,
                                         subtitlePreference: .album,
                                         trailingIcon: "plus.circle") {
                                    navigator.open(item, within: shelf.items, player: player)
                                }
                            }
                        }
                    } else {
                        ShelfRow(shelf: shelf) { item in
                            navigator.open(item, within: shelf.items, player: player)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(browseId) }
    }
}
