import AppKit
import Observation

/// Interface languages the app ships, plus "whatever macOS prefers".
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    /// Each language is named in itself, so it can be found from any interface language.
    @MainActor var title: String {
        switch self {
        case .system: L("System")
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }
}

/// Resolves the interface language and switches it while the app runs.
///
/// The choice is stored the way macOS stores a per-app language (the app's own
/// `AppleLanguages`), so it matches System Settings › Language & Region › Applications.
/// Our own strings switch immediately; text that AppKit and WebKit provide (the Services
/// menu, web context menus, the page's `navigator.language`) follows on the next launch.
@MainActor
@Observable
final class Localizer {
    static let shared = Localizer()

    private static let appleLanguagesKey = "AppleLanguages"
    private static let supported = AppLanguage.allCases.filter { $0 != .system }.map(\.rawValue)

    var preference: AppLanguage {
        didSet {
            guard preference != oldValue else { return }
            if preference == .system {
                defaults.removeObject(forKey: Self.appleLanguagesKey)
            } else {
                defaults.set([preference.rawValue], forKey: Self.appleLanguagesKey)
            }
            apply(Self.resolve(preference))
        }
    }

    /// The localization in use, `en` or `zh-Hans`.
    private(set) var language: String
    private(set) var locale: Locale
    /// Where `L` looks strings up. Reading these is what makes views and menus refresh on a switch.
    private(set) var bundle: Bundle
    private(set) var table: String?

    /// What AppKit and WebKit settled on at launch; they keep it until the app restarts.
    @ObservationIgnored let launchLanguage: String
    @ObservationIgnored private let defaults: UserDefaults

    var needsRelaunch: Bool { language != launchLanguage }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let ownLanguages = Bundle.main.bundleIdentifier
            .flatMap { defaults.persistentDomain(forName: $0)?[Self.appleLanguagesKey] as? [String] }
        preference = ownLanguages?.first.flatMap(Self.supportedLanguage(for:)) ?? .system
        launchLanguage = Bundle.main.preferredLocalizations.first { Self.supported.contains($0) } ?? AppLanguage.english.rawValue
        language = launchLanguage
        locale = Locale(identifier: launchLanguage)
        (bundle, table) = Self.lookup(for: launchLanguage)
    }

    private func apply(_ language: String) {
        guard language != self.language else { return }
        self.language = language
        locale = Locale(identifier: language)
        (bundle, table) = Self.lookup(for: language)
    }

    private static func supportedLanguage(for identifier: String) -> AppLanguage? {
        if identifier.hasPrefix("zh") { return .simplifiedChinese }
        if identifier.hasPrefix("en") { return .english }
        return nil
    }

    private static func resolve(_ preference: AppLanguage) -> String {
        guard preference == .system else { return preference.rawValue }
        // Our own `AppleLanguages` has just been removed, but `Locale.preferredLanguages`
        // may still be cached, so read the system-wide list directly.
        let systemLanguages = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[appleLanguagesKey]
            as? [String] ?? Locale.preferredLanguages
        for identifier in systemLanguages {
            if let language = supportedLanguage(for: identifier) { return language.rawValue }
        }
        return AppLanguage.english.rawValue
    }

    /// Looks inside the `.lproj` folder itself, so lookups ignore the language the process launched with.
    private static func lookup(for language: String) -> (Bundle, String?) {
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) {
            return (bundle, nil)
        }
        // English is the source language, so the build emits no table for it. Asking for a
        // table that doesn't exist makes the lookup return the key, which is the English text.
        return (.main, "SourceLanguage")
    }
}

/// A UI string in the current interface language. Reading it inside a SwiftUI body or an
/// `observeChanges` block re-runs that code when the language changes.
@MainActor
func L(_ key: String.LocalizationValue) -> String {
    let localizer = Localizer.shared
    return String(localized: key, table: localizer.table, bundle: localizer.bundle, locale: localizer.locale)
}

extension NSApplication {
    /// Quits and opens the app again once this process has exited.
    func relaunch() {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        // The bundle path arrives as $0, so it needs no quoting.
        process.arguments = [
            "-c",
            "while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"$0\"",
            Bundle.main.bundlePath,
        ]
        try? process.run()
        terminate(nil)
    }
}
