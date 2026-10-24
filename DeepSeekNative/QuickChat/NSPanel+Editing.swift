import AppKit

extension NSPanel {
    /// A panel that doesn't activate the app never gets the main menu's key equivalents,
    /// so it routes the standard editing shortcuts to the focused view itself.
    func performEditingKeyEquivalent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == .command || flags == [.command, .shift],
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return false }
        let action: Selector? = switch (key, flags.contains(.shift)) {
        case ("x", false): #selector(NSText.cut(_:))
        case ("c", false): #selector(NSText.copy(_:))
        case ("v", false): #selector(NSText.paste(_:))
        case ("a", false): #selector(NSText.selectAll(_:))
        case ("z", false): Selector(("undo:"))
        case ("z", true): Selector(("redo:"))
        case ("w", false): #selector(NSWindow.performClose(_:))
        default: nil
        }
        guard let action else { return false }
        return NSApp.sendAction(action, to: nil, from: self)
    }
}
