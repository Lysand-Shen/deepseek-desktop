import AppKit
import Observation
import SwiftUI

/// What's typed in the quick chat bar. Kept when the bar is dismissed, like a draft.
@MainActor
@Observable
final class QuickEntryModel {
    var text = ""
    /// Bumped to move keyboard focus into the field each time the bar appears.
    var focusRequest = 0
}

/// The floating input bar. It doesn't activate the app, so the app the user was in keeps
/// its menu bar and gets focus back when the bar goes away.
@MainActor
final class QuickEntryPanel: NSPanel {
    static let width: CGFloat = 680
    private static let cornerRadius: CGFloat = 18

    let model = QuickEntryModel()
    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 64),
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
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        animationBehavior = .utilityWindow

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius)

        let hosting = NSHostingView(rootView: QuickEntryView(
            model: model,
            cornerRadius: Self.cornerRadius,
            onSubmit: { [weak self] in self?.onSubmit?($0) },
            onHeightChange: { [weak self] in self?.fitHeight($0) }
        ))
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        contentView = background
    }

    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        super.performKeyEquivalent(with: event) || performEditingKeyEquivalent(event)
    }

    /// Esc
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func resignKey() {
        super.resignKey()
        // Clicking anywhere else dismisses the bar, like Spotlight.
        if isVisible { onCancel?() }
    }

    func present(on screen: NSScreen) {
        let visible = screen.visibleFrame
        let width = min(Self.width, visible.width - 80)
        let origin = NSPoint(
            x: (visible.midX - width / 2).rounded(),
            y: (visible.maxY - visible.height * 0.24 - frame.height).rounded()
        )
        setFrame(NSRect(origin: origin, size: NSSize(width: width, height: frame.height)), display: false)
        makeKeyAndOrderFront(nil)
        model.focusRequest += 1
    }

    /// Grows downwards as the text wraps, keeping the top edge where it was.
    private func fitHeight(_ height: CGFloat) {
        let height = height.rounded(.up)
        guard abs(frame.height - height) > 0.5 else { return }
        var newFrame = frame
        newFrame.origin.y += frame.height - height
        newFrame.size.height = height
        setFrame(newFrame, display: true)
        invalidateShadow()
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

private struct QuickEntryView: View {
    @Bindable var model: QuickEntryModel
    let cornerRadius: CGFloat
    let onSubmit: (String) -> Void
    let onHeightChange: (CGFloat) -> Void

    @FocusState private var isFocused: Bool

    private var trimmed: String {
        model.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image("WhaleGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 1)
            // ⌥↩ adds a line; ↩ sends.
            TextField(L("Ask DeepSeek…"), text: $model.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 19))
                .lineLimit(1...8)
                .focused($isFocused)
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .foregroundStyle(trimmed.isEmpty ? Color.secondary : Color.accentColor)
            .disabled(trimmed.isEmpty)
            .help(L("Send (↩)"))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        // The panel takes the height the text needs.
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onHeightChange(proxy.size.height) }
                    .onChange(of: proxy.size.height) { _, height in onHeightChange(height) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
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
