import AppKit

/// Builds the menu bar. App-specific items target the `AppDelegate`; standard editing and
/// window items go up the responder chain so WKWebView handles copy, paste and undo.
@MainActor
enum MainMenuBuilder {
    static func build(for app: AppDelegate, accountMenu: NSMenu) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenu(appMenu(app)))
        mainMenu.addItem(submenu(fileMenu(app)))
        mainMenu.addItem(submenu(editMenu()))
        mainMenu.addItem(submenu(viewMenu(app)))
        accountMenu.delegate = app
        mainMenu.addItem(submenu(accountMenu))
        let windowMenu = windowMenu(app)
        mainMenu.addItem(submenu(windowMenu))
        let helpMenu = helpMenu(app)
        mainMenu.addItem(submenu(helpMenu))
        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = helpMenu
        return mainMenu
    }

    private static func appMenu(_ app: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "DeepSeek")
        menu.addItem(item(L("About DeepSeek"), #selector(AppDelegate.showAbout(_:)), target: app))
        menu.addItem(.separator())
        menu.addItem(item(L("Settings…"), #selector(AppDelegate.showSettings(_:)), ",", target: app))
        menu.addItem(.separator())
        let services = NSMenu(title: L("Services"))
        NSApp.servicesMenu = services
        let servicesItem = NSMenuItem(title: L("Services"), action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        menu.addItem(servicesItem)
        menu.addItem(.separator())
        menu.addItem(item(L("Hide DeepSeek"), #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item(L("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item(L("Show All"), #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item(L("Quit DeepSeek"), #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu(_ app: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: L("File"))
        menu.addItem(item(L("New Chat"), #selector(AppDelegate.newChat(_:)), "n", target: app))
        menu.addItem(.separator())
        menu.addItem(item(L("Close Window"), #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: L("Edit"))
        menu.addItem(item(L("Undo"), Selector(("undo:")), "z"))
        menu.addItem(item(L("Redo"), Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item(L("Cut"), #selector(NSText.cut(_:)), "x"))
        menu.addItem(item(L("Copy"), #selector(NSText.copy(_:)), "c"))
        menu.addItem(item(L("Paste"), #selector(NSText.paste(_:)), "v"))
        menu.addItem(item(L("Paste and Match Style"), #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]))
        menu.addItem(item(L("Delete"), #selector(NSText.delete(_:))))
        menu.addItem(item(L("Select All"), #selector(NSText.selectAll(_:)), "a"))
        return menu
    }

    private static func viewMenu(_ app: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: L("View"))
        menu.addItem(item(L("Reload Page"), #selector(AppDelegate.reloadPage(_:)), "r", target: app))
        menu.addItem(item(L("Reload Ignoring Cache"), #selector(AppDelegate.reloadIgnoringCache(_:)), "r", [.command, .shift], target: app))
        menu.addItem(.separator())
        menu.addItem(item(L("Actual Size"), #selector(AppDelegate.actualSize(_:)), "0", target: app))
        menu.addItem(item(L("Zoom In"), #selector(AppDelegate.zoomIn(_:)), "+", target: app))
        // ⌘= is what people actually press for "zoom in" on most layouts.
        let zoomInAlias = item(L("Zoom In"), #selector(AppDelegate.zoomIn(_:)), "=", target: app)
        zoomInAlias.isHidden = true
        zoomInAlias.allowsKeyEquivalentWhenHidden = true
        menu.addItem(zoomInAlias)
        menu.addItem(item(L("Zoom Out"), #selector(AppDelegate.zoomOut(_:)), "-", target: app))
        menu.addItem(.separator())
        menu.addItem(item(L("Back"), #selector(AppDelegate.goBack(_:)), "[", target: app))
        menu.addItem(item(L("Forward"), #selector(AppDelegate.goForward(_:)), "]", target: app))
        menu.addItem(.separator())
        menu.addItem(item(L("Enter Full Screen"), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func windowMenu(_ app: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: L("Window"))
        menu.addItem(item(L("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item(L("Zoom"), #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item(L("Float on Top"), #selector(AppDelegate.toggleFloatOnTop(_:)), "t", [.command, .option], target: app))
        menu.addItem(item(L("Main Window"), #selector(AppDelegate.showMainWindow(_:)), "1", target: app))
        menu.addItem(.separator())
        menu.addItem(item(L("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    private static func helpMenu(_ app: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: L("Help"))
        menu.addItem(item(L("Open Current Page in Browser"), #selector(AppDelegate.openCurrentPageInBrowser(_:)), target: app))
        menu.addItem(item(L("DeepSeek Website"), #selector(AppDelegate.openDeepSeekWebsite(_:)), target: app))
        return menu
    }

    // MARK: Helpers

    static func item(
        _ title: String, _ action: Selector?, _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
        item.target = target
        return item
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
