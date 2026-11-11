import Foundation

enum AppConfig {
    /// Content region and language, sent as `gl`/`hl` on every request. These
    /// are user preferences now, so read them per request rather than caching
    /// the value — `AppSettings` can change them mid-session.
    static var region: String { LocalePreference.region }
    static var language: String { LocalePreference.language }

    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "TuneTube \(v)"
    }
}
