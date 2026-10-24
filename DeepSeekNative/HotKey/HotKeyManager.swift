import AppKit
import Carbon.HIToolbox
import Observation
import os

/// 'DSNK' — tags our hot key so the handler ignores anyone else's.
private let hotKeySignature: OSType = 0x4453_4E4B
private let log = Logger(subsystem: "com.sink7.DeepSeekNative", category: "HotKey")

/// Registers one system-wide shortcut through the Carbon hot key API. Unlike a global
/// `NSEvent` monitor, this needs no Accessibility permission and the key press is consumed.
@MainActor
@Observable
final class HotKeyManager {
    static let shared = HotKeyManager()

    /// Shown in Settings when registration fails, e.g. because another app owns the combo.
    private(set) var registrationError: String?

    /// While true the shortcut is unregistered, so the recorder can capture any combo,
    /// including the one currently in use.
    var isSuspended = false {
        didSet { if isSuspended != oldValue { refresh() } }
    }

    @ObservationIgnored private var combo: KeyCombo?
    @ObservationIgnored private var action: (@MainActor () -> Void)?
    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var handlerRef: EventHandlerRef?

    func register(_ combo: KeyCombo?, action: @escaping @MainActor () -> Void) {
        self.combo = combo
        self.action = action
        refresh()
    }

    fileprivate func handlePress() {
        log.info("Hot key pressed")
        action?()
    }

    private func refresh() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        registrationError = nil
        guard let combo, !isSuspended else { return }

        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: hotKeySignature, id: 1)
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id, GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRef = ref
            log.info("Registered hot key \(combo.displayString, privacy: .public)")
        } else if status == OSStatus(eventHotKeyExistsErr) {
            registrationError = "“\(combo.displayString)” 已被系统或其他应用占用，请换一个组合。"
        } else {
            registrationError = "无法注册全局快捷键（错误码 \(status)）。"
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
    MainActor.assumeIsolated {
        HotKeyManager.shared.handlePress()
    }
    return noErr
}
