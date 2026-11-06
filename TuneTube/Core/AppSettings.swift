import Foundation
import Observation

/// A YouTube Music content region. `code` is the ISO 3166-1 alpha-2 value the
/// API client sends as `gl` on every request, and which the Worker folds into
/// its cache key.
struct ContentRegion: Identifiable, Hashable, Sendable {
    let code: String
    let name: String

    var id: String { code }

    /// Flag emoji built from the two regional-indicator symbols for the code.
    var flag: String {
        var scalars = String.UnicodeScalarView()
        for scalar in code.uppercased().unicodeScalars {
            guard let indicator = UnicodeScalar(127_397 + scalar.value) else { return "🏳️" }
            scalars.append(indicator)
        }
        return String(scalars)
    }
}

/// Interface + content language, sent as `hl`.
struct ContentLanguage: Identifiable, Hashable, Sendable {
    let code: String
    /// English name, shown as the row title.
    let name: String
    /// The language's own name, shown underneath.
    let nativeName: String

    var id: String { code }
}

extension ContentRegion {
    /// The regions YouTube Music serves a distinct home feed for. Ordered by
    /// name so the picker reads alphabetically.
    static let all: [ContentRegion] = [
        .init(code: "AR", name: "Argentina"),
        .init(code: "AU", name: "Australia"),
        .init(code: "AT", name: "Austria"),
        .init(code: "BD", name: "Bangladesh"),
        .init(code: "BE", name: "Belgium"),
        .init(code: "BR", name: "Brazil"),
        .init(code: "CA", name: "Canada"),
        .init(code: "CL", name: "Chile"),
        .init(code: "CO", name: "Colombia"),
        .init(code: "CZ", name: "Czechia"),
        .init(code: "DK", name: "Denmark"),
        .init(code: "EG", name: "Egypt"),
        .init(code: "FI", name: "Finland"),
        .init(code: "FR", name: "France"),
        .init(code: "DE", name: "Germany"),
        .init(code: "GH", name: "Ghana"),
        .init(code: "HK", name: "Hong Kong"),
        .init(code: "HU", name: "Hungary"),
        .init(code: "IN", name: "India"),
        .init(code: "ID", name: "Indonesia"),
        .init(code: "IE", name: "Ireland"),
        .init(code: "IL", name: "Israel"),
        .init(code: "IT", name: "Italy"),
        .init(code: "JP", name: "Japan"),
        .init(code: "KE", name: "Kenya"),
        .init(code: "MY", name: "Malaysia"),
        .init(code: "MX", name: "Mexico"),
        .init(code: "NL", name: "Netherlands"),
        .init(code: "NZ", name: "New Zealand"),
        .init(code: "NG", name: "Nigeria"),
        .init(code: "NO", name: "Norway"),
        .init(code: "PK", name: "Pakistan"),
        .init(code: "PE", name: "Peru"),
        .init(code: "PH", name: "Philippines"),
        .init(code: "PL", name: "Poland"),
        .init(code: "PT", name: "Portugal"),
        .init(code: "RO", name: "Romania"),
        .init(code: "RU", name: "Russia"),
        .init(code: "SA", name: "Saudi Arabia"),
        .init(code: "SG", name: "Singapore"),
        .init(code: "ZA", name: "South Africa"),
        .init(code: "KR", name: "South Korea"),
        .init(code: "ES", name: "Spain"),
        .init(code: "LK", name: "Sri Lanka"),
        .init(code: "SE", name: "Sweden"),
        .init(code: "CH", name: "Switzerland"),
        .init(code: "TW", name: "Taiwan"),
        .init(code: "TH", name: "Thailand"),
        .init(code: "TR", name: "Türkiye"),
        .init(code: "AE", name: "United Arab Emirates"),
        .init(code: "GB", name: "United Kingdom"),
        .init(code: "US", name: "United States"),
        .init(code: "VN", name: "Vietnam"),
    ]

    static let fallback = ContentRegion(code: "US", name: "United States")

    static func named(_ code: String) -> ContentRegion {
        all.first { $0.code == code } ?? fallback
    }
}

extension ContentLanguage {
    static let all: [ContentLanguage] = [
        .init(code: "ar",    name: "Arabic",     nativeName: "العربية"),
        .init(code: "bn",    name: "Bengali",    nativeName: "বাংলা"),
        .init(code: "zh-CN", name: "Chinese (Simplified)",  nativeName: "简体中文"),
        .init(code: "zh-TW", name: "Chinese (Traditional)", nativeName: "繁體中文"),
        .init(code: "nl",    name: "Dutch",      nativeName: "Nederlands"),
        .init(code: "en",    name: "English",    nativeName: "English"),
        .init(code: "fil",   name: "Filipino",   nativeName: "Filipino"),
        .init(code: "fr",    name: "French",     nativeName: "Français"),
        .init(code: "de",    name: "German",     nativeName: "Deutsch"),
        .init(code: "hi",    name: "Hindi",      nativeName: "हिन्दी"),
        .init(code: "id",    name: "Indonesian", nativeName: "Bahasa Indonesia"),
        .init(code: "it",    name: "Italian",    nativeName: "Italiano"),
        .init(code: "ja",    name: "Japanese",   nativeName: "日本語"),
        .init(code: "ko",    name: "Korean",     nativeName: "한국어"),
        .init(code: "ms",    name: "Malay",      nativeName: "Bahasa Melayu"),
        .init(code: "fa",    name: "Persian",    nativeName: "فارسی"),
        .init(code: "pl",    name: "Polish",     nativeName: "Polski"),
        .init(code: "pt",    name: "Portuguese", nativeName: "Português"),
        .init(code: "ru",    name: "Russian",    nativeName: "Русский"),
        .init(code: "es",    name: "Spanish",    nativeName: "Español"),
        .init(code: "sv",    name: "Swedish",    nativeName: "Svenska"),
        .init(code: "ta",    name: "Tamil",      nativeName: "தமிழ்"),
        .init(code: "te",    name: "Telugu",     nativeName: "తెలుగు"),
        .init(code: "th",    name: "Thai",       nativeName: "ไทย"),
        .init(code: "tr",    name: "Turkish",    nativeName: "Türkçe"),
        .init(code: "uk",    name: "Ukrainian",  nativeName: "Українська"),
        .init(code: "ur",    name: "Urdu",       nativeName: "اردو"),
        .init(code: "vi",    name: "Vietnamese", nativeName: "Tiếng Việt"),
    ]

    static let fallback = ContentLanguage(code: "en", name: "English", nativeName: "English")

    static func named(_ code: String) -> ContentLanguage {
        all.first { $0.code == code } ?? fallback
    }
}

/// Raw persisted locale preference.
///
/// Deliberately not actor-isolated: `APIClient` is an actor and reads these on
/// every request to build `gl`/`hl`. `UserDefaults` is thread-safe, so this is
/// the one piece that both the main actor and the API actor touch directly.
enum LocalePreference {
    private static let regionKey = "settings.contentRegion"
    private static let languageKey = "settings.contentLanguage"

    static var region: String {
        get { UserDefaults.standard.string(forKey: regionKey) ?? deviceRegion }
        set { UserDefaults.standard.set(newValue, forKey: regionKey) }
    }

    static var language: String {
        get { UserDefaults.standard.string(forKey: languageKey) ?? deviceLanguage }
        set { UserDefaults.standard.set(newValue, forKey: languageKey) }
    }

    /// First launch follows the device, but only to a region we actually list —
    /// an unlisted one would send a `gl` the home manifest has no shelves for.
    private static var deviceRegion: String {
        let code = Locale.current.region?.identifier ?? ContentRegion.fallback.code
        return ContentRegion.all.contains { $0.code == code } ? code : ContentRegion.fallback.code
    }

    private static var deviceLanguage: String {
        let code = Locale.current.language.languageCode?.identifier ?? ContentLanguage.fallback.code
        return ContentLanguage.all.contains { $0.code == code } ? code : ContentLanguage.fallback.code
    }
}

/// Observable wrapper over `LocalePreference` for the UI.
///
/// Changing either value drops every cached API response and bumps
/// `localeRevision`; screens watch that token and refetch. The token is what
/// makes the change visible immediately rather than on next cold launch.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private(set) var region: String
    private(set) var language: String

    /// Incremented after the caches are cleared, never before — a screen that
    /// reloads on this token is guaranteed not to read a stale response.
    private(set) var localeRevision = 0

    private init() {
        region = LocalePreference.region
        language = LocalePreference.language
    }

    var selectedRegion: ContentRegion { .named(region) }
    var selectedLanguage: ContentLanguage { .named(language) }

    func setRegion(_ code: String) {
        guard code != region, ContentRegion.all.contains(where: { $0.code == code }) else { return }
        region = code
        LocalePreference.region = code
        Task { await applyLocaleChange() }
    }

    func setLanguage(_ code: String) {
        guard code != language, ContentLanguage.all.contains(where: { $0.code == code }) else { return }
        language = code
        LocalePreference.language = code
        Task { await applyLocaleChange() }
    }

    private func applyLocaleChange() async {
        await APIClient.shared.clearCaches()
        localeRevision &+= 1
    }
}
