import AppKit
import SwiftUI

/// Classic toolbar-tab preferences window hosting one SwiftUI form per pane.
@MainActor
final class SettingsWindowController: NSWindowController {
    enum Pane: Int, CaseIterable {
        case general, shortcut, accounts, web, about
    }

    private let tabController = SettingsTabViewController()

    init(model: WebViewModel, settings: AppSettings, profiles: ProfileStore) {
        tabController.tabStyle = .toolbar
        tabController.addPane(GeneralSettingsView(settings: settings), label: "通用", symbol: "gearshape", height: 490)
        tabController.addPane(ShortcutSettingsView(settings: settings), label: "快捷键", symbol: "command", height: 640)
        tabController.addPane(AccountSettingsView(model: model, profiles: profiles), label: "账户", symbol: "person.2", height: 420)
        tabController.addPane(WebSettingsView(model: model, settings: settings), label: "网页", symbol: "globe", height: 360)
        tabController.addPane(AboutSettingsView(), label: "关于", symbol: "info.circle", height: 340)

        let window = NSWindow(contentViewController: tabController)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        tabController.fitWindow(animated: false)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(pane: Pane?) {
        if let pane { tabController.selectedTabViewItemIndex = pane.rawValue }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        // Otherwise AppKit focuses the first text field, e.g. selecting an account name.
        window?.makeFirstResponder(nil)
    }
}

/// Resizes the window to each pane's height on selection, like System Settings did before
/// it became a sidebar app.
private final class SettingsTabViewController: NSTabViewController {
    private static let paneWidth: CGFloat = 540

    func addPane<Content: View>(_ view: Content, label: String, symbol: String, height: CGFloat) {
        let hosting = NSHostingController(rootView: view)
        // The tab controller propagates the selected child's title to the window.
        hosting.title = label
        hosting.sizingOptions = []
        hosting.preferredContentSize = NSSize(width: Self.paneWidth, height: height)
        let item = NSTabViewItem(viewController: hosting)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        addTabViewItem(item)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow(animated: true)
    }

    func fitWindow(animated: Bool) {
        guard let window = view.window,
              let item = tabView.selectedTabViewItem,
              let size = item.viewController?.preferredContentSize
        else { return }
        window.title = item.label
        let current = window.contentRect(forFrameRect: window.frame)
        // Keep the top edge fixed while the height changes.
        let content = NSRect(x: current.minX, y: current.maxY - size.height, width: size.width, height: size.height)
        window.setFrame(window.frameRect(forContentRect: content), display: true, animate: animated && window.isVisible)
        window.makeFirstResponder(nil)
    }
}
