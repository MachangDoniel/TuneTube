import Foundation
import Observation

/// A YouTube Music content region. `code` is the ISO 3166-1 alpha-2 value the
/// API client sends as `gl` on every request, and which the Worker folds into
/// its cache key.
struct ContentRegion: Identifiable, Hashable, Sendable {
    let code: String

    var id: String { code }

    /// Taken from the device rather than hard-coded, so the picker reads in the
    /// user's own language and there are no 150 English names to maintain.
    var name: String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

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
    /// Every region the API can serve real regional charts for: the countries
    /// YouTube Music charts directly, plus those the Worker maps to a charted
    /// neighbour (Bangladesh and Pakistan to India, Ghana to Nigeria, and so
    /// on). A code outside this list would fall through to the global chart,
    /// which is what the list exists to avoid.
    ///
    /// Sorted by localized name, so the order follows whatever language the
    /// device is in.
    static let all: [ContentRegion] = codes
        .map(ContentRegion.init(code:))
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    static let fallback = ContentRegion(code: "US")

    static func named(_ code: String) -> ContentRegion {
        all.first { $0.code == code } ?? fallback
    }

    private static let codes: [String] = [
        "AE", "AF", "AL", "AM", "AR", "AT", "AU", "AZ", "BA", "BD", "BE", "BF",
        "BG", "BH", "BN", "BO", "BR", "BS", "BT", "BW", "BY", "BZ", "CA", "CH",
        "CI", "CL", "CM", "CO", "CR", "CU", "CY", "CZ", "DE", "DK", "DO", "DZ",
        "EC", "EE", "EG", "ES", "ET", "FI", "FJ", "FR", "GB", "GE", "GH", "GR",
        "GT", "GY", "HK", "HN", "HR", "HT", "HU", "ID", "IE", "IL", "IN", "IQ",
        "IS", "IT", "JM", "JO", "JP", "KE", "KG", "KH", "KR", "KW", "KZ", "LA",
        "LB", "LK", "LS", "LT", "LU", "LV", "LY", "MA", "MD", "ME", "MK", "ML",
        "MM", "MN", "MO", "MT", "MV", "MW", "MX", "MY", "MZ", "NA", "NC", "NG",
        "NI", "NL", "NO", "NP", "NZ", "OM", "PA", "PE", "PG", "PH", "PK", "PL",
        "PR", "PT", "PY", "QA", "RO", "RS", "RU", "RW", "SA", "SD", "SE", "SG",
        "SI", "SK", "SN", "SO", "SR", "SS", "SV", "SY", "SZ", "TH", "TJ", "TM",
        "TN", "TO", "TR", "TT", "TW", "TZ", "UA", "UG", "US", "UY", "UZ", "VE",
        "VN", "WS", "YE", "ZA", "ZM", "ZW",
    ]
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
