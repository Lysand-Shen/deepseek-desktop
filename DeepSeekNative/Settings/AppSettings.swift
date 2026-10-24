import AppKit
import Observation

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
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

    var title: String {
        switch self {
        case .remember: "保持上次位置"
        case .mouseScreenCenter: "鼠标所在屏幕居中"
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
        static let hotKey = "hotKey"
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

    /// `nil` means the global shortcut is turned off.
    var hotKey: KeyCombo? {
        didSet {
            if let hotKey, let data = try? JSONEncoder().encode(hotKey) {
                defaults.set(data, forKey: Key.hotKey)
            } else {
                defaults.set(Self.disabledHotKeyMarker, forKey: Key.hotKey)
            }
        }
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

        switch defaults.object(forKey: Key.hotKey) {
        case let data as Data:
            hotKey = (try? JSONDecoder().decode(KeyCombo.self, from: data)) ?? .defaultSummon
        case let marker as String where marker == Self.disabledHotKeyMarker:
            hotKey = nil
        default:
            hotKey = .defaultSummon
        }
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
