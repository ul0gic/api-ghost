import SwiftUI
import WebKit

/// Hosts a tab's pre-created WKWebView; webviews are owned by BrowserTab so state survives tab switches.
struct BrowserWebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(webView, to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if webView.superview !== container {
            attach(webView, to: container)
        }
    }

    private func attach(_ webView: WKWebView, to container: NSView) {
        webView.removeFromSuperview()
        container.subviews.forEach { $0.removeFromSuperview() }

        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
    }
}
