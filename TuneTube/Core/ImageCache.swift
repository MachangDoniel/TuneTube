import SwiftUI
import UIKit

/// Shared artwork loader.
///
/// `AsyncImage` has no cache: every instance refetches, and every instance
/// starts in its `.empty` phase. In a shelf-based UI where the same thumbnail
/// appears in a card, a row, the mini player and the lock screen, that reads as
/// constant flicker and spinners.
///
/// This fixes the three causes:
///  * a memory cache that can be read *synchronously*, so a warm image renders
///    on the very first frame with no loading state at all;
///  * a disk cache, so artwork survives relaunch and works offline;
///  * request coalescing, so N views asking for the same URL trigger one fetch.
/// NSCache is documented as thread-safe, but it is not `Sendable`, so it is
/// boxed here rather than marked `nonisolated` on the actor (which is an error
/// under the Swift 6 language mode).
private final class ImageMemoryCache: @unchecked Sendable {
    private let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 400
        cache.totalCostLimit = 64 * 1024 * 1024   // ~64 MB of decoded images
        return cache
    }()

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL, cost: image.estimatedCost)
    }
}

actor ImageLoader {
    static let shared = ImageLoader()

    private nonisolated let memory = ImageMemoryCache()

    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    private nonisolated let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("TuneTubeArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Synchronous memory peek. This is what removes the flicker: a view that
    /// already has its image never renders a placeholder.
    nonisolated func cached(_ url: URL) -> UIImage? {
        memory.image(for: url)
    }

    func image(for url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }

        // Coalesce: if this URL is already loading, await the same task rather
        // than starting a second identical request.
        if let existing = inFlight[url] { return await existing.value }

        let task = Task<UIImage?, Never> { [directory] in
            let fileURL = directory.appendingPathComponent(Self.filename(for: url))

            if let data = try? Data(contentsOf: fileURL),
               let image = UIImage(data: data) {
                return image
            }

            guard
                let (data, response) = try? await URLSession.shared.data(from: url),
                let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                let image = UIImage(data: data)
            else { return nil }

            try? data.write(to: fileURL, options: .atomic)
            return image
        }

        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil

        if let image { memory.store(image, for: url) }
        return image
    }

    private nonisolated static func filename(for url: URL) -> String {
        // Stable, filesystem-safe, and collision-resistant enough for artwork.
        var hash: UInt64 = 5381
        for byte in url.absoluteString.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return String(hash, radix: 16)
    }
}

fileprivate extension UIImage {
    var estimatedCost: Int {
        guard let cg = cgImage else { return 1 }
        return cg.bytesPerRow * cg.height
    }
}

/// Drop-in replacement for `AsyncImage` that renders cached images immediately.
struct CachedImage<Placeholder: View>: View {
    private let url: URL?
    private let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
        // Seed from the cache during init so a warm image is on screen for the
        // first frame — no placeholder, no fade, no flicker.
        _image = State(initialValue: url.flatMap { ImageLoader.shared.cached($0) })
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard image == nil, let url else { return }
            let loaded = await ImageLoader.shared.image(for: url)
            // Only adopt it if this view still wants this URL (cells get reused).
            if !Task.isCancelled { image = loaded }
        }
    }
}
