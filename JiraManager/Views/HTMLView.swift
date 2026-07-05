import SwiftUI
import WebKit

/// Renders an HTML fragment (e.g. a Confluence page body) in a WKWebView.
struct HTMLView: NSViewRepresentable {
    let html: String
    let baseURL: URL?

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground") // transparent, blends with window
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(Self.wrap(html), baseURL: baseURL)
    }

    /// Wraps a Confluence body fragment in a minimal, readable document.
    private static func wrap(_ fragment: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: light dark; }
          body {
            font: -apple-system-body;
            font-family: -apple-system, system-ui, sans-serif;
            line-height: 1.55; margin: 0; padding: 16px;
            word-wrap: break-word;
          }
          h1,h2,h3 { line-height: 1.25; }
          img { max-width: 100%; height: auto; }
          table { border-collapse: collapse; max-width: 100%; display: block; overflow-x: auto; }
          th,td { border: 1px solid rgba(128,128,128,0.4); padding: 6px 10px; }
          pre, code { font-family: ui-monospace, monospace; }
          pre { background: rgba(128,128,128,0.12); padding: 12px; border-radius: 6px; overflow-x: auto; }
          a { color: #2a7ae2; }
        </style></head>
        <body>\(fragment)</body></html>
        """
    }
}
