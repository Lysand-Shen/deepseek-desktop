import AppKit
import Carbon.HIToolbox
import Observation
import os

/// 'DSNK' — tags our hot keys so the handler ignores anyone else's.
private let hotKeySignature: OSType = 0x4453_4E4B
private let log = Logger(subsystem: "com.sink7.DeepSeekNative", category: "HotKey")

/// Registers system-wide shortcuts through the Carbon hot key API. Unlike a global
/// `NSEvent` monitor, this needs no Accessibility permission and the key press is consumed.
@MainActor
@Observable
final class HotKeyManager {
    static let shared = HotKeyManager()

    enum Shortcut: UInt32, CaseIterable {
        case quickChat = 1
        case mainWindow = 2
    }

    enum RegistrationError: Equatable {
        /// Another app, macOS, or our other shortcut already registered the combo.
        case taken(KeyCombo)
        case failed(OSStatus)

        @MainActor var message: String {
            switch self {
            case .taken(let combo): L("“\(combo.displayString)” is already used by macOS or another app. Choose a different shortcut.")
            case .failed(let status): L("Couldn't register the global shortcut (error \(String(status))).")
            }
        }
    }

    /// Shown in Settings when registration fails, e.g. because another app owns the combo.
    private(set) var errors: [Shortcut: RegistrationError] = [:]

    /// While true the shortcuts are unregistered, so the recorder can capture any combo,
    /// including one currently in use.
    var isSuspended = false {
        didSet { if isSuspended != oldValue { refresh() } }
    }

    private struct Binding {
        var combo: KeyCombo?
        var action: @MainActor () -> Void
        var ref: EventHotKeyRef?
    }

    @ObservationIgnored private var bindings: [Shortcut: Binding] = [:]
    @ObservationIgnored private var handlerRef: EventHandlerRef?

    func register(_ shortcut: Shortcut, combo: KeyCombo?, action: @escaping @MainActor () -> Void) {
        unregister(shortcut)
        bindings[shortcut] = Binding(combo: combo, action: action)
        errors[shortcut] = nil
        if !isSuspended { activate(shortcut) }
    }

    fileprivate func handlePress(_ id: UInt32) {
        guard let shortcut = Shortcut(rawValue: id) else { return }
        log.info("Hot key pressed: \(String(describing: shortcut), privacy: .public)")
        bindings[shortcut]?.action()
    }

    private func refresh() {
        for shortcut in Shortcut.allCases { unregister(shortcut) }
        errors = [:]
        guard !isSuspended else { return }
        for shortcut in Shortcut.allCases { activate(shortcut) }
    }

    private func unregister(_ shortcut: Shortcut) {
        guard let ref = bindings[shortcut]?.ref else { return }
        UnregisterEventHotKey(ref)
        bindings[shortcut]?.ref = nil
    }

    private func activate(_ shortcut: Shortcut) {
        guard let combo = bindings[shortcut]?.combo else { return }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: hotKeySignature, id: shortcut.rawValue)
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id, GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref {
            bindings[shortcut]?.ref = ref
            log.info("Registered hot key \(String(describing: shortcut), privacy: .public): \(combo.displayString, privacy: .public)")
        } else if status == OSStatus(eventHotKeyExistsErr) {
            errors[shortcut] = .taken(combo)
        } else {
            errors[shortcut] = .failed(status)
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyEventHandler, 1, &eventType, nil, &handlerRef)
    }
}

/// Carbon delivers hot key events on the main thread's event loop.
private func hotKeyEventHandler(_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &id
    )
    guard status == noErr, id.signature == hotKeySignature else { return OSStatus(eventNotHandledErr) }
    let hotKeyID = id.id
    MainActor.assumeIsolated {
        HotKeyManager.shared.handlePress(hotKeyID)
    }
    return noErr
}
