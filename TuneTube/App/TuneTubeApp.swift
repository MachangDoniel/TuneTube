import SwiftData
import SwiftUI

@main
struct TuneTubeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [LocalPlaylist.self, LocalTrack.self])
    }
}
