import AppKit
import SwiftUI

private extension NSToolbarItem.Identifier {
    static let quickTitle = Self("com.sink7.DeepSeekNative.quick.title")
    static let quickNewChat = Self("com.sink7.DeepSeekNative.quick.newChat")
    static let quickOpenInMain = Self("com.sink7.DeepSeekNative.quick.openInMain")
}

/// The compact window a quick chat continues in. It floats above other apps without
/// activating DeepSeek, and remembers its size (not its position, which follows the bar).
@MainActor
final class QuickChatPanel: NSPanel, NSWindowDelegate, NSToolbarDelegate {
    private static let sizeKey = "quickChatSize"
    private static let defaultSize = NSSize(width: 480, height: 680)

    var onClose: (() -> Void)?
    var onNewChat: (() -> Void)?
    var onOpenInMainWindow: (() -> Void)?

    private(set) var session: QuickChatSession?
    private let titleField = NSTextField(labelWithString: "DeepSeek")
    private lazy var newChatItem = makeButtonItem(.quickNewChat, symbol: "square.and.pencil", action: #selector(newChat(_:)))
    private lazy var openInMainItem = makeButtonItem(
        .quickOpenInMain, symbol: "arrow.up.left.and.arrow.down.right", action: #selector(openInMainWindow(_:))
    )
    private var appearanceObservation: NSKeyValueObservation?

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.savedSize),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        toolbarStyle = .unifiedCompact
        minSize = NSSize(width: 360, height: 420)
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        delegate = self

        let toolbar = NSToolbar(identifier: "DeepSeekQuickChatToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = [.quickTitle]
        self.toolbar = toolbar

        observeChanges { [weak self] in self?.applyToolbarText() }
        appearanceObservation = observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.matchTitlebar(to: self?.session?.pageBackgroundColor) }
        }
    }

    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        super.performKeyEquivalent(with: event) || performEditingKeyEquivalent(event)
    }

    /// Esc, when the page doesn't use it.
    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onClose?()
        return false
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        UserDefaults.standard.set(NSStringFromSize(frame.size), forKey: Self.sizeKey)
    }

    // MARK: - Content

    func attach(_ session: QuickChatSession) {
        guard session !== self.session else { return }
        self.session = session
        let hosting = NSHostingView(rootView: QuickChatView(session: session))
        hosting.sizingOptions = []
        contentView = hosting
        // Follows this session until another one is attached.
        observeChanges { [weak self, weak session] in
            guard let self, let session, session === self.session else { return }
            self.titleField.stringValue = session.title
            self.matchTitlebar(to: session.pageBackgroundColor)
        }
    }

    func detachSession() {
        session = nil
        contentView = nil
    }

    /// Opens below the input bar's top edge, centred on it, inside the screen's visible area.
    func present(below anchor: NSRect, on screen: NSScreen) {
        let visible = screen.visibleFrame
        let size = NSSize(
            width: min(Self.savedSize.width, visible.width - 40),
            height: min(Self.savedSize.height, visible.height - 40)
        )
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY - size.height)
        origin.x = min(max(origin.x, visible.minX + 20), visible.maxX - size.width - 20)
        origin.y = min(max(origin.y, visible.minY + 20), visible.maxY - size.height - 20)
        setFrame(NSRect(origin: origin, size: size).integral, display: false)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(session?.webView)
    }

    private static var savedSize: NSSize {
        guard let string = UserDefaults.standard.string(forKey: sizeKey) else { return defaultSize }
        let size = NSSizeFromString(string)
        return size.width > 0 && size.height > 0 ? size : defaultSize
    }

    // MARK: - Toolbar

    private func applyToolbarText() {
        for (item, label) in [(newChatItem, L("New Chat")), (openInMainItem, L("Open in Main Window"))] {
            item.label = label
            item.paletteLabel = label
            item.toolTip = label
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .quickTitle, .flexibleSpace, .quickNewChat, .quickOpenInMain]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .quickNewChat:
            return newChatItem
        case .quickOpenInMain:
            return openInMainItem
        case .quickTitle:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            titleField.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            titleField.textColor = .labelColor
            titleField.alignment = .center
            titleField.lineBreakMode = .byTruncatingTail
            titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            titleField.widthAnchor.constraint(lessThanOrEqualToConstant: 240).isActive = true
            item.view = titleField
            item.visibilityPriority = .low
            return item
        default:
            return nil
        }
    }

    private func makeButtonItem(_ identifier: NSToolbarItem.Identifier, symbol: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.target = self
        item.action = action
        item.isBordered = true
        return item
    }

    @objc private func newChat(_ sender: Any?) {
        onNewChat?()
    }

    @objc private func openInMainWindow(_ sender: Any?) {
        onOpenInMainWindow?()
    }
}

private struct QuickChatView: View {
    let session: QuickChatSession

    var body: some View {
        ZStack {
            WebViewContainer(webView: session.webView)
                .opacity(session.hasContent ? 1 : 0)
            if !session.hasContent {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .animation(.easeOut(duration: 0.2), value: session.hasContent)
    }
}
