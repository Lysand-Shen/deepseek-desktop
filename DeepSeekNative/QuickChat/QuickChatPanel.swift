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

    private var barHeight: CGFloat = 60

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
            onOpenInMainWindow: { [weak self] in self?.onOpenInMainWindow?() }
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
        if isVisible, !model.isExpanded { onClose?() }
    }

    var isExpanded: Bool { model.isExpanded }

    // MARK: - States

    /// Shows the bar in the lower part of the screen, leaving room to grow upwards.
    func presentBar(on screen: NSScreen) {
        let visible = screen.visibleFrame
        model.isExpanded = false
        model.expandedHeight = min(Self.maxExpandedHeight, visible.height - 80)
        let width = min(Self.width, visible.width - 40)
        let origin = NSPoint(x: (visible.midX - width / 2).rounded(), y: (visible.minY + visible.height * 0.22).rounded())
        setFrame(NSRect(origin: origin, size: NSSize(width: width, height: barHeight)), display: false)
        makeKeyAndOrderFront(nil)
        model.focusRequest += 1
    }

    /// Grows the bar upwards into the conversation, keeping the bottom edge in place
    /// unless the screen is too short.
    func expand() {
        guard !model.isExpanded else { return }
        var target = frame
        target.size.height = model.expandedHeight
        if let visible = screen?.visibleFrame, target.maxY > visible.maxY - 12 {
            target.origin.y = max(visible.minY + 12, visible.maxY - 12 - target.height)
        }
        model.isExpanded = true
        animate(to: target) { [weak self] in
            guard let self, let webView = self.model.session?.webView else { return }
            self.makeFirstResponder(webView)
        }
    }

    /// Shrinks back into the bar for a new question.
    func collapse() {
        guard model.isExpanded else { return }
        var target = frame
        target.size.height = barHeight
        model.isExpanded = false
        animate(to: target) { [weak self] in self?.model.focusRequest += 1 }
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

    private var surfaceColor: Color {
        if model.isExpanded, let color = model.session?.pageBackgroundColor { return Color(nsColor: color) }
        return Color(nsColor: .textBackgroundColor)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                if let session = model.session {
                    ConversationView(
                        session: session, onClose: onClose, onNewChat: onNewChat, onOpenInMainWindow: onOpenInMainWindow
                    )
                    .frame(height: model.expandedHeight)
                    .opacity(model.isExpanded ? 1 : 0)
                    .allowsHitTesting(model.isExpanded)
                }
                InputBar(model: model, onSubmit: onSubmit, onHeightChange: onBarHeightChange)
                    .opacity(model.isExpanded ? 0 : 1)
                    .allowsHitTesting(!model.isExpanded)
            }
            // The conversation is taller than the window while it's a bar: pinned to the
            // window's bottom, it overflows upwards and the window clips it.
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            .background(surfaceColor)
            .overlay {
                RoundedRectangle(cornerRadius: QuickChatPanel.cornerRadius, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
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
            TextField(L("Ask DeepSeek…"), text: $model.text, axis: .vertical)
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
        .onChange(of: model.focusRequest) { _, _ in isFocused = true }
        .onAppear { isFocused = true }
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
            .frame(height: 56)
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
