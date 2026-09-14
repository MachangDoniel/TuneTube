import Foundation

enum AppConfig {
    /// Production Cloudflare Worker edge API.
    static let productionBaseURL = URL(string: "https://tunetube-api.tunetube-app.workers.dev")!

    #if DEBUG
    /// Where the local Mac Worker lives in debug mode.
    static let localBaseURL: URL = {
        if let override = ProcessInfo.processInfo.environment["TUNETUBE_API"],
           let url = URL(string: override), url.host != nil {
            return url
        }
        if let configured = Bundle.main.object(forInfoDictionaryKey: "TuneTubeAPIBaseURL") as? String,
           let url = URL(string: configured), url.host != nil {
            return url
        }
        return URL(string: "http://Doniels-MacBook-Air.local:8799")!
    }()

    /// The initial base URL for API requests. In debug builds, attempts local first.
    static let initialBaseURL: URL = localBaseURL
    #else
    /// In release builds, always use the production Cloudflare edge API.
    static let initialBaseURL: URL = {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "TuneTubeAPIBaseURL") as? String,
           let url = URL(string: configured), url.host != nil {
            return url
        }
        return productionBaseURL
    }()
    #endif

    /// Default base URL reference for error messages and backward compatibility.
    static var apiBaseURL: URL {
        initialBaseURL
    }

    static let region = "US"
    static let language = "en"

    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "TuneTube \(v)"
    }
}
