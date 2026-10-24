import AppKit
import Observation

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .system: L("System")
        case .light: L("Light")
        case .dark: L("Dark")
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum SummonPosition: String, CaseIterable, Identifiable, Sendable {
    case remember, mouseScreenCenter

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .remember: L("Where It Was Last")
        case .mouseScreenCenter: L("Center of the Screen with the Pointer")
        }
    }
}

/// User preferences, persisted to `UserDefaults` as soon as they change.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    static let zoomRange: ClosedRange<Double> = 0.5...2.0

    private enum Key {
        /// Named before quick chat existed, when the one shortcut summoned the main window.
        static let quickChatHotKey = "hotKey"
        static let mainWindowHotKey = "mainWindowHotKey"
        static let summonPosition = "summonPosition"
        static let focusInputOnSummon = "focusInputOnSummon"
        static let hideOnDeactivate = "hideOnDeactivate"
        static let keepRunningInBackground = "keepRunningInBackground"
        static let showDockIcon = "showDockIcon"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let floatOnTop = "floatOnTop"
        static let appearance = "appearance"
        static let startHidden = "startHidden"
        static let pageZoom = "pageZoom"
        static let openExternalLinksInBrowser = "openExternalLinksInBrowser"
        static let askDownloadLocation = "askDownloadLocation"
    }

    /// Stored in place of an encoded combo when the user turns the shortcut off,
    /// so "never set" (use the default) and "disabled" stay distinguishable.
    private static let disabledHotKeyMarker = "disabled"

    @ObservationIgnored private let defaults: UserDefaults

    /// Opens the quick chat bar. `nil` means the shortcut is turned off.
    var quickChatHotKey: KeyCombo? {
        didSet { save(quickChatHotKey, forKey: Key.quickChatHotKey) }
    }

    /// Shows or hides the main window. Off unless the user records one.
    var mainWindowHotKey: KeyCombo? {
        didSet { save(mainWindowHotKey, forKey: Key.mainWindowHotKey) }
    }

    var summonPosition: SummonPosition {
        didSet { defaults.set(summonPosition.rawValue, forKey: Key.summonPosition) }
    }

    var focusInputOnSummon: Bool {
        didSet { defaults.set(focusInputOnSummon, forKey: Key.focusInputOnSummon) }
    }

    var hideOnDeactivate: Bool {
        didSet { defaults.set(hideOnDeactivate, forKey: Key.hideOnDeactivate) }
    }

    var keepRunningInBackground: Bool {
        didSet { defaults.set(keepRunningInBackground, forKey: Key.keepRunningInBackground) }
    }

    var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: Key.showDockIcon) }
    }

    var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
    }

    var floatOnTop: Bool {
        didSet { defaults.set(floatOnTop, forKey: Key.floatOnTop) }
    }

    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    var startHidden: Bool {
        didSet { defaults.set(startHidden, forKey: Key.startHidden) }
    }

    /// Always within `zoomRange`; use `setPageZoom(_:)` to change it.
    private(set) var pageZoom: Double {
        didSet { defaults.set(pageZoom, forKey: Key.pageZoom) }
    }

    func setPageZoom(_ zoom: Double) {
        // Round to whole percents so repeated ±10% steps don't drift.
        let rounded = (zoom * 100).rounded() / 100
        pageZoom = min(max(rounded, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    var openExternalLinksInBrowser: Bool {
        didSet { defaults.set(openExternalLinksInBrowser, forKey: Key.openExternalLinksInBrowser) }
    }

    var askDownloadLocation: Bool {
        didSet { defaults.set(askDownloadLocation, forKey: Key.askDownloadLocation) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.summonPosition: SummonPosition.remember.rawValue,
            Key.focusInputOnSummon: true,
            Key.hideOnDeactivate: false,
            Key.keepRunningInBackground: true,
            Key.showDockIcon: true,
            Key.showMenuBarIcon: true,
            Key.floatOnTop: false,
            Key.appearance: AppearanceMode.system.rawValue,
            Key.startHidden: false,
            Key.pageZoom: 1.0,
            Key.openExternalLinksInBrowser: true,
            Key.askDownloadLocation: false,
        ])

        quickChatHotKey = Self.loadHotKey(Key.quickChatHotKey, from: defaults, default: .defaultSummon)
        mainWindowHotKey = Self.loadHotKey(Key.mainWindowHotKey, from: defaults, default: nil)
        summonPosition = SummonPosition(rawValue: defaults.string(forKey: Key.summonPosition) ?? "") ?? .remember
        focusInputOnSummon = defaults.bool(forKey: Key.focusInputOnSummon)
        hideOnDeactivate = defaults.bool(forKey: Key.hideOnDeactivate)
        keepRunningInBackground = defaults.bool(forKey: Key.keepRunningInBackground)
        showDockIcon = defaults.bool(forKey: Key.showDockIcon)
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
        floatOnTop = defaults.bool(forKey: Key.floatOnTop)
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        startHidden = defaults.bool(forKey: Key.startHidden)
        pageZoom = min(max(defaults.double(forKey: Key.pageZoom), Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        openExternalLinksInBrowser = defaults.bool(forKey: Key.openExternalLinksInBrowser)
        askDownloadLocation = defaults.bool(forKey: Key.askDownloadLocation)

        // The Dock icon and the menu bar icon are the only ways back to a hidden window
        // besides the shortcut, so never let both be off.
        if !showDockIcon && !showMenuBarIcon { showMenuBarIcon = true }
    }

    private static func loadHotKey(_ key: String, from defaults: UserDefaults, default fallback: KeyCombo?) -> KeyCombo? {
        switch defaults.object(forKey: key) {
        case let data as Data:
            (try? JSONDecoder().decode(KeyCombo.self, from: data)) ?? fallback
        case let marker as String where marker == disabledHotKeyMarker:
            nil
        default:
            fallback
        }
    }

    private func save(_ combo: KeyCombo?, forKey key: String) {
        if let combo, let data = try? JSONEncoder().encode(combo) {
            defaults.set(data, forKey: key)
        } else {
            defaults.set(Self.disabledHotKeyMarker, forKey: key)
        }
    }
}

/// Runs `apply` now and again every time an observable property it read changes.
@MainActor
func observeChanges(_ apply: @escaping @MainActor @Sendable () -> Void) {
    withObservationTracking {
        apply()
    } onChange: {
        // `onChange` fires before the new value is stored; re-run on the next turn.
        Task { @MainActor in observeChanges(apply) }
    }
}

/// Calls `perform` with `value()` now and whenever an observable property `value` read
/// changes. Only `value` is tracked, so `perform` may freely change observable state.
@MainActor
func observeChanges<Value>(
    of value: @escaping @MainActor @Sendable () -> Value,
    perform: @escaping @MainActor @Sendable (Value) -> Void
) {
    let current = withObservationTracking {
        value()
    } onChange: {
        Task { @MainActor in observeChanges(of: value, perform: perform) }
    }
    perform(current)
}
