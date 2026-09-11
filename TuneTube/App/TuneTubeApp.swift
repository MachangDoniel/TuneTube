import SwiftData
import SwiftUI
#if DEBUG
import DebugSwift
#endif

@main
struct TuneTubeApp: App {
    #if DEBUG
    private let debugger = DebugSwift()
    #endif

    init() {
        #if DEBUG
        debugger.setup().show()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [LocalPlaylist.self, LocalTrack.self])
    }
}
