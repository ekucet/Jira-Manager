import SwiftUI
import WebKit

/// Owns a WKWebView so SwiftUI can drive find-in-page and read the selection.
@MainActor
final class WebController: NSObject, ObservableObject {
    let webView: WKWebView

    override init() {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init()
        webView.setValue(false, forKey: "drawsBackground") // blend with window
    }

    func loadHTML(_ fragment: String, baseURL: URL?) {
        webView.loadHTMLString(Self.wrap(fragment), baseURL: baseURL)
    }

    /// Find-in-page. Highlights and scrolls to the next/previous match.
    func find(_ text: String, forward: Bool) {
        guard !text.isEmpty else { return }
        let cfg = WKFindConfiguration()
        cfg.backwards = !forward
        cfg.caseSensitive = false
        cfg.wraps = true
        webView.find(text, configuration: cfg, completionHandler: { _ in })
    }

    /// The current selection, or (if nothing is selected) the whole document text.
    func selectionOrAllText() async -> String {
        let sel = (try? await webView.evaluateJavaScript("window.getSelection().toString()")) as? String ?? ""
        if !sel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return sel }
        let all = (try? await webView.evaluateJavaScript("document.body.innerText")) as? String ?? ""
        return all
    }

    /// Wraps a Confluence body fragment with CSS approximating Confluence's look.
    private static func wrap(_ fragment: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: light dark; }
          body {
            font-family: -apple-system, system-ui, "Helvetica Neue", sans-serif;
            font-size: 14px; line-height: 1.6; margin: 0; padding: 16px 20px;
            color: #172b4d; word-wrap: break-word;
          }
          @media (prefers-color-scheme: dark) { body { color: #c7d1db; } }
          h1,h2,h3,h4 { color: inherit; line-height: 1.25; margin: 1.2em 0 .5em; font-weight: 600; }
          h1 { font-size: 1.7em; } h2 { font-size: 1.4em; } h3 { font-size: 1.2em; }
          p { margin: .6em 0; }
          a { color: #0c66e4; text-decoration: none; }
          a:hover { text-decoration: underline; }
          img { max-width: 100%; height: auto; }
          ul, ol { padding-left: 1.6em; }
          hr { border: none; border-top: 1px solid rgba(128,128,128,.3); margin: 1.2em 0; }

          /* Tables (Confluence uses confluenceTable / Th / Td) */
          table, table.confluenceTable { border-collapse: collapse; margin: 1em 0; max-width: 100%;
            display: block; overflow-x: auto; }
          th, td, .confluenceTh, .confluenceTd { border: 1px solid #dfe1e6; padding: 8px 10px; text-align: left; vertical-align: top; }
          th, .confluenceTh { background: rgba(128,128,128,.12); font-weight: 600; }

          /* Code */
          code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: .9em;
            background: rgba(128,128,128,.15); padding: 1px 4px; border-radius: 3px; }
          pre, .code, .codeContent, .preformatted { font-family: ui-monospace, Menlo, monospace;
            background: rgba(128,128,128,.12); padding: 12px; border-radius: 6px; overflow-x: auto; }
          pre code { background: none; padding: 0; }

          /* Panels / info-note-warning macros */
          .panel, .confluence-information-macro {
            border: 1px solid #dfe1e6; border-radius: 6px; padding: 10px 14px; margin: 1em 0;
            background: rgba(128,128,128,.06); }
          .panelHeader, .title { font-weight: 600; margin-bottom: 4px; }
          .confluence-information-macro-information { border-left: 4px solid #0c66e4; }
          .confluence-information-macro-note      { border-left: 4px solid #8270db; }
          .confluence-information-macro-warning    { border-left: 4px solid #e56910; }
          .confluence-information-macro-tip,
          .confluence-information-macro-success    { border-left: 4px solid #22a06b; }
          .aui-message { border-radius: 6px; padding: 10px 14px; margin: 1em 0; background: rgba(128,128,128,.08); }

          /* Status lozenges */
          .aui-lozenge { display: inline-block; padding: 1px 6px; border-radius: 3px; font-size: .75em;
            font-weight: 700; text-transform: uppercase; background: #dfe1e6; color: #42526e; }
          .aui-lozenge-success { background: #e3fcef; color: #006644; }
          .aui-lozenge-error   { background: #ffebe6; color: #bf2600; }
          .aui-lozenge-current { background: #deebff; color: #0747a6; }

          blockquote { border-left: 3px solid rgba(128,128,128,.4); margin: 1em 0; padding: .2em 1em; color: inherit; opacity: .9; }
          ::selection { background: #b3d4ff; }
        </style></head>
        <body>\(fragment)</body></html>
        """
    }
}
