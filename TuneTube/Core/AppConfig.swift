import Foundation

enum AppConfig {
    static var youtubeAPIKey: String? {
        let configured = ProcessInfo.processInfo.environment["YOUTUBE_DATA_API_KEY"]
            ?? Bundle.main.object(forInfoDictionaryKey: "YouTubeDataAPIKey") as? String
        guard let key = configured?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return key
    }

    static var region: String { LocalePreference.region }
    static var language: String { LocalePreference.language }

    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "TuneTube \(v)"
    }
}
