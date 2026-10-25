import AppKit

/// Quick chat: the global shortcut opens a small input bar over any app; sending a question
/// grows it into a compact conversation, leaving the main window and its chat alone.
@MainActor
final class QuickChatController {
    /// A hidden quick chat keeps its page loaded for the next question this long, then
    /// releases the web content process.
    private static let idleLifetime: Duration = .seconds(600)

    private enum Key {
        static let lastConversation = "quickChatLastConversation"
        static let lastConversationProfile = "quickChatLastConversationProfile"
    }

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
        panel.onDropFiles = { [weak self] in self?.attach($0) }

        // Start over after switching accounts.
        observeChanges { [weak self] in
            guard let self else { return }
            let current = self.profiles.currentID
            if self.session != nil, self.sessionProfileID != current { self.endSession() }
        }
    }

    /// Bound to the quick chat shortcut: opens quick chat, or puts away what's showing.
    func toggle() {
        if !panel.isVisible {
            show()
        } else if panel.isKeyWindow {
            hide()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Opens the bar, or the conversation left last time when Settings asks for that.
    func show() {
        if model.settings.quickChatOpening == .lastConversation, let url = lastConversation {
            showConversation(url)
        } else {
            showBar()
        }
    }

    private func showBar() {
        teardown?.cancel()
        revealApp()
        // Start loading now so the page is ready by the time the question is.
        panel.model.session = prepareSession()
        panel.presentBar(on: Self.screenWithMouse())
    }

    private func showConversation(_ url: URL) {
        teardown?.cancel()
        revealApp()
        let session = prepareSession()
        // Still on the page unless it was released while hidden.
        if session.currentURL != url { session.load(url) }
        panel.model.session = session
        panel.presentConversation(on: Self.screenWithMouse())
        session.focusInput()
    }

    private func submit(_ text: String) {
        panel.model.text = ""
        prepareSession().send(text)
        panel.expand()
    }

    /// Files dropped on the bar start a new chat; dropped on a conversation, they join it.
    /// Either way they wait in the page's message box, with whatever was typed in the bar.
    private func attach(_ urls: [URL]) {
        let draft = panel.model.text
        panel.model.text = ""
        prepareSession().attach(urls, draft: draft, inNewChat: !panel.isExpanded)
        // The drag came from another app, which has the keyboard now.
        panel.makeKeyAndOrderFront(nil)
        panel.expand()
    }

    private func hide() {
        guard panel.isVisible else { return }
        if panel.isExpanded {
            rememberConversation()
            // The conversation stays in DeepSeek's history. Unless it's to be reopened, get a
            // blank one ready for next time.
            if model.settings.quickChatOpening == .newChat { session?.startNewChat() }
        }
        panel.dismiss()
        scheduleTeardown()
    }

    private func newChat() {
        lastConversation = nil
        session?.startNewChat()
        panel.collapse()
    }

    private func rememberConversation() {
        guard let url = session?.currentURL, LinkPolicy.isAppURL(url), url.path != "/" else { return }
        lastConversation = url
    }

    /// The conversation the window showed when it was put away. Kept across launches, and
    /// only for the account it belongs to.
    private var lastConversation: URL? {
        get {
            let defaults = UserDefaults.standard
            guard defaults.string(forKey: Key.lastConversationProfile) == profiles.currentID.uuidString else { return nil }
            return defaults.url(forKey: Key.lastConversation)
        }
        set {
            let defaults = UserDefaults.standard
            if let newValue {
                defaults.set(newValue, forKey: Key.lastConversation)
                defaults.set(profiles.currentID.uuidString, forKey: Key.lastConversationProfile)
            } else {
                defaults.removeObject(forKey: Key.lastConversation)
                defaults.removeObject(forKey: Key.lastConversationProfile)
            }
        }
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
        session.webView.onFileDrop = { [weak self] in self?.attach($0) }
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
