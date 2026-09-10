import Foundation
import SwiftUI

enum PlayerDisplayMode: String, CaseIterable, Sendable {
    case song = "Song"
    case video = "Video"
}

enum Tab: Hashable { case home, search, library, profile }

enum Route: Hashable {
    case artist(id: String, name: String)
    case playlist(id: String, title: String)
    case localPlaylist(id: UUID)
}

/// Owns tab selection and a navigation path per tab, so pushing a detail screen
/// from Search doesn't also push it onto Home.
@MainActor
@Observable
final class Navigator {
    var selectedTab: Tab = .home
    var homePath: [Route] = []
    var searchPath: [Route] = []
    var libraryPath: [Route] = []
    var profilePath: [Route] = []

    /// Signed-out placeholder; replaced by the account name once auth lands.
    var userFirstName = "there"

    var showPlayer = false
    var playerDisplayMode: PlayerDisplayMode = .song

    /// "Go to Artist" from the player: songs carry an artist name but no artist
    /// browseId, so we hand the name to Search to resolve.
    var pendingArtistSearch: String?

    func push(_ route: Route) {
        switch selectedTab {
        case .home: homePath.append(route)
        case .search: searchPath.append(route)
        case .library: libraryPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    /// Single entry point for "user tapped a card". Playable items start
    /// playback in the context of their shelf; containers push a detail screen.
    func open(_ item: MediaItem, within context: [MediaItem] = [], player: PlayerEngine? = nil) {
        let activePlayer = player ?? PlayerEngine.shared
        switch item.kind {
        case .song:
            playerDisplayMode = .song
            activePlayer.displayMode = .song
            activePlayer.play(item, in: context)
            showPlayer = true
        case .video:
            playerDisplayMode = .video
            activePlayer.displayMode = .video
            activePlayer.play(item, in: context)
            showPlayer = true
        case .artist:
            push(.artist(id: item.id, name: item.title))
        case .playlist, .album:
            push(.playlist(id: item.playlistId ?? item.id, title: item.title))
        }
    }
}
