import Foundation
import SwiftData

/// A user playlist stored on device.
///
/// `isDefault` marks the seeded "Favourites" list. It is the one playlist a free
/// user gets, and it can never be deleted or renamed — deleting it would leave a
/// free user with no library at all.
@Model
final class LocalPlaylist {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var isDefault: Bool = false
    var iconName: String = "heart.fill"
    var colorHex: String = "#FF2D55"

    @Relationship(deleteRule: .cascade, inverse: \LocalTrack.playlist)
    var tracks: [LocalTrack] = []

    init(name: String, isDefault: Bool = false, iconName: String = "heart.fill", colorHex: String = "#FF2D55") {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.isDefault = isDefault
        self.iconName = iconName
        self.colorHex = colorHex
    }

    var orderedTracks: [LocalTrack] {
        tracks.sorted { $0.addedAt < $1.addedAt }
    }
}

@Model
final class LocalTrack {
    var videoId: String = ""
    var title: String = ""
    var subtitle: String?
    var artistName: String?
    var albumName: String?
    var thumbnailURLString: String?
    var durationSeconds: Int?
    var addedAt: Date = Date()
    var playlist: LocalPlaylist?

    init(from item: MediaItem) {
        videoId = item.id
        title = item.title
        subtitle = item.subtitle
        artistName = item.artistName
        albumName = item.albumName
        thumbnailURLString = item.thumbnailUrl?.absoluteString
        durationSeconds = item.durationSeconds
        addedAt = Date()
    }

    /// Back to the shared shape the player and rows already understand.
    var asMediaItem: MediaItem {
        MediaItem(
            id: videoId,
            kind: .song,
            title: title,
            subtitle: subtitle,
            thumbnailUrl: thumbnailURLString.flatMap(URL.init(string:)),
            durationSeconds: durationSeconds,
            playlistId: nil,
            artistName: artistName,
            albumName: albumName
        )
    }
}
