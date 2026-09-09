import Foundation

enum AppConfig {
    /// Where the Worker lives. Precedence:
    ///   1. `TUNETUBE_API` environment variable (scheme / CI override)
    ///   2. `TuneTubeAPIBaseURL` from Info.plist, set by the `API_BASE_URL`
    ///      build setting in project.yml
    ///   3. localhost, which only works in the Simulator
    ///
    /// Note `localhost` is wrong on a physical device — the phone resolves it to
    /// itself, which surfaces as NSURLErrorCannotConnectToHost (-1004) with
    /// "Connection refused" on 127.0.0.1. Use the Mac's `.local` name instead,
    /// and start the Worker with `--ip 0.0.0.0` so it accepts LAN connections.
    static let apiBaseURL: URL = {
        if let override = ProcessInfo.processInfo.environment["TUNETUBE_API"],
           let url = URL(string: override), url.host != nil {
            return url
        }
        if let configured = Bundle.main.object(forInfoDictionaryKey: "TuneTubeAPIBaseURL") as? String,
           let url = URL(string: configured), url.host != nil {
            return url
        }
        return URL(string: "http://localhost:8799")!
    }()

    static let region = "US"
    static let language = "en"

    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "TuneTube \(v)"
    }
}
