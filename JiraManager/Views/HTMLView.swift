import SwiftUI
import WebKit

/// Embeds the WKWebView owned by a WebController. Loading/find/selection are driven via the controller.
struct HTMLView: NSViewRepresentable {
    let controller: WebController

    func makeNSView(context: Context) -> WKWebView { controller.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
