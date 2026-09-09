import SwiftData
import SwiftUI

struct RootView: View {
    @State private var navigator = Navigator()
    private let player = PlayerEngine.shared
    private let store = StoreManager.shared
    private let auth = AuthService.shared

    var body: some View {
        @Bindable var nav = navigator

        tabs
            .tint(Theme.accent)
            .environment(navigator)
            .environment(player)
            .environment(store)
            .environment(auth)
            .sheet(isPresented: $nav.showPlayer) {
                PlayerView()
                    .environment(navigator)
                    .environment(player)
                    .environment(store)
            }
            .task { await store.bootstrap() }
            .preferredColorScheme(.dark)
    }

    /// The mini player has to sit ABOVE the tab bar, never over it.
    ///
    /// iOS 26 gives us the purpose-built accessory slot for exactly this. On
    /// earlier versions we fall back to a safe-area inset on the TabView —
    /// which must stay on the TabView itself: moving it inside a tab's
    /// NavigationStack stops it re-evaluating when the player goes from
    /// "nothing loaded" to "playing", and the bar silently never appears.
    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 26.0, *) {
            tabView.tabViewBottomAccessory { MiniPlayerView() }
        } else {
            tabView.safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerView() }
        }
    }

    private var tabView: some View {
        @Bindable var nav = navigator
        return TabView(selection: $nav.selectedTab) {
            tab(.home, "Home", "house") { HomeView() }
            tab(.search, "Search", "magnifyingglass") { SearchView() }
            tab(.library, "Library", "music.note.list") { LibraryView() }
            tab(.profile, "Profile", "person") { ProfileView() }
        }
    }

    private func tab<Content: View>(
        _ tag: Tab,
        _ title: String,
        _ icon: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        NavigationStack(path: navigator.path(for: tag)) {
            content()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .artist(let id, let name):
                        ArtistView(browseId: id, name: name)
                    case .playlist(let id, let title):
                        PlaylistView(playlistId: id, title: title)
                    case .localPlaylist(let id):
                        LocalPlaylistView(playlistId: id)
                    }
                }
        }
        .tabItem { Label(title, systemImage: icon) }
        .tag(tag)
    }
}
