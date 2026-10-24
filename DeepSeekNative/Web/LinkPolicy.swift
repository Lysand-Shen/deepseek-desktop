import Foundation

/// Decides which URLs belong inside the app and which go to the user's browser.
enum LinkPolicy {
    static let appHost = "chat.deepseek.com"
    static let homeURL = URL(string: "https://chat.deepseek.com/")!

    /// Sign-in pages that must open inside the app so the session cookie lands in our data store.
    private static let signInHosts: Set<String> = [
        "accounts.google.com",
        "appleid.apple.com",
        "idmsa.apple.com",
        "open.weixin.qq.com",
        "graph.qq.com",
        "login.microsoftonline.com",
        "login.live.com",
        "github.com",
    ]

    /// Domains a sign-in or captcha flow may redirect through without a user click.
    private static let trustedDomains: [String] = [
        "deepseek.com",
        "google.com", "youtube.com", "gstatic.com", "googleusercontent.com",
        "apple.com", "icloud.com",
        "qq.com", "wechat.com",
        "microsoftonline.com", "live.com", "microsoft.com",
        "github.com",
        "hcaptcha.com", "recaptcha.net",
    ]

    /// Schemes the web view renders itself and must never hand to another app.
    private static let inlineSchemes: Set<String> = ["about", "blob", "data", "javascript"]

    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    static func isInlineURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return true }
        return inlineSchemes.contains(scheme)
    }

    static func isAppURL(_ url: URL) -> Bool {
        isWebURL(url) && url.host?.lowercased() == appHost
    }

    static func isSignInURL(_ url: URL) -> Bool {
        guard isWebURL(url), let host = url.host?.lowercased() else { return false }
        if host == "github.com" { return url.path.hasPrefix("/login") }
        return signInHosts.contains(host)
    }

    static func isTrustedRedirect(_ url: URL) -> Bool {
        guard isWebURL(url), let host = url.host?.lowercased() else { return false }
        return trustedDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
