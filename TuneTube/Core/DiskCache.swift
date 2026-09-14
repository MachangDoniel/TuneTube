import Foundation

/// Last-known-good response store. Deliberately dumb: newest write wins, no
/// expiry. The Worker owns freshness; this only exists so the app opens to
/// content instead of a spinner when the network is slow or absent.
actor DiskCache {
    private let directory: URL
    private let memoryCache = NSCache<NSString, NSData>()

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("TuneTubeResponses", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memoryCache.countLimit = 120
    }

    private func fileURL(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-_"))) ?? key
        return directory.appendingPathComponent(safe).appendingPathExtension("json")
    }

    func write(_ data: Data, for key: String) {
        memoryCache.setObject(data as NSData, forKey: key as NSString)
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    /// Reads cached data. If `maxAge` is provided, only returns data if it was written
    /// within `maxAge` seconds. Returns nil if expired or not found.
    func read(for key: String, maxAge: TimeInterval? = nil) -> Data? {
        let url = fileURL(for: key)
        if let maxAge {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = values.contentModificationDate,
                  Date().timeIntervalSince(modDate) <= maxAge else {
                return nil
            }
        }
        if let inMemory = memoryCache.object(forKey: key as NSString) {
            return inMemory as Data
        }
        if let diskData = try? Data(contentsOf: url) {
            memoryCache.setObject(diskData as NSData, forKey: key as NSString)
            return diskData
        }
        return nil
    }

    /// Unconditionally reads cached data (even if stale), used for offline fallback.
    func readStale(for key: String) -> Data? {
        read(for: key, maxAge: nil)
    }
}
