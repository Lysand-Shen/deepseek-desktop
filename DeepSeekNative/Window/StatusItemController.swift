import AppKit

/// Menu bar icon: click toggles the window, right-click (or ⌃/⌥-click) opens the menu.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let onToggle: () -> Void

    init(menu: NSMenu, onToggle: @escaping () -> Void) {
        self.menu = menu
        self.onToggle = onToggle
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        guard let button = statusItem.button else { return }
        let image = NSImage(named: "StatusBarIcon")
            ?? NSImage(systemSymbolName: "bubble.left.and.text.bubble.right", accessibilityDescription: "DeepSeek")
        image?.isTemplate = true
        button.image = image
        button.toolTip = "DeepSeek"
        button.target = self
        button.action = #selector(buttonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
            || event?.modifierFlags.contains(.option) == true
        guard wantsMenu else {
            onToggle()
            return
        }
        // Attaching the menu only for this click keeps left-click free for toggling.
        statusItem.menu = menu
        sender.performClick(nil)
        statusItem.menu = nil
    }
}
