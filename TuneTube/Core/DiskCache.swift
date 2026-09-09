import Foundation

/// Last-known-good response store. Deliberately dumb: newest write wins, no
/// expiry. The Worker owns freshness; this only exists so the app opens to
/// content instead of a spinner when the network is slow or absent.
actor DiskCache {
    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("TuneTubeResponses", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-_"))) ?? key
        return directory.appendingPathComponent(safe).appendingPathExtension("json")
    }

    func write(_ data: Data, for key: String) {
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    func read(for key: String) -> Data? {
        try? Data(contentsOf: fileURL(for: key))
    }
}
