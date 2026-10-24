import AppKit
import WebKit

/// Saves `WKDownload`s to ~/Downloads (or wherever the user picks) and reports the outcome.
@MainActor
final class DownloadManager: NSObject, WKDownloadDelegate {
    enum Event {
        case finished(URL)
        case failed(filename: String, message: String)
    }

    var onEvent: ((Event) -> Void)?

    private let settings: AppSettings
    private var destinations: [ObjectIdentifier: URL] = [:]

    init(settings: AppSettings) {
        self.settings = settings
    }

    func attach(_ download: WKDownload) {
        download.delegate = self
    }

    static var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
    }

    // MARK: WKDownloadDelegate

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor (URL?) -> Void
    ) {
        let filename = Self.sanitizedFilename(suggestedFilename)
        let key = ObjectIdentifier(download)

        guard settings.askDownloadLocation else {
            let url = Self.uniqueURL(for: filename, in: Self.downloadsDirectory)
            destinations[key] = url
            completionHandler(url)
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.directoryURL = Self.downloadsDirectory
        panel.canCreateDirectories = true
        let finish: @MainActor (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else {
                completionHandler(nil)
                return
            }
            // The panel already asked about replacing; WKDownload refuses to overwrite.
            try? FileManager.default.removeItem(at: url)
            self?.destinations[key] = url
            completionHandler(url)
        }
        if let window = download.webView?.window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = destinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        // Makes the Downloads stack in the Dock bounce, like Safari.
        DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: url.path)
        onEvent?(.finished(url))
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let url = destinations.removeValue(forKey: ObjectIdentifier(download))
        let nsError = error as NSError
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
        onEvent?(.failed(filename: url?.lastPathComponent ?? L("file"), message: error.localizedDescription))
    }

    // MARK: Helpers

    private static func sanitizedFilename(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned.hasPrefix(".") ? L("Download") + cleaned : cleaned
    }

    /// `name.ext`, then `name 2.ext`, `name 3.ext`… like Finder.
    private static func uniqueURL(for filename: String, in directory: URL) -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appending(path: filename)
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var index = 2
        while fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = directory.appending(path: name)
            index += 1
        }
        return candidate
    }
}
