import AppKit
import Observation
import SwiftUI

/// What the quick chat panel shows: the input bar, or the conversation it grew into.
@MainActor
@Observable
final class QuickChatModel {
    /// The bar's draft. Kept when the bar is dismissed.
    var text = ""
    /// Bumped to move keyboard focus into the bar's field.
    var focusRequest = 0
    fileprivate(set) var isExpanded = false
    /// The conversation's height. The page is laid out at this size even while only the
    /// bar shows, so expanding reveals it rather than re-flowing it.
    fileprivate(set) var expandedHeight: CGFloat = 640
    /// True while files are dragged over the bar.
    fileprivate var isDropTargeted = false
    var session: QuickChatSession?
}

/// Quick chat in one floating surface, like Gemini's: a pill-shaped input bar that grows
/// upwards into a compact conversation, with the page's own input where the bar was.
/// It never activates the app, so the app the user is in keeps its menu bar and focus.
@MainActor
final class QuickChatPanel: NSPanel {
    static let width: CGFloat = 560
    static let cornerRadius: CGFloat = 26
    private static let maxExpandedHeight: CGFloat = 680

    let model = QuickChatModel()
    var onSubmit: ((String) -> Void)?
    var onClose: (() -> Void)?
    var onNewChat: (() -> Void)?
    var onOpenInMainWindow: (() -> Void)?
    var onDropFiles: (([URL]) -> Void)?

    private var barHeight: CGFloat = 60
    /// Height of the strip with the floating buttons above the page.
    fileprivate static let topStripHeight: CGFloat = 56

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 60),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: true
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow

        // Clips the web view too, which SwiftUI's clip shapes don't reach.
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = Self.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: QuickChatView(
            model: model,
            onSubmit: { [weak self] in self?.onSubmit?($0) },
            onBarHeightChange: { [weak self] in self?.fitBar(to: $0) },
            onClose: { [weak self] in self?.onClose?() },
            onNewChat: { [weak self] in self?.onNewChat?() },
            onOpenInMainWindow: { [weak self] in self?.onOpenInMainWindow?() },
            onDropFiles: { [weak self] in self?.onDropFiles?($0) }
        ))
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        contentView = container
    }

    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        super.performKeyEquivalent(with: event) || performEditingKeyEquivalent(event)
    }

    /// Esc, unless the page used it.
    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    override func resignKey() {
        super.resignKey()
        // Clicking elsewhere dismisses the bar, like Spotlight; a conversation stays up.
        guard isVisible, !model.isExpanded else { return }
        // Wait for the mouse button to come back up first: the click may start dragging a
        // file over to the bar.
        Task { @MainActor [weak self] in
            while NSEvent.pressedMouseButtons != 0 {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, self.isVisible, !self.isKeyWindow, !self.model.isExpanded else { return }
            self.onClose?()
        }
    }

    var isExpanded: Bool { model.isExpanded }

    // MARK: - States

    /// Shows the bar in the lower part of the screen, leaving room to grow upwards.
    func presentBar(on screen: NSScreen) {
        model.isExpanded = false
        let frame = barFrame(on: screen)
        // Out of the window until the bar expands (DeepSeek's page grabs the keyboard as
        // soon as it loads), but laid out at the conversation's size already.
        if let webView = model.session?.webView, webView.superview == nil {
            webView.setFrameSize(NSSize(width: frame.width, height: model.expandedHeight - Self.topStripHeight))
        }
        setFrame(frame, display: false)
        makeKeyAndOrderFront(nil)
        focusBar()
    }

    /// Shows a conversation straight away, as if the bar had just grown into it.
    func presentConversation(on screen: NSScreen) {
        model.isExpanded = true
        var target = barFrame(on: screen)
        target.size.height = model.expandedHeight
        setFrame(Self.fitted(target, on: screen), display: false)
        makeKeyAndOrderFront(nil)
        invalidateShadow()
        if let webView = model.session?.webView { makeFirstResponder(webView) }
    }

    /// Grows the bar upwards into the conversation, keeping the bottom edge in place
    /// unless the screen is too short.
    func expand() {
        guard !model.isExpanded, let screen else { return }
        var target = frame
        target.size.height = model.expandedHeight
        model.isExpanded = true
        animate(to: Self.fitted(target, on: screen)) { [weak self] in
            guard let self, let webView = self.model.session?.webView else { return }
            self.makeFirstResponder(webView)
        }
    }

    /// Centred, low on the screen; also sizes the conversation for this screen.
    private func barFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        model.expandedHeight = min(Self.maxExpandedHeight, visible.height - 80)
        let width = min(Self.width, visible.width - 40)
        return NSRect(
            x: (visible.midX - width / 2).rounded(), y: (visible.minY + visible.height * 0.22).rounded(),
            width: width, height: barHeight
        )
    }

    /// Moves a frame down just enough to keep its top on screen.
    private static func fitted(_ frame: NSRect, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        var frame = frame
        if frame.maxY > visible.maxY - 12 {
            frame.origin.y = max(visible.minY + 12, visible.maxY - 12 - frame.height)
        }
        return frame
    }

    /// Shrinks back into the bar for a new question.
    func collapse() {
        guard model.isExpanded else { return }
        // The bar closes when it isn't key, and it needs the keyboard for the question anyway.
        makeKeyAndOrderFront(nil)
        var target = frame
        target.size.height = barHeight
        model.isExpanded = false
        animate(to: target) { [weak self] in self?.focusBar() }
    }

    /// Clears whatever took the keyboard when the window became key, then lets SwiftUI focus
    /// the field once it has.
    private func focusBar() {
        makeFirstResponder(nil)
        Task { @MainActor [weak self] in self?.model.focusRequest += 1 }
    }

    /// Hides without animation and resets to the bar for next time.
    func dismiss() {
        orderOut(nil)
        model.isExpanded = false
        var bar = frame
        bar.size.height = barHeight
        setFrame(bar, display: false)
    }

    private func animate(to target: NSRect, completion: @escaping @MainActor () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            animator().setFrame(target, display: true)
        } completionHandler: {
            MainActor.assumeIsolated {
                self.invalidateShadow()
                completion()
            }
        }
    }

    /// Grows downwards as the bar's text wraps, keeping the top edge where it was.
    private func fitBar(to height: CGFloat) {
        let height = height.rounded(.up)
        barHeight = height
        guard !model.isExpanded, abs(frame.height - height) > 0.5 else { return }
        var newFrame = frame
        newFrame.origin.y += frame.height - height
        newFrame.size.height = height
        setFrame(newFrame, display: true)
        invalidateShadow()
    }
}

// MARK: - Views

private struct QuickChatView: View {
    @Bindable var model: QuickChatModel
    let onSubmit: (String) -> Void
    let onBarHeightChange: (CGFloat) -> Void
    let onClose: () -> Void
    let onNewChat: () -> Void
    let onOpenInMainWindow: () -> Void
    let onDropFiles: ([URL]) -> Void

    private var surfaceColor: Color {
        if model.isExpanded, let color = model.session?.pageBackgroundColor { return Color(nsColor: color) }
        return Color(nsColor: .textBackgroundColor)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                if let session = model.session, model.isExpanded {
                    ConversationView(
                        session: session, onClose: onClose, onNewChat: onNewChat, onOpenInMainWindow: onOpenInMainWindow
                    )
                    .frame(height: model.expandedHeight)
                    .transition(.opacity)
                }
                InputBar(model: model, onSubmit: onSubmit, onHeightChange: onBarHeightChange)
                    .opacity(model.isExpanded ? 0 : 1)
                    .allowsHitTesting(!model.isExpanded)
                    .dropDestination(for: URL.self) { urls, _ in
                        let files = urls.filter(\.isFileURL)
                        guard !files.isEmpty else { return false }
                        onDropFiles(files)
                        return true
                    } isTargeted: { model.isDropTargeted = $0 }
            }
            // The conversation is taller than the window while it's a bar: pinned to the
            // window's bottom, it overflows upwards and the window clips it.
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            .background(surfaceColor)
            .overlay {
                RoundedRectangle(cornerRadius: QuickChatPanel.cornerRadius, style: .continuous)
                    .strokeBorder(
                        model.isDropTargeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                        lineWidth: model.isDropTargeted ? 2 : 0.5
                    )
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.isExpanded)
    }
}

private struct InputBar: View {
    @Bindable var model: QuickChatModel
    let onSubmit: (String) -> Void
    let onHeightChange: (CGFloat) -> Void

    @FocusState private var isFocused: Bool

    private var trimmed: String {
        model.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Image("WhaleGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 3)
            // ↩ sends, ⌥↩ adds a line.
            TextField(model.isDropTargeted ? L("Drop to Attach") : L("Ask DeepSeek…"), text: $model.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .lineLimit(1...8)
                .padding(.vertical, 6)
                .focused($isFocused)
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(trimmed.isEmpty ? Color.secondary.opacity(0.35) : Color.accentColor))
            }
            .buttonStyle(.plain)
            .disabled(trimmed.isEmpty)
            .help(L("Send (↩)"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onHeightChange(proxy.size.height) }
                    .onChange(of: proxy.size.height) { _, height in onHeightChange(height) }
            }
        }
        .onChange(of: model.focusRequest) { _, _ in
            // The state can still read true after the window gave the keyboard to another
            // view, and setting it to true again would change nothing.
            isFocused = false
            Task { @MainActor in isFocused = true }
        }
    }

    private func submit() {
        let text = trimmed
        guard !text.isEmpty else { return }
        onSubmit(text)
    }
}

private struct ConversationView: View {
    let session: QuickChatSession
    let onClose: () -> Void
    let onNewChat: () -> Void
    let onOpenInMainWindow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                FloatingButton(symbol: "xmark", label: L("Close"), action: onClose)
                Spacer()
                FloatingButton(symbol: "square.and.pencil", label: L("New Chat"), action: onNewChat)
                FloatingButton(symbol: "arrow.up.left.and.arrow.down.right", label: L("Open in Main Window"), action: onOpenInMainWindow)
            }
            .padding(.horizontal, 12)
            .frame(height: QuickChatPanel.topStripHeight)
            .background(WindowDragArea())
            ZStack {
                WebViewContainer(webView: session.webView)
                    .opacity(session.hasContent ? 1 : 0)
                if !session.hasContent {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }
}

/// A round button that floats over the conversation, as in Gemini's quick window.
private struct FloatingButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Lets the borderless panel be dragged by its top strip.
private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}
