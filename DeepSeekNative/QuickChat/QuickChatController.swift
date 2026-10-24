import AppKit

/// Quick chat: the global shortcut opens a small input bar over any app; sending a question
/// grows it into a compact conversation, leaving the main window and its chat alone.
@MainActor
final class QuickChatController {
    /// A hidden quick chat keeps its page loaded for the next question this long, then
    /// releases the web content process.
    private static let idleLifetime: Duration = .seconds(600)

    private let model: WebViewModel
    private let profiles: ProfileStore
    private let mainWindow: MainWindowController
    private let panel = QuickChatPanel()
    private var session: QuickChatSession?
    /// The account the session's page is signed in as.
    private var sessionProfileID: UUID?
    private var teardown: Task<Void, Never>?

    init(model: WebViewModel, profiles: ProfileStore, mainWindow: MainWindowController) {
        self.model = model
        self.profiles = profiles
        self.mainWindow = mainWindow

        panel.onSubmit = { [weak self] in self?.submit($0) }
        panel.onClose = { [weak self] in self?.hide() }
        panel.onNewChat = { [weak self] in self?.newChat() }
        panel.onOpenInMainWindow = { [weak self] in self?.openInMainWindow() }

        // Start over after switching accounts.
        observeChanges { [weak self] in
            guard let self else { return }
            let current = self.profiles.currentID
            if self.session != nil, self.sessionProfileID != current { self.endSession() }
        }
    }

    /// Bound to the quick chat shortcut: opens the bar, or puts away what's showing.
    func toggle() {
        if !panel.isVisible {
            showBar()
        } else if panel.isKeyWindow {
            hide()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func showBar() {
        teardown?.cancel()
        revealApp()
        // Start loading now so the page is ready by the time the question is.
        panel.model.session = prepareSession()
        panel.presentBar(on: Self.screenWithMouse())
    }

    private func submit(_ text: String) {
        panel.model.text = ""
        prepareSession().send(text)
        panel.expand()
    }

    private func hide() {
        guard panel.isVisible else { return }
        // The conversation stays in DeepSeek's history; get a blank one ready for next time.
        if panel.isExpanded { session?.startNewChat() }
        panel.dismiss()
        scheduleTeardown()
    }

    private func newChat() {
        session?.startNewChat()
        panel.collapse()
    }

    private func openInMainWindow() {
        if let url = session?.currentURL, LinkPolicy.isAppURL(url) {
            model.load(url)
        }
        hide()
        mainWindow.present()
    }

    private func prepareSession() -> QuickChatSession {
        if let session { return session }
        let session = QuickChatSession(model: model)
        self.session = session
        sessionProfileID = profiles.currentID
        return session
    }

    private func scheduleTeardown() {
        teardown?.cancel()
        teardown = Task { [weak self] in
            try? await Task.sleep(for: Self.idleLifetime)
            guard !Task.isCancelled, let self, !self.panel.isVisible else { return }
            self.endSession()
        }
    }

    private func endSession() {
        teardown?.cancel()
        panel.dismiss()
        panel.model.session = nil
        session = nil
    }

    /// A hidden app can't show windows. Unhide it without bringing back the main window,
    /// which went away together with the app.
    private func revealApp() {
        guard NSApp.isHidden else { return }
        mainWindow.window?.orderOut(nil)
        NSApp.unhideWithoutActivation()
    }

    private static func screenWithMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
