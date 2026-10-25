import AppKit
import os

private let log = Logger(subsystem: "com.sink7.DeepSeekNative", category: "App")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private let settings = AppSettings.shared
    private let profiles = ProfileStore.shared

    private var model: WebViewModel!
    private var mainWindow: MainWindowController!
    private var quickChat: QuickChatController!
    private var settingsWindow: SettingsWindowController?
    private var statusItem: StatusItemController?

    // Rebuilt whenever the interface language changes; a menu can only have one supermenu.
    private var accountMenu = NSMenu()
    private var statusAccountMenu = NSMenu()
    private lazy var statusMenu = makeStatusMenu()

    // MARK: - Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        // We provide our own "Enter Full Screen" item in the View menu.
        UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
        // Builds the menu bar now, and again in the new language when it changes.
        observeChanges { [weak self] in
            guard let self else { return }
            self.accountMenu = NSMenu(title: L("Account"))
            NSApp.mainMenu = MainMenuBuilder.build(for: self, accountMenu: self.accountMenu)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = WebViewModel(settings: settings, profiles: profiles)
        mainWindow = MainWindowController(model: model, settings: settings)
        quickChat = QuickChatController(model: model, profiles: profiles, mainWindow: mainWindow)
        bindSettings()

        if !(settings.startHidden && settings.keepRunningInBackground) {
            mainWindow.present()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock icon click while the chat window is closed or hidden.
        if mainWindow.window?.isVisible != true { mainWindow.present() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !settings.keepRunningInBackground
    }

    func applicationDidResignActive(_ notification: Notification) {
        guard settings.hideOnDeactivate, mainWindow.window?.isVisible == true, !mainWindow.isFullScreen else { return }
        NSApp.hide(nil)
    }

    // MARK: - Settings side effects

    private func bindSettings() {
        observeChanges { [weak self] in
            guard let self else { return }
            NSApp.appearance = self.settings.appearance.nsAppearance
        }
        observeChanges { [weak self] in self?.applyActivationPolicy() }
        observeChanges { [weak self] in self?.applyStatusItem() }
        // Registering updates `HotKeyManager.errors`, so only the combos are tracked.
        observeChanges(of: { [settings] in settings.quickChatHotKey }) { [weak self] combo in
            HotKeyManager.shared.register(.quickChat, combo: combo) { self?.quickChat.toggle() }
        }
        observeChanges(of: { [settings] in settings.mainWindowHotKey }) { [weak self] combo in
            HotKeyManager.shared.register(.mainWindow, combo: combo) { self?.toggleMainWindow() }
        }
    }

    private func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = settings.showDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Switching policy can push our windows behind other apps; bring them back.
        Task { @MainActor [weak self] in
            NSApp.activate()
            self?.settingsWindow?.window?.makeKeyAndOrderFront(nil)
        }
    }

    private func applyStatusItem() {
        if settings.showMenuBarIcon {
            guard statusItem == nil else { return }
            statusItem = StatusItemController(menu: statusMenu) { [weak self] in self?.toggleMainWindow() }
        } else {
            statusItem?.remove()
            statusItem = nil
        }
    }

    // MARK: - Summoning

    /// Bound to the main window shortcut and the menu bar icon.
    func toggleMainWindow() {
        if let window = mainWindow.window {
            log.info("""
                Toggle: active=\(NSApp.isActive) visible=\(window.isVisible) key=\(window.isKeyWindow) \
                onActiveSpace=\(window.isOnActiveSpace) keyWindow=\(NSApp.keyWindow?.title ?? "nil", privacy: .public)
                """)
        }
        if mainWindow.isFrontmost {
            // Hiding the app (rather than ordering out) hands focus back to the previous app.
            NSApp.hide(nil)
        } else {
            mainWindow.present(centerOnMouseScreen: settings.summonPosition == .mouseScreenCenter)
            if settings.focusInputOnSummon { model.focusInput() }
        }
    }

    // MARK: - Menu actions

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate()
        let credits = NSAttributedString(
            string: L("A native macOS client for DeepSeek's official web app.\nUses the system's WebKit. No API key needed, and no data collected."),
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc func showSettings(_ sender: Any?) {
        openSettings(pane: nil)
    }

    @objc func manageAccounts(_ sender: Any?) {
        openSettings(pane: .accounts)
    }

    private func openSettings(pane: SettingsWindowController.Pane?) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(model: model, settings: settings, profiles: profiles)
        }
        settingsWindow?.show(pane: pane)
    }

    @objc func newChat(_ sender: Any?) {
        mainWindow.present()
        model.startNewChat()
    }

    @objc func showMainWindow(_ sender: Any?) {
        mainWindow.present()
    }

    @objc func toggleFromStatusMenu(_ sender: Any?) {
        toggleMainWindow()
    }

    @objc func showQuickChat(_ sender: Any?) {
        quickChat.show()
    }

    @objc func reloadPage(_ sender: Any?) { model.reload() }
    @objc func reloadIgnoringCache(_ sender: Any?) { model.reloadIgnoringCache() }
    @objc func actualSize(_ sender: Any?) { model.resetZoom() }
    @objc func zoomIn(_ sender: Any?) { model.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { model.zoomOut() }
    @objc func goBack(_ sender: Any?) { model.goBack() }
    @objc func goForward(_ sender: Any?) { model.goForward() }
    @objc func toggleFloatOnTop(_ sender: Any?) { settings.floatOnTop.toggle() }
    @objc func openCurrentPageInBrowser(_ sender: Any?) { model.openCurrentPageInBrowser() }

    @objc func openDeepSeekWebsite(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: "https://www.deepseek.com/")!)
    }

    @objc func switchAccount(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        model.switchProfile(to: id)
        mainWindow.present()
    }

    @objc func addAccount(_ sender: Any?) {
        model.addProfileAndSwitch()
        mainWindow.present()
    }

    @objc func clearCache(_ sender: Any?) {
        Task { await model.clearCache() }
    }

    @objc func signOutCurrentAccount(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = L("Sign out of “\(profiles.current.displayName)”?")
        alert.informativeText = L("This deletes the account's cookies, local storage and cache on this Mac. Your chats stay in the cloud and come back when you sign in again.")
        alert.addButton(withTitle: L("Sign Out and Clear"))
        alert.addButton(withTitle: L("Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        let confirm: @MainActor (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            Task { await self.model.signOutAndClearData() }
        }
        if let window = mainWindow.window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: confirm)
        } else {
            confirm(alert.runModal())
        }
    }

    // MARK: - Menu state

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(goBack(_:)):
            return model?.canGoBack ?? false
        case #selector(goForward(_:)):
            return model?.canGoForward ?? false
        case #selector(zoomIn(_:)):
            return settings.pageZoom < AppSettings.zoomRange.upperBound
        case #selector(zoomOut(_:)):
            return settings.pageZoom > AppSettings.zoomRange.lowerBound
        case #selector(toggleFloatOnTop(_:)):
            menuItem.state = settings.floatOnTop ? .on : .off
            return true
        case #selector(switchAccount(_:)):
            menuItem.state = (menuItem.representedObject as? UUID) == profiles.currentID ? .on : .off
            return true
        default:
            return true
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === accountMenu {
            populateAccountMenu(menu, includeDataActions: true)
        } else if menu === statusAccountMenu {
            populateAccountMenu(menu, includeDataActions: false)
        } else if menu === statusMenu {
            populateStatusMenu(menu)
        }
    }

    private func populateAccountMenu(_ menu: NSMenu, includeDataActions: Bool) {
        menu.removeAllItems()
        for profile in profiles.profiles {
            let item = MainMenuBuilder.item(profile.displayName, #selector(switchAccount(_:)), target: self)
            item.representedObject = profile.id
            item.state = profile.id == profiles.currentID ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(MainMenuBuilder.item(L("Add Account"), #selector(addAccount(_:)), target: self))
        menu.addItem(MainMenuBuilder.item(L("Manage Accounts…"), #selector(manageAccounts(_:)), target: self))
        guard includeDataActions else { return }
        menu.addItem(.separator())
        menu.addItem(MainMenuBuilder.item(L("Clear Cache"), #selector(clearCache(_:)), target: self))
        menu.addItem(MainMenuBuilder.item(L("Sign Out of Current Account…"), #selector(signOutCurrentAccount(_:)), target: self))
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        populateStatusMenu(menu)
        return menu
    }

    /// Filled in each time the menu opens, so it's always in the current language.
    private func populateStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let quickTitle = settings.quickChatHotKey.map { L("Quick Chat (\($0.displayString))") } ?? L("Quick Chat")
        menu.addItem(MainMenuBuilder.item(quickTitle, #selector(showQuickChat(_:)), target: self))
        let toggleTitle = settings.mainWindowHotKey.map { L("Show or Hide DeepSeek (\($0.displayString))") } ?? L("Show or Hide DeepSeek")
        menu.addItem(MainMenuBuilder.item(toggleTitle, #selector(toggleFromStatusMenu(_:)), target: self))
        menu.addItem(MainMenuBuilder.item(L("New Chat"), #selector(newChat(_:)), target: self))
        menu.addItem(.separator())
        menu.addItem(MainMenuBuilder.item(L("Float on Top"), #selector(toggleFloatOnTop(_:)), target: self))
        statusAccountMenu = NSMenu(title: L("Account"))
        statusAccountMenu.delegate = self
        let accounts = NSMenuItem(title: statusAccountMenu.title, action: nil, keyEquivalent: "")
        accounts.submenu = statusAccountMenu
        menu.addItem(accounts)
        menu.addItem(.separator())
        menu.addItem(MainMenuBuilder.item(L("Settings…"), #selector(showSettings(_:)), target: self))
        menu.addItem(.separator())
        menu.addItem(MainMenuBuilder.item(L("Quit DeepSeek"), #selector(NSApplication.terminate(_:)), target: NSApp))
    }
}
