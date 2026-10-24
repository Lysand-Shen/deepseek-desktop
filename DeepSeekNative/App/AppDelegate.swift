import AppKit
import os

private let log = Logger(subsystem: "com.sink7.DeepSeekNative", category: "App")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private let settings = AppSettings.shared
    private let profiles = ProfileStore.shared

    private var model: WebViewModel!
    private var mainWindow: MainWindowController!
    private var settingsWindow: SettingsWindowController?
    private var statusItem: StatusItemController?

    private let accountMenu = NSMenu(title: "账户")
    private let statusAccountMenu = NSMenu(title: "账户")
    private lazy var statusMenu = makeStatusMenu()
    private weak var statusToggleItem: NSMenuItem?

    // MARK: - Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        // We provide our own "进入全屏幕" item in the View menu.
        UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
        NSApp.mainMenu = MainMenuBuilder.build(for: self, accountMenu: accountMenu)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = WebViewModel(settings: settings, profiles: profiles)
        mainWindow = MainWindowController(model: model, settings: settings)
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
        observeChanges { [weak self] in
            guard let self else { return }
            HotKeyManager.shared.register(self.settings.hotKey) { [weak self] in
                self?.toggleMainWindow()
            }
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

    /// Bound to the global shortcut and the menu bar icon.
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
            string: "基于 DeepSeek 官方网页版的原生 macOS 客户端。\n使用系统 WebKit，无需 API Key，不收集任何数据。",
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
        alert.messageText = "退出“\(profiles.current.name)”？"
        alert.informativeText = "将删除该账户在本机保存的 Cookie、本地存储与缓存。云端聊天记录不受影响，重新登录后即可看到。"
        alert.addButton(withTitle: "退出并清除")
        alert.addButton(withTitle: "取消")
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
            let shortcut = settings.hotKey.map { "（\($0.displayString)）" } ?? ""
            statusToggleItem?.title = "显示 / 隐藏 DeepSeek\(shortcut)"
        }
    }

    private func populateAccountMenu(_ menu: NSMenu, includeDataActions: Bool) {
        menu.removeAllItems()
        for profile in profiles.profiles {
            let item = MainMenuBuilder.item(profile.name, #selector(switchAccount(_:)), target: self)
            item.representedObject = profile.id
            item.state = profile.id == profiles.currentID ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(MainMenuBuilder.item("添加账户", #selector(addAccount(_:)), target: self))
        menu.addItem(MainMenuBuilder.item("管理账户…", #selector(manageAccounts(_:)), target: self))
        guard includeDataActions else { return }
        menu.addItem(.separator())
        menu.addItem(MainMenuBuilder.item("清除缓存", #selector(clearCache(_:)), target: self))
        menu.addItem(MainMenuBuilder.item("退出当前账户…", #selector(signOutCurrentAccount(_:)), target: self))
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let toggle = MainMenuBuilder.item("显示 / 隐藏 DeepSeek", #selector(toggleFromStatusMenu(_:)), target: self)
        statusToggleItem = toggle
        menu.addItem(toggle)
        menu.addItem(MainMenuBuilder.item("新对话", #selector(newChat(_:)), target: self))
        menu.addItem(.separator())
        menu.addItem(MainMenuBuilder.item("窗口置顶", #selector(toggleFloatOnTop(_:)), target: self))
        statusAccountMenu.delegate = self
        let accounts = NSMenuItem(title: "账户", action: nil, keyEquivalent: "")
        accounts.submenu = statusAccountMenu
        menu.addItem(accounts)
        menu.addItem(.separator())
        menu.addItem(MainMenuBuilder.item("设置…", #selector(showSettings(_:)), target: self))
        menu.addItem(.separator())
        menu.addItem(MainMenuBuilder.item("退出 DeepSeek", #selector(NSApplication.terminate(_:)), target: NSApp))
        return menu
    }
}
