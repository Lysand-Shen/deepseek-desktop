import SwiftUI
import WebKit

/// Everything below the toolbar: the web view plus native loading, error, offline and toast layers.
struct MainContentView: View {
    let model: WebViewModel

    private var failure: WebViewModel.PageError? {
        if case .failed(let error) = model.phase { error } else { nil }
    }

    var body: some View {
        let failure = failure
        let showsWebView = model.hasContent && failure == nil

        ZStack {
            WebViewContainer(webView: model.webView)
                .id(model.generation)
                .opacity(showsWebView ? 1 : 0)

            if let failure {
                ErrorStateView(error: failure, isOffline: model.isOffline, retry: model.retry)
                    .transition(.opacity)
            } else if !model.hasContent {
                LaunchPlaceholder()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: showsWebView)
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                LoadingBar(progress: model.progress, isVisible: model.isLoading && failure == nil)
                if model.isOffline, showsWebView {
                    OfflineBanner()
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: model.isOffline)
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast) { model.toast = nil }
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: model.toast)
    }
}

struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

private struct LoadingBar: View {
    let progress: Double
    let isVisible: Bool

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: proxy.size.width * max(0.06, min(progress, 1)))
                .animation(.easeOut(duration: 0.25), value: progress)
        }
        .frame(height: 2)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeOut(duration: isVisible ? 0.1 : 0.4), value: isVisible)
        .allowsHitTesting(false)
    }
}

private struct LaunchPlaceholder: View {
    @State private var showsSpinner = false

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)
            ProgressView()
                .controlSize(.small)
                .opacity(showsSpinner ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // Only show a spinner if loading is actually slow.
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation { showsSpinner = true }
        }
    }
}

private struct ErrorStateView: View {
    let error: WebViewModel.PageError
    let isOffline: Bool
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: error.symbol)
                .font(.system(size: 46, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text(error.title)
                .font(.title2.weight(.semibold))
            Text(error.message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button(L("Try Again"), action: retry)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)
            if isOffline {
                Label(L("Waiting for the network…"), systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OfflineBanner: View {
    var body: some View {
        Label(L("You're offline. DeepSeek reconnects automatically."), systemImage: "wifi.slash")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}

private struct ToastView: View {
    let toast: WebViewModel.Toast
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .foregroundStyle(.secondary)
            Text(toast.message)
                .lineLimit(2)
            if let url = toast.revealURL {
                Button(L("Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    dismiss()
                }
                .buttonStyle(.link)
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
        .padding(.horizontal, 24)
        .task(id: toast.id) {
            try? await Task.sleep(for: .seconds(toast.revealURL == nil ? 3 : 6))
            dismiss()
        }
    }
}
