import AppKit
import WebKit

/// Native panels for the page's `alert` / `confirm` / `prompt` and `<input type="file">`.
/// Without these WKWebView silently drops the requests on macOS.
@MainActor
enum WebDialogs {
    static func alert(message: String, frame: WKFrameInfo, in window: NSWindow?, completion: @escaping @MainActor () -> Void) {
        let alert = makeAlert(message: message, frame: frame)
        alert.addButton(withTitle: "好")
        present(alert, in: window) { _ in completion() }
    }

    static func confirm(message: String, frame: WKFrameInfo, in window: NSWindow?, completion: @escaping @MainActor (Bool) -> Void) {
        let alert = makeAlert(message: message, frame: frame)
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "取消")
        present(alert, in: window) { completion($0 == .alertFirstButtonReturn) }
    }

    static func prompt(
        _ prompt: String, defaultText: String?, frame: WKFrameInfo, in window: NSWindow?,
        completion: @escaping @MainActor (String?) -> Void
    ) {
        let alert = makeAlert(message: prompt, frame: frame)
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        present(alert, in: window) { completion($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    static func openPanel(parameters: WKOpenPanelParameters, in window: NSWindow?, completion: @escaping @MainActor ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.message = "选择要上传到 DeepSeek 的文件"
        let finish: @MainActor (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .OK ? panel.urls : nil)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    private static func makeAlert(message: String, frame: WKFrameInfo) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host.isEmpty ? "DeepSeek" : frame.securityOrigin.host
        alert.informativeText = message
        return alert
    }

    private static func present(_ alert: NSAlert, in window: NSWindow?, completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void) {
        if let window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }
}
