import AppKit

/// Quick chat: the global shortcut opens a small input bar over any app; sending a question
/// continues in a compact floating window, leaving the main window and its chat alone.
@MainActor
final class QuickChatController {
    /// A hidden quick chat keeps its page loaded for the next question this long, then
    /// releases the web content process.
    private static let idleLifetime: Duration = .seconds(600)

    private let model: WebViewModel
    private let profiles: ProfileStore
    private let mainWindow: MainWindowController
    private let entryPanel = QuickEntryPanel()
    private let chatPanel = QuickChatPanel()
    private var session: QuickChatSession?
    /// The account the session's page is signed in as.
    private var sessionProfileID: UUID?
    private var teardown: Task<Void, Never>?

    init(model: WebViewModel, profiles: ProfileStore, mainWindow: MainWindowController) {
        self.model = model
        self.profiles = profiles
        self.mainWindow = mainWindow

        entryPanel.onSubmit = { [weak self] in self?.submit($0) }
        entryPanel.onCancel = { [weak self] in self?.hideEntry() }
        chatPanel.onClose = { [weak self] in self?.hideChat() }
        chatPanel.onNewChat = { [weak self] in self?.showEntry() }
        chatPanel.onOpenInMainWindow = { [weak self] in self?.openInMainWindow() }

        // Start over after switching accounts.
        observeChanges { [weak self] in
            guard let self else { return }
            let current = self.profiles.currentID
            if self.session != nil, self.sessionProfileID != current { self.endSession() }
        }
    }

    private var isVisible: Bool { entryPanel.isVisible || chatPanel.isVisible }

    /// Bound to the quick chat shortcut: opens the bar, or puts away what's showing.
    func toggle() {
        if entryPanel.isVisible {
            hideEntry()
        } else if chatPanel.isVisible {
            if chatPanel.isKeyWindow {
                hideChat()
            } else {
                chatPanel.makeKeyAndOrderFront(nil)
            }
        } else {
            showEntry()
        }
    }

    func showEntry() {
        teardown?.cancel()
        hideChat()
        revealApp()
        entryPanel.present(on: Self.screenWithMouse())
        // Start loading now so the page is ready by the time the question is.
        prepareSession()
    }

    private func hideEntry() {
        guard entryPanel.isVisible else { return }
        entryPanel.orderOut(nil)
        scheduleTeardown()
    }

    private func submit(_ text: String) {
        let anchor = entryPanel.frame
        let screen = entryPanel.screen ?? Self.screenWithMouse()
        entryPanel.model.text = ""
        entryPanel.orderOut(nil)

        let session = prepareSession()
        chatPanel.attach(session)
        chatPanel.present(below: anchor, on: screen)
        session.send(text)
    }

    private func hideChat() {
        guard chatPanel.isVisible else { return }
        chatPanel.orderOut(nil)
        // The conversation stays in DeepSeek's history; get a blank one ready for next time.
        session?.startNewChat()
        scheduleTeardown()
    }

    private func openInMainWindow() {
        if let url = session?.currentURL, LinkPolicy.isAppURL(url) {
            model.load(url)
        }
        hideChat()
        mainWindow.present()
    }

    @discardableResult
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
            guard !Task.isCancelled, let self, !self.isVisible else { return }
            self.endSession()
        }
    }

    private func endSession() {
        teardown?.cancel()
        entryPanel.orderOut(nil)
        chatPanel.orderOut(nil)
        chatPanel.detachSession()
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
