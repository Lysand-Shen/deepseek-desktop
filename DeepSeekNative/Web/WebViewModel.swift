import AppKit
import Observation
import WebKit
import os

private let log = Logger(subsystem: "com.sink7.DeepSeekNative", category: "Web")

/// Owns the DeepSeek web view and exposes its state to the window, toolbar and menus.
@MainActor
@Observable
final class WebViewModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(PageError)
    }

    /// Stores the kind of failure rather than text, so an error page on screen follows a language switch.
    struct PageError: Equatable {
        enum Kind: Equatable {
            case offline, timedOut, cannotConnect, insecure, crashed, failed
        }

        var kind: Kind
        /// The system's description of the underlying error, for kinds without a message of our own.
        var detail: String?

        var symbol: String {
            switch kind {
            case .offline: "wifi.slash"
            case .timedOut: "clock.badge.exclamationmark"
            case .cannotConnect: "network.slash"
            case .insecure: "lock.trianglebadge.exclamationmark"
            case .crashed, .failed: "exclamationmark.triangle"
            }
        }

        @MainActor var title: String {
            switch kind {
            case .offline: L("You're Offline")
            case .timedOut: L("Connection Timed Out")
            case .cannotConnect: L("Can't Connect to DeepSeek")
            case .insecure: L("Can't Establish a Secure Connection")
            case .crashed: L("The Page Stopped Unexpectedly")
            case .failed: L("The Page Couldn't Load")
            }
        }

        @MainActor var message: String {
            switch kind {
            case .offline: L("Check your network connection. The page reloads automatically when you're back online.")
            case .timedOut: L("DeepSeek isn't responding right now. Try again in a moment.")
            case .cannotConnect: L("The server can't be reached. Check your network or proxy settings.")
            case .crashed: L("The page's web process quit several times in a short time. Try reloading, or clear the cache in Settings.")
            case .insecure, .failed: detail ?? ""
            }
        }
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var symbol: String
        var message: String
        var revealURL: URL?
    }

    private(set) var webView: WKWebView
    /// Bumped whenever `webView` is replaced (account switch) so SwiftUI mounts the new one.
    private(set) var generation = 0
    private(set) var phase: Phase = .loading
    /// False until the first page load completes; the web view stays hidden until then
    /// so launching in Dark Mode doesn't flash an empty white page.
    private(set) var hasContent = false
    private(set) var isLoading = false
    private(set) var progress: Double = 0
    private(set) var pageTitle = "DeepSeek"
    private(set) var currentURL: URL?
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var pageBackgroundColor: NSColor?
    private(set) var isOffline = false
    var toast: Toast?

    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored let profiles: ProfileStore
    @ObservationIgnored let downloads: DownloadManager
    @ObservationIgnored private var delegate: WebViewDelegate?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var popups: [PopupWindowController] = []
    @ObservationIgnored private let network = NetworkMonitor()
    @ObservationIgnored private var lastRequestedURL: URL?
    @ObservationIgnored private var recentCrashes: [Date] = []

    init(settings: AppSettings, profiles: ProfileStore) {
        self.settings = settings
        self.profiles = profiles
        self.downloads = DownloadManager(settings: settings)
        self.webView = Self.makeWebView(dataStore: profiles.dataStore(for: profiles.currentID), zoom: settings.pageZoom)
        self.delegate = WebViewDelegate(model: self)
        attach(webView)

        downloads.onEvent = { [weak self] event in self?.handleDownload(event) }
        network.onChange = { [weak self] connected in self?.networkChanged(connected) }
        network.start()

        observeChanges { [weak self] in
            guard let self else { return }
            let zoom = self.settings.pageZoom
            if self.webView.pageZoom != zoom { self.webView.pageZoom = zoom }
        }

        loadHome()
    }

    // MARK: - Web view setup

    private static func makeWebView(dataStore: WKWebsiteDataStore, zoom: Double) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        // Present as Safari: some sign-in providers refuse embedded browsers by user agent.
        configuration.applicationNameForUserAgent = userAgentSuffix
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = true
        webView.pageZoom = zoom
        #if DEBUG
        webView.isInspectable = true
        #else
        webView.isInspectable = UserDefaults.standard.bool(forKey: "WebInspectorEnabled")
        #endif
        return webView
    }

    private static let userAgentSuffix: String = {
        let safari = Bundle(url: URL(filePath: "/Applications/Safari.app"))?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let version = safari.map { $0.split(separator: ".").prefix(2).joined(separator: ".") } ?? "18.0"
        return "Version/\(version) Safari/605.1.15"
    }()

    /// A configuration for windows the app opens itself (in-app browser), sharing the account's cookies.
    func makeAuxiliaryConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = webView.configuration.websiteDataStore
        configuration.applicationNameForUserAgent = Self.userAgentSuffix
        configuration.preferences.isElementFullscreenEnabled = true
        return configuration
    }

    private func attach(_ webView: WKWebView) {
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        // WKWebView posts KVO on the main thread.
        observations = [
            webView.observe(\.estimatedProgress, options: [.initial]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.progress = webView.estimatedProgress }
            },
            webView.observe(\.isLoading, options: [.initial]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.isLoading = webView.isLoading }
            },
            webView.observe(\.title, options: [.initial]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.pageTitle = Self.displayTitle(webView.title) }
            },
            webView.observe(\.url, options: [.initial]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.currentURL = webView.url }
            },
            webView.observe(\.canGoBack, options: [.initial]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.canGoBack = webView.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.canGoForward = webView.canGoForward }
            },
            webView.observe(\.underPageBackgroundColor, options: [.initial]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.pageBackgroundColor = webView.underPageBackgroundColor }
            },
        ]
    }

    private static func displayTitle(_ raw: String?) -> String {
        var title = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [" - DeepSeek", " | DeepSeek", " — DeepSeek"] where title.hasSuffix(suffix) {
            title.removeLast(suffix.count)
        }
        return title.isEmpty || title.hasPrefix("DeepSeek") ? "DeepSeek" : title
    }

    // MARK: - Navigation commands

    var isShowingApp: Bool {
        currentURL.map(LinkPolicy.isAppURL) ?? false
    }

    func loadHome() {
        load(LinkPolicy.homeURL)
    }

    func load(_ url: URL) {
        lastRequestedURL = url
        webView.load(URLRequest(url: url))
    }

    func reload() {
        if case .failed = phase {
            retry()
        } else {
            webView.reload()
        }
    }

    func reloadIgnoringCache() {
        webView.reloadFromOrigin()
    }

    func retry() {
        phase = .loading
        if hasContent, let url = webView.url, LinkPolicy.isWebURL(url) {
            webView.reload()
        } else {
            load(lastRequestedURL ?? LinkPolicy.homeURL)
        }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    /// Uses the page's own "new chat" button so the single-page app doesn't reload;
    /// falls back to loading the home page.
    func startNewChat() {
        guard hasContent, isShowingApp, currentURL?.path.hasPrefix("/sign_in") == false else {
            loadHome()
            return
        }
        webView.evaluateJavaScript(WebScripts.startNewChat) { [weak self] result, _ in
            guard let self else { return }
            if (result as? Bool) == true {
                self.focusInput()
            } else {
                self.loadHome()
            }
        }
    }

    func focusInput() {
        guard hasContent else { return }
        webView.window?.makeFirstResponder(webView)
        webView.evaluateJavaScript(WebScripts.focusChatInput, completionHandler: nil)
    }

    func zoomIn() { settings.setPageZoom(settings.pageZoom + 0.1) }
    func zoomOut() { settings.setPageZoom(settings.pageZoom - 0.1) }
    func resetZoom() { settings.setPageZoom(1.0) }

    func openCurrentPageInBrowser() {
        NSWorkspace.shared.open(currentURL ?? LinkPolicy.homeURL)
    }

    func showToast(symbol: String, message: String, revealURL: URL? = nil) {
        toast = Toast(symbol: symbol, message: message, revealURL: revealURL)
    }

    // MARK: - Website data and accounts

    func clearCache() async {
        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeFetchCache, WKWebsiteDataTypeOfflineWebApplicationCache,
        ]
        await webView.configuration.websiteDataStore.removeData(ofTypes: types, modifiedSince: .distantPast)
        webView.reloadFromOrigin()
        showToast(symbol: "checkmark.circle", message: L("Cache cleared. You're still signed in."))
    }

    /// Removes every cookie and storage item of the current account, which signs it out.
    func signOutAndClearData() async {
        await webView.configuration.websiteDataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast
        )
        hasContent = false
        phase = .loading
        loadHome()
        showToast(symbol: "person.crop.circle.badge.xmark", message: L("Signed out of “\(profiles.current.displayName)” and cleared its website data"))
    }

    func switchProfile(to id: UUID) {
        guard id != profiles.currentID else { return }
        profiles.select(id)
        rebuildWebView()
        showToast(symbol: "person.crop.circle", message: L("Switched to “\(profiles.current.displayName)”"))
    }

    func addProfileAndSwitch() {
        let profile = profiles.add()
        switchProfile(to: profile.id)
    }

    private func rebuildWebView() {
        let old = webView
        old.stopLoading()
        old.navigationDelegate = nil
        old.uiDelegate = nil
        observations.removeAll()
        for popup in popups { popup.close() }

        webView = Self.makeWebView(dataStore: profiles.dataStore(for: profiles.currentID), zoom: settings.pageZoom)
        generation += 1
        hasContent = false
        phase = .loading
        pageBackgroundColor = nil
        recentCrashes.removeAll()
        attach(webView)
        loadHome()
    }

    // MARK: - Navigation policy

    func policy(for action: WKNavigationAction) -> WKNavigationActionPolicy {
        if action.shouldPerformDownload { return .download }
        guard let url = action.request.url else { return .allow }

        if !LinkPolicy.isWebURL(url) {
            if LinkPolicy.isInlineURL(url) { return .allow }
            NSWorkspace.shared.open(url) // mailto:, tel:, weixin:// …
            return .cancel
        }

        // Sub-frames (captchas, embeds) load freely; `targetFrame == nil` is a new-window
        // request that `makePopup` handles next.
        guard let frame = action.targetFrame, frame.isMainFrame else { return .allow }
        if action.navigationType == .backForward || action.navigationType == .reload { return .allow }

        if action.modifierFlags.contains(.command) {
            openExternal(url)
            return .cancel
        }
        if LinkPolicy.isAppURL(url) { return .allow }

        if action.navigationType == .linkActivated {
            if LinkPolicy.isSignInURL(url) { return .allow }
        } else if LinkPolicy.isTrustedRedirect(url) {
            return .allow // sign-in redirects and other script-driven hops
        }
        openExternal(url)
        return .cancel
    }

    static func policy(for response: WKNavigationResponse) -> WKNavigationResponsePolicy {
        if let http = response.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().hasPrefix("attachment") {
            return .download
        }
        return response.canShowMIMEType ? .allow : .download
    }

    /// `window.open` / `target="_blank"`.
    func makePopup(
        configuration: WKWebViewConfiguration, action: WKNavigationAction, features: WKWindowFeatures
    ) -> WKWebView? {
        let url = action.request.url
        if let url, LinkPolicy.isWebURL(url) {
            if LinkPolicy.isSignInURL(url) {
                return openPopup(configuration: configuration, features: features, mode: .signIn).webView
            }
            if LinkPolicy.isAppURL(url), !action.modifierFlags.contains(.command) {
                webView.load(action.request)
            } else {
                openExternal(url)
            }
            return nil
        }
        if let url, !LinkPolicy.isInlineURL(url) {
            NSWorkspace.shared.open(url)
            return nil
        }
        // A blank window that the opener will navigate later (common for OAuth).
        return openPopup(configuration: configuration, features: features, mode: .undecided).webView
    }

    func openExternal(_ url: URL) {
        if settings.openExternalLinksInBrowser {
            NSWorkspace.shared.open(url)
        } else {
            let popup = openPopup(configuration: makeAuxiliaryConfiguration(), features: nil, mode: .browser)
            popup.webView.load(URLRequest(url: url))
        }
    }

    @discardableResult
    private func openPopup(
        configuration: WKWebViewConfiguration, features: WKWindowFeatures?, mode: PopupWindowController.Mode
    ) -> PopupWindowController {
        let popup = PopupWindowController(
            configuration: configuration, features: features, mode: mode, model: self, parent: webView.window
        )
        popups.append(popup)
        popup.showWindow(nil)
        return popup
    }

    func loadInMainWindow(_ request: URLRequest) {
        webView.load(request)
        webView.window?.makeKeyAndOrderFront(nil)
    }

    func popupDidClose(_ popup: PopupWindowController) {
        popups.removeAll { $0 === popup }
    }

    /// A sign-in popup ended on a DeepSeek page instead of closing itself.
    func signInPopupReturnedToApp() {
        webView.reload()
        webView.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Navigation events

    func navigationStarted() {
        if let url = webView.url, LinkPolicy.isWebURL(url) { lastRequestedURL = url }
        if case .failed = phase { phase = .loading }
    }

    func navigationFinished() {
        if !hasContent {
            log.info("First page load finished: \(self.webView.url?.path ?? "-", privacy: .public)")
        }
        hasContent = true
        phase = .ready
    }

    func navigationFailed(_ error: Error, provisional: Bool) {
        // A failure after the page committed leaves usable content on screen.
        guard provisional || !hasContent else { return }
        guard let pageError = Self.pageError(for: error, offline: isOffline) else { return }
        phase = .failed(pageError)
    }

    func webContentProcessTerminated() {
        let now = Date()
        recentCrashes = recentCrashes.filter { now.timeIntervalSince($0) < 60 } + [now]
        if recentCrashes.count <= 2 {
            webView.reload()
        } else {
            phase = .failed(PageError(kind: .crashed))
        }
    }

    private static func pageError(for error: Error, offline: Bool) -> PageError? {
        let error = error as NSError
        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled { return nil }
        // 102: frame load interrupted (e.g. the response became a download). 204: handled by a plug-in.
        if error.domain == "WebKitErrorDomain", error.code == 102 || error.code == 204 { return nil }

        if offline { return PageError(kind: .offline) }
        guard error.domain == NSURLErrorDomain else {
            return PageError(kind: .failed, detail: error.localizedDescription)
        }
        switch error.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed,
             NSURLErrorInternationalRoamingOff:
            return PageError(kind: .offline)
        case NSURLErrorTimedOut:
            return PageError(kind: .timedOut)
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed, NSURLErrorCannotConnectToHost:
            return PageError(kind: .cannotConnect)
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected:
            return PageError(kind: .insecure, detail: error.localizedDescription)
        default:
            return PageError(kind: .failed, detail: error.localizedDescription)
        }
    }

    // MARK: - Connectivity and downloads

    private func networkChanged(_ connected: Bool) {
        isOffline = !connected
        guard connected, case .failed = phase else { return }
        Task { [weak self] in
            // Let DNS and VPNs settle before retrying.
            try? await Task.sleep(for: .seconds(1))
            guard let self, case .failed = self.phase else { return }
            self.retry()
        }
    }

    private func handleDownload(_ event: DownloadManager.Event) {
        switch event {
        case .finished(let url):
            showToast(symbol: "arrow.down.circle", message: L("Downloaded “\(url.lastPathComponent)”"), revealURL: url)
        case .failed(let filename, let message):
            showToast(symbol: "exclamationmark.triangle", message: L("Couldn't download “\(filename)”: \(message)"))
        }
    }
}
