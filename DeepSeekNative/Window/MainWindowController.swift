import AppKit
import SwiftUI

private extension NSToolbarItem.Identifier {
    static let newChat = Self("com.sink7.DeepSeekNative.newChat")
    static let conversationTitle = Self("com.sink7.DeepSeekNative.title")
    static let reload = Self("com.sink7.DeepSeekNative.reload")
    static let pin = Self("com.sink7.DeepSeekNative.pin")
}

/// The single chat window. It is hidden rather than destroyed when closed, so the page,
/// any reply still streaming in, and the sign-in all survive until the next summon.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private static let frameAutosaveName = "DeepSeekMainWindow"

    private let model: WebViewModel
    private let settings: AppSettings
    private let titleField = NSTextField(labelWithString: "DeepSeek")
    private lazy var newChatItem = makeButtonItem(.newChat, symbol: "square.and.pencil", action: #selector(newChat(_:)))
    private lazy var reloadItem = makeButtonItem(.reload, symbol: "arrow.clockwise", action: #selector(reload(_:)))
    private lazy var pinItem = makeButtonItem(.pin, symbol: "pin", action: #selector(togglePin(_:)))
    private lazy var titleItem = NSToolbarItem(itemIdentifier: .conversationTitle)
    private var appearanceObservation: NSKeyValueObservation?

    init(model: WebViewModel, settings: AppSettings) {
        self.model = model
        self.settings = settings

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "DeepSeek"
        window.titleVisibility = .hidden
        // Lets the toolbar take on the page's own background colour.
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unifiedCompact
        window.minSize = NSSize(width: 520, height: 440)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        // Summoning from another Space brings the window to the user instead of switching Spaces.
        window.collectionBehavior = [.fullScreenPrimary, .moveToActiveSpace]

        let hostingView = NSHostingView(rootView: MainContentView(model: model))
        // The window's size is the user's; don't let SwiftUI's ideal size fight the saved frame.
        hostingView.sizingOptions = []
        window.contentView = hostingView

        super.init(window: window)
        window.delegate = self
        installToolbar(in: window)

        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        // The saved frame may belong to a display that is gone or arranged differently now.
        Self.keepOnScreen(window)
        window.setFrameAutosaveName(Self.frameAutosaveName)

        bindState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Showing and hiding

    /// True when the window is what the user is looking at right now.
    var isFrontmost: Bool {
        guard let window else { return false }
        return NSApp.isActive && window.isVisible && window.isKeyWindow && !window.isMiniaturized && window.isOnActiveSpace
    }

    var isFullScreen: Bool {
        window?.styleMask.contains(.fullScreen) ?? false
    }

    func present(centerOnMouseScreen: Bool = false) {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        if centerOnMouseScreen, !isFullScreen { centerOnScreenWithMouse(window) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        Self.keepOnScreen(window)
    }

    /// Pulls the window fully inside its screen's visible area. Needed because
    /// `.moveToActiveSpace` carries the window to another display at the same offset,
    /// which can leave it hanging off the edge of a smaller screen.
    private static func keepOnScreen(_ window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen),
              let screen = window.screen ?? NSScreen.main
        else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        guard !visible.contains(frame) else { return }
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        window.setFrame(frame, display: true)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let window else { return }
        Self.keepOnScreen(window)
    }

    private func centerOnScreenWithMouse(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = (visible.midX - frame.width / 2).rounded()
        frame.origin.y = (visible.midY - frame.height / 2).rounded()
        window.setFrame(frame, display: true)
    }

    // MARK: - State binding

    private func bindState() {
        observeChanges { [weak self] in self?.applyFloating() }
        observeChanges { [weak self] in self?.applyToolbarText() }
        observeChanges { [weak self] in self?.applyTitle() }
        observeChanges { [weak self] in self?.applyChromeColor() }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.applyChromeColor() }
        }
    }

    private func applyFloating() {
        let floating = settings.floatOnTop
        window?.level = floating ? .floating : .normal
        pinItem.image = NSImage(systemSymbolName: floating ? "pin.fill" : "pin", accessibilityDescription: L("Float on Top"))
        pinItem.toolTip = floating ? L("Stop Floating on Top (⌥⌘T)") : L("Float on Top (⌥⌘T)")
    }

    private func applyToolbarText() {
        for (item, label) in [(newChatItem, L("New Chat")), (reloadItem, L("Reload")), (pinItem, L("Float on Top"))] {
            item.label = label
            item.paletteLabel = label
        }
        newChatItem.toolTip = L("New Chat (⌘N)")
        reloadItem.toolTip = L("Reload (⌘R)")
        titleItem.label = L("Title")
    }

    private func applyTitle() {
        let title = model.pageTitle
        titleField.stringValue = title
        window?.title = title
    }

    private func applyChromeColor() {
        window?.matchTitlebar(to: model.pageBackgroundColor)
    }

    // MARK: - Toolbar

    private func installToolbar(in window: NSWindow) {
        let toolbar = NSToolbar(identifier: "DeepSeekMainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = [.conversationTitle]
        window.toolbar = toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.newChat, .flexibleSpace, .conversationTitle, .flexibleSpace, .reload, .pin]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .newChat:
            return newChatItem
        case .reload:
            return reloadItem
        case .pin:
            return pinItem
        case .conversationTitle:
            let item = titleItem
            titleField.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            titleField.textColor = .labelColor
            titleField.alignment = .center
            titleField.lineBreakMode = .byTruncatingTail
            titleField.cell?.truncatesLastVisibleLine = true
            titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            titleField.widthAnchor.constraint(lessThanOrEqualToConstant: 440).isActive = true
            item.view = titleField
            item.visibilityPriority = .low
            return item
        default:
            return nil
        }
    }

    /// Labels and tooltips are set by `applyToolbarText()`, in the current language.
    private func makeButtonItem(_ identifier: NSToolbarItem.Identifier, symbol: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.target = self
        item.action = action
        item.isBordered = true
        return item
    }

    // MARK: - Actions

    @objc private func newChat(_ sender: Any?) {
        model.startNewChat()
    }

    @objc private func reload(_ sender: Any?) {
        model.reload()
    }

    @objc private func togglePin(_ sender: Any?) {
        settings.floatOnTop.toggle()
    }
}

extension NSWindow {
    /// Paints the title bar with the page's background so toolbar and page read as one
    /// surface — but only when that colour suits the current appearance, so the toolbar
    /// icons keep their contrast.
    func matchTitlebar(to pageColor: NSColor?) {
        let isDarkAppearance = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        guard let color = pageColor?.usingColorSpace(.sRGB), color.alphaComponent > 0.99 else {
            backgroundColor = .windowBackgroundColor
            return
        }
        let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        backgroundColor = (luminance < 0.5) == isDarkAppearance ? color : .windowBackgroundColor
    }
}
