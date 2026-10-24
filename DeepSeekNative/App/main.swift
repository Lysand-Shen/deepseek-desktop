import AppKit

// AppKit lifecycle: the main window, menus and status item are managed by hand so the window
// can be hidden, summoned and re-centred freely, which SwiftUI scenes don't allow.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
