import SwiftData
import SwiftUI

struct RootView: View {
    @State private var navigator = Navigator()
    private let player = PlayerEngine.shared
    private let store = StoreManager.shared
    private let auth = AuthService.shared
    private let downloadManager = DownloadManager.shared
    private let settings = AppSettings.shared

    var body: some View {
        @Bindable var nav = navigator

        ZStack {
            tabs
                .tint(Theme.accent)
                .environment(navigator)
                .environment(player)
                .environment(store)
                .environment(auth)
                .environment(downloadManager)
                .environment(settings)

            PlayerView()
                .environment(navigator)
                .environment(player)
                .environment(store)
                .environment(auth)
                .environment(downloadManager)
                .environment(settings)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: nav.showPlayer ? 0 : UIScreen.main.bounds.height + 200)
                .allowsHitTesting(nav.showPlayer)
                .animation(.spring(response: 0.36, dampingFraction: 0.88), value: nav.showPlayer)
                .ignoresSafeArea()
        }
        .onChange(of: nav.showPlayer) { _, visible in
            player.isVideoPlayerVisible = visible
        }
        .task {
            await store.bootstrap()
            #if DEBUG
            if let autoPlayID = ProcessInfo.processInfo.environment["TUNETUBE_AUTOPLAY_ID"] {
                let item = MediaItem(id: autoPlayID, kind: .video, title: "Test Video")
                navigator.open(item, within: [item], player: player)
            }
            #endif
        }
        .onOpenURL { url in
            handleURL(url)
        }
        .preferredColorScheme(.dark)
    }

    private func handleURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        switch components.host {
        case "play":
            let id = components.queryItems?.first(where: { $0.name == "id" })?.value ?? ""
            let title = components.queryItems?.first(where: { $0.name == "title" })?.value ?? "Now Playing"
            let artist = components.queryItems?.first(where: { $0.name == "artist" })?.value ?? ""
            let thumb = components.queryItems?.first(where: { $0.name == "thumb" })?.value.flatMap(URL.init(string:))
            let dur = components.queryItems?.first(where: { $0.name == "duration" })?.value.flatMap(Int.init)
            guard !id.isEmpty else { return }
            let item = MediaItem(id: id, kind: .song, title: title, thumbnailUrl: thumb, durationSeconds: dur, artistName: artist.isEmpty ? nil : artist)
            navigator.open(item, within: [item], player: player)
        case "tab":
            if let name = components.queryItems?.first(where: { $0.name == "name" })?.value {
                switch name {
                case "home": navigator.selectedTab = .home
                case "search": navigator.selectedTab = .search
                case "library": navigator.selectedTab = .library
                case "profile": navigator.selectedTab = .profile
                default: break
                }
            }
        case "dismissPlayer":
            navigator.showPlayer = false
        case "togglePlayer":
            navigator.showPlayer.toggle()
        case "forward10":
            player.forward10()
        case "backward10":
            player.backward10()
        case "seek":
            if let toStr = components.queryItems?.first(where: { $0.name == "to" })?.value,
               let seconds = Double(toStr) {
                player.seek(to: seconds)
            }
        default:
            break
        }
    }

    private var tabs: some View {
        tabView
            .overlay(alignment: .bottom) {
                if player.hasTrack {
                    MiniPlayerView()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 50)
                }
            }
    }

    private var tabView: some View {
        @Bindable var nav = navigator
        return TabView(selection: $nav.selectedTab) {
            tab(.home, "Home", "house", path: $nav.homePath) { HomeView() }
            tab(.search, "Search", "magnifyingglass", path: $nav.searchPath) { SearchView() }
            tab(.library, "Library", "music.note.list", path: $nav.libraryPath) { LibraryView() }
            tab(.profile, "Profile", "person", path: $nav.profilePath) { ProfileView() }
        }
    }

    private func tab<Content: View>(
        _ tag: Tab,
        _ title: String,
        _ icon: String,
        path: Binding<[Route]>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        NavigationStack(path: path) {
            content()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .artist(let id, let name):
                        ArtistView(browseId: id, name: name)
                    case .playlist(let id, let title):
                        PlaylistView(playlistId: id, title: title)
                    case .localPlaylist(let id):
                        LocalPlaylistView(playlistId: id)
                    case .downloads:
                        DownloadsView()
                    case .regionPicker:
                        RegionPickerView()
                    case .languagePicker:
                        LanguagePickerView()
                    }
                }
        }
        .tabItem { Label(title, systemImage: icon) }
        .tag(tag)
    }
}
