//
//  BrowserView.swift
//  APIGhost
//
//  NSViewRepresentable wrapper for WKWebView, enabling SwiftUI integration.
//

import SwiftUI
import WebKit
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "BrowserView")

struct BrowserView: NSViewRepresentable {
    @Bindable var viewModel: BrowserViewModel

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // Use non-persistent data store to avoid caching issues
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        // Load and inject the API interceptor script
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

        // Register message handler for receiving captured traffic
        // Store the handler in coordinator to prevent deallocation
        let messageHandler = JSMessageHandler()
        context.coordinator.messageHandler = messageHandler
        configuration.userContentController.add(messageHandler, name: JSMessageHandler.handlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Use standard Safari user agent to avoid bot detection
        // Must look like real Safari - no custom identifiers
        // Standard Safari user agent for stealth
        webView.customUserAgent = [
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
            "AppleWebKit/605.1.15 (KHTML, like Gecko)",
            "Version/17.2 Safari/605.1.15"
        ].joined(separator: " ")

        viewModel.webView = webView
        context.coordinator.observeWebView(webView)

        // Load initial URL
        if let url = viewModel.validatedURL {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Handle URL changes if needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // Coordinator is defined in BrowserViewCoordinator.swift
}
