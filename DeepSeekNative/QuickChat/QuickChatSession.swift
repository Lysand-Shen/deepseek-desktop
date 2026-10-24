import AppKit
import Observation
import WebKit
import os

private let log = Logger(subsystem: "com.sink7.DeepSeekNative", category: "QuickChat")

/// The compact window's own web view. It shares the current account's cookies with the main
/// window but keeps a page of its own, so quick questions don't disturb the main conversation.
@MainActor
@Observable
final class QuickChatSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    private(set) var hasContent = false
    private(set) var title = "DeepSeek"
    private(set) var pageBackgroundColor: NSColor?

    @ObservationIgnored private weak var model: WebViewModel?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    /// True while the page is a new chat that nothing has been sent from yet.
    @ObservationIgnored private var isFreshChat = false
    /// Waits here until the page has loaded.
    @ObservationIgnored private var pendingPrompt: String?

    init(model: WebViewModel) {
        self.model = model
        let configuration = model.makeAuxiliaryConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController.addUserScript(WKUserScript(
            source: WebScripts.quickChatStyle, injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = false
        webView.pageZoom = model.settings.pageZoom
        webView.isInspectable = model.webView.isInspectable
        observations = [
            webView.observe(\.title) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.updateTitle(webView.title) }
            },
            webView.observe(\.underPageBackgroundColor, options: [.initial]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.pageBackgroundColor = webView.underPageBackgroundColor }
            },
        ]
        startNewChat()
    }

    var currentURL: URL? { webView.url }

    /// Loads an empty chat, ready for the next question.
    func startNewChat() {
        isFreshChat = false
        webView.load(URLRequest(url: LinkPolicy.homeURL))
    }

    /// Sends `text` as the first message of a new chat.
    func send(_ text: String) {
        if isFreshChat, !webView.isLoading {
            submit(text)
        } else {
            pendingPrompt = text
            if !webView.isLoading || webView.url?.path != "/" { startNewChat() }
        }
    }

    private func submit(_ text: String) {
        isFreshChat = false
        webView.callAsyncJavaScript(WebScripts.submitPrompt, arguments: ["text": text], in: nil, in: .page) { result in
            switch result {
            case .success(let status): log.info("Prompt submitted: \(String(describing: status), privacy: .public)")
            case .failure(let error): log.error("Prompt failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func updateTitle(_ raw: String?) {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmed.isEmpty || trimmed.hasPrefix("DeepSeek") ? "DeepSeek" : trimmed.replacingOccurrences(of: " - DeepSeek", with: "")
    }

    // MARK: WKNavigationDelegate

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(policy(for: navigationAction))
    }

    /// Like the main window: DeepSeek and sign-in pages stay here, everything else opens outside.
    private func policy(for action: WKNavigationAction) -> WKNavigationActionPolicy {
        if action.shouldPerformDownload { return .download }
        guard let url = action.request.url else { return .allow }
        if !LinkPolicy.isWebURL(url) {
            if LinkPolicy.isInlineURL(url) { return .allow }
            NSWorkspace.shared.open(url)
            return .cancel
        }
        guard let frame = action.targetFrame, frame.isMainFrame else { return .allow }
        if action.navigationType == .backForward || action.navigationType == .reload { return .allow }
        if !action.modifierFlags.contains(.command) {
            if LinkPolicy.isAppURL(url) { return .allow }
            if action.navigationType == .linkActivated ? LinkPolicy.isSignInURL(url) : LinkPolicy.isTrustedRedirect(url) {
                return .allow
            }
        }
        model?.openExternal(url)
        return .cancel
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
        hasContent = true
        isFreshChat = webView.url.map { LinkPolicy.isAppURL($0) && $0.path == "/" } ?? false
        if let prompt = pendingPrompt {
            pendingPrompt = nil
            submit(prompt)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        startNewChat()
    }

    // MARK: WKUIDelegate

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        model?.makePopup(configuration: configuration, action: navigationAction, features: windowFeatures)
    }

    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void
    ) {
        WebDialogs.alert(message: message, frame: frame, in: webView.window, completion: completionHandler)
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void
    ) {
        WebDialogs.confirm(message: message, frame: frame, in: webView.window, completion: completionHandler)
    }

    func webView(
        _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void
    ) {
        WebDialogs.openPanel(parameters: parameters, in: webView.window, completion: completionHandler)
    }
}
