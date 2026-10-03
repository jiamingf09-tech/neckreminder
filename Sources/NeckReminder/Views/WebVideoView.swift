import AppKit
import SwiftUI
import WebKit
import NeckReminderCore

/// A YouTube demo shown inside NeckReminder, so watching it during a relax session keeps
/// the focus in the app (and doesn't count as "still working").
struct VideoLink: Identifiable, Equatable {
    let title: String
    let url: URL
    var id: String { url.absoluteString }

    static func youtube(_ title: String, query: String) -> VideoLink {
        VideoLink(title: title, url: youtubeSearchURL(query))
    }
}

struct WebVideoView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        let web = WKWebView(frame: .zero, configuration: config)
        // YouTube serves its full desktop site to Safari.
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: url))
        context.coordinator.webView = web
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKUIDelegate {
        weak var webView: WKWebView?

        // Links that want a new window open in the same view.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }
    }
}

struct VideoSheet: View {
    let video: VideoLink
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(video.title, systemImage: "play.rectangle").scaledFont(14, weight: .semibold)
                Spacer()
                Button(tr("完成", "Done")) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
            }
            .padding(12)
            Divider()
            WebVideoView(url: video.url)
        }
        .frame(minWidth: 900, idealWidth: 1000, minHeight: 600, idealHeight: 680)
    }
}
