import AppKit
import WebKit

/// A secondary window for `window.open` targets: sign-in providers (which talk back to
/// the opener), blank windows the opener navigates later, and the optional in-app browser.
@MainActor
final class PopupWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    enum Mode {
        /// Stays in the app; may end on a DeepSeek page or close itself.
        case signIn
        /// Opened blank; the first real URL decides where it belongs.
        case undecided
        /// External link shown in-app because the user turned off "open in browser".
        case browser
    }

    let webView: WKWebView
    private var mode: Mode
    private weak var model: WebViewModel?
    private var titleObservation: NSKeyValueObservation?
    private var didReturnToApp = false

    init(
        configuration: WKWebViewConfiguration, features: WKWindowFeatures?, mode: Mode,
        model: WebViewModel, parent: NSWindow?
    ) {
        // WebKit requires the popup to be created with exactly the configuration it passed in.
        webView = WKWebView(frame: .zero, configuration: configuration)
        self.mode = mode
        self.model = model

        let fallback = mode == .browser ? NSSize(width: 1040, height: 760) : NSSize(width: 520, height: 680)
        let size = NSSize(
            width: max(360, features?.width.map { CGFloat($0.doubleValue) } ?? fallback.width),
            height: max(320, features?.height.map { CGFloat($0.doubleValue) } ?? fallback.height)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.title = mode == .browser ? L("Loading…") : L("Sign In")
        window.contentView = webView
        super.init(window: window)

        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        titleObservation = webView.observe(\.title) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                guard let self, let title = webView.title, !title.isEmpty else { return }
                self.window?.title = title
            }
        }
        place(window, over: parent)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func place(_ window: NSWindow, over parent: NSWindow?) {
        guard let parent, parent.isVisible else {
            window.center()
            return
        }
        let frame = parent.frame
        let origin = NSPoint(
            x: frame.midX - window.frame.width / 2,
            y: frame.midY - window.frame.height / 2
        )
        window.setFrameOrigin(origin)
        if let screen = parent.screen {
            window.setFrame(window.constrainFrameRect(window.frame, to: screen), display: false)
        }
    }

    private func closeSoon() {
        // Never tear the web view down from inside one of its own delegate callbacks.
        Task { @MainActor [weak self] in self?.close() }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        webView.stopLoading()
        model?.popupDidClose(self)
    }

    // MARK: WKNavigationDelegate

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if !LinkPolicy.isWebURL(url) {
            if LinkPolicy.isInlineURL(url) {
                decisionHandler(.allow)
            } else {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            }
            return
        }
        guard navigationAction.targetFrame?.isMainFrame == true, mode == .undecided else {
            decisionHandler(.allow)
            return
        }

        if LinkPolicy.isSignInURL(url) {
            mode = .signIn
            decisionHandler(.allow)
        } else if LinkPolicy.isAppURL(url) {
            decisionHandler(.cancel)
            model?.loadInMainWindow(navigationAction.request)
            closeSoon()
        } else {
            decisionHandler(.cancel)
            model?.openExternal(url)
            closeSoon()
        }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(WebViewModel.policy(for: navigationResponse))
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        model?.downloads.attach(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        model?.downloads.attach(download)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Redirect-style sign-in that lands back on DeepSeek inside the popup: the cookie is
        // already in the shared data store, so hand over to the main window.
        guard mode == .signIn, !didReturnToApp, let url = webView.url, LinkPolicy.isAppURL(url) else { return }
        didReturnToApp = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, self.window?.isVisible == true else { return }
            self.close()
            self.model?.signInPopupReturnedToApp()
        }
    }

    // MARK: WKUIDelegate

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        webView.load(navigationAction.request)
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        closeSoon()
    }

    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void
    ) {
        WebDialogs.alert(message: message, frame: frame, in: window, completion: completionHandler)
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void
    ) {
        WebDialogs.confirm(message: message, frame: frame, in: window, completion: completionHandler)
    }

    func webView(
        _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void
    ) {
        WebDialogs.prompt(prompt, defaultText: defaultText, frame: frame, in: window, completion: completionHandler)
    }

    func webView(
        _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void
    ) {
        WebDialogs.openPanel(parameters: parameters, in: window, completion: completionHandler)
    }
}
