import SwiftUI
import WebKit
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "BrowserView")

struct BrowserView: NSViewRepresentable {
    @Bindable var viewModel: BrowserViewModel

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        if let scriptURL = Bundle.main.url(forResource: "APIGhostInterceptor", withExtension: "js"),
           let scriptSource = try? String(contentsOf: scriptURL, encoding: .utf8) {
            let script = WKUserScript(
                source: scriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            configuration.userContentController.addUserScript(script)
            logger.info("Interceptor script injected")
        } else {
            logger.error("WARNING: Could not load APIGhostInterceptor.js")
        }

        // Coordinator retains the handler to prevent deallocation.
        let messageHandler = JSMessageHandler()
        context.coordinator.messageHandler = messageHandler
        configuration.userContentController.add(messageHandler, name: JSMessageHandler.handlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Standard Safari user agent to avoid bot detection
        webView.customUserAgent = [
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
            "AppleWebKit/605.1.15 (KHTML, like Gecko)",
            "Version/17.2 Safari/605.1.15"
        ].joined(separator: " ")

        viewModel.webView = webView
        context.coordinator.observeWebView(webView)

        if let url = viewModel.validatedURL {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
}
