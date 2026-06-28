import WebKit
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "BrowserTab")

@MainActor
@Observable
final class BrowserTab: Identifiable {
    let id: String
    let viewModel: BrowserViewModel
    let webView: WKWebView

    private let coordinator: BrowserCoordinator
    private let messageHandler: JSMessageHandler

    init(
        id: String = UUID().uuidString,
        url: String = BrowserTab.defaultURL,
        dataStore: WKWebsiteDataStore
    ) {
        self.id = id

        let model = BrowserViewModel()
        model.urlString = url
        self.viewModel = model

        let handler = JSMessageHandler()
        handler.sourceTabId = id
        self.messageHandler = handler

        let webView = BrowserTab.makeWebView(dataStore: dataStore, messageHandler: handler)
        self.webView = webView

        let coordinator = BrowserCoordinator(viewModel: model)
        self.coordinator = coordinator

        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = BrowserTab.safariUserAgent

        model.webView = webView
        coordinator.observeWebView(webView)

        if let url = model.validatedURL {
            webView.load(URLRequest(url: url))
        }
    }

    var displayTitle: String {
        if !viewModel.pageTitle.isEmpty {
            return viewModel.pageTitle
        }
        if let host = URL(string: viewModel.urlString)?.host {
            return host
        }
        return "New Tab"
    }

    func teardown() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: JSMessageHandler.handlerName)
        webView.removeFromSuperview()
    }
}

// MARK: - WebView Construction

extension BrowserTab {
    nonisolated static let defaultURL = "https://www.google.com"

    static let safariUserAgent = [
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        "AppleWebKit/605.1.15 (KHTML, like Gecko)",
        "Version/17.2 Safari/605.1.15"
    ].joined(separator: " ")

    static func makeWebView(
        dataStore: WKWebsiteDataStore,
        messageHandler: JSMessageHandler
    ) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore

        // Proxy mode is the sole capturer for its traffic; injecting the JS interceptor too would double-capture.
        if AppState.shared.interceptMode == .jsInjection {
            if let scriptURL = Bundle.main.url(forResource: "APIGhostInterceptor", withExtension: "js"),
               let scriptSource = try? String(contentsOf: scriptURL, encoding: .utf8) {
                let script = WKUserScript(
                    source: scriptSource,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: false
                )
                configuration.userContentController.addUserScript(script)
            } else {
                logger.error("WARNING: Could not load APIGhostInterceptor.js")
            }

            configuration.userContentController.add(messageHandler, name: JSMessageHandler.handlerName)
        }

        return WKWebView(frame: .zero, configuration: configuration)
    }
}
