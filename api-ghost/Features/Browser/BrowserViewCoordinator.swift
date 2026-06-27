//
//  BrowserViewCoordinator.swift
//  APIGhost
//
//  WKWebView coordinator handling navigation, popups, and JavaScript dialogs.
//

import WebKit
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "BrowserViewCoordinator")

// MARK: - BrowserView Coordinator

extension BrowserView {
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
        var viewModel: BrowserViewModel
        private var observations: [NSKeyValueObservation] = []

        /// Maps popup windows to their webviews for safe cleanup
        private var popupWebViews: [ObjectIdentifier: WKWebView] = [:]

        /// Holds references to popup windows to prevent deallocation
        private var popupWindows: Set<NSWindow> = []

        /// Tracks windows being cleaned up to prevent double cleanup
        private var windowsBeingCleaned: Set<ObjectIdentifier> = []

        /// Holds a reference to the message handler to prevent deallocation
        var messageHandler: JSMessageHandler?

        init(viewModel: BrowserViewModel) {
            self.viewModel = viewModel
        }

        deinit {
            cleanupAllPopups()
        }

        // MARK: - Popup Cleanup

        private func cleanupPopupWebView(_ webView: WKWebView, deferred: Bool = false) {
            let cleanup = { [weak webView] in
                guard let webView = webView else { return }
                webView.stopLoading()
                webView.loadHTMLString("", baseURL: nil)
                webView.navigationDelegate = nil
                webView.uiDelegate = nil
                logger.info("Popup webview cleanup completed")
            }

            if deferred {
                DispatchQueue.main.async(execute: cleanup)
            } else {
                cleanup()
            }
        }

        private func cleanupAllPopups() {
            for (_, webView) in popupWebViews {
                cleanupPopupWebView(webView, deferred: false)
            }
            popupWebViews.removeAll()
            windowsBeingCleaned.removeAll()

            for window in popupWindows {
                window.delegate = nil
                window.orderOut(nil)
            }
            popupWindows.removeAll()
        }

        private func removePopupWindow(_ window: NSWindow, triggeredByWebKit: Bool) {
            let windowID = ObjectIdentifier(window)

            guard !windowsBeingCleaned.contains(windowID) else {
                logger.debug("Skipping duplicate cleanup for window")
                return
            }
            windowsBeingCleaned.insert(windowID)

            if let webView = popupWebViews[windowID] {
                cleanupPopupWebView(webView, deferred: triggeredByWebKit)
                popupWebViews.removeValue(forKey: windowID)
            }

            window.delegate = nil
            popupWindows.remove(window)

            DispatchQueue.main.async { [weak self] in
                self?.windowsBeingCleaned.remove(windowID)
            }
        }

        // MARK: - NSWindowDelegate

        func windowWillClose(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            logger.info("windowWillClose called")
            removePopupWindow(window, triggeredByWebKit: false)
        }

        // MARK: - WKUIDelegate (Popup Handling)

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard let url = navigationAction.request.url else {
                return nil
            }

            logger.info("Popup requested for: \(url.absoluteString)")
            let popupWebView = WKWebView(frame: .zero, configuration: configuration)
            popupWebView.navigationDelegate = self
            popupWebView.uiDelegate = self

            let popupWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            popupWindow.title = "Sign In"
            popupWindow.contentView = popupWebView
            popupWindow.center()
            popupWindow.animationBehavior = .none
            popupWindow.isReleasedWhenClosed = false
            popupWindow.delegate = self

            let windowID = ObjectIdentifier(popupWindow)
            popupWebViews[windowID] = popupWebView
            popupWindows.insert(popupWindow)
            popupWindow.makeKeyAndOrderFront(nil)

            return popupWebView
        }

        func webViewDidClose(_ webView: WKWebView) {
            logger.info("webViewDidClose called - deferring window close")
            var windowToClose: NSWindow?
            var foundWindowID: ObjectIdentifier?

            for (windowID, storedWebView) in popupWebViews
            where ObjectIdentifier(storedWebView) == ObjectIdentifier(webView) {
                for window in popupWindows where ObjectIdentifier(window) == windowID {
                    windowToClose = window
                    foundWindowID = windowID
                    break
                }
                break
            }

            guard let window = windowToClose, let windowID = foundWindowID else {
                logger.info("webViewDidClose: window not found in tracking")
                return
            }

            guard !windowsBeingCleaned.contains(windowID) else {
                logger.info("webViewDidClose: window already being cleaned up")
                return
            }

            DispatchQueue.main.async { [weak self, weak window] in
                guard let self = self, let window = window else { return }
                logger.info("Executing deferred window close")
                self.removePopupWindow(window, triggeredByWebKit: true)
                window.close()
            }
        }
    }
}

// MARK: - JavaScript Dialog Handling

extension BrowserView.Coordinator {
    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        completionHandler(response == .alertFirstButtonReturn)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = defaultText ?? ""
        alert.accessoryView = textField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            completionHandler(textField.stringValue)
        } else {
            completionHandler(nil)
        }
    }
}

// MARK: - Navigation Observation

extension BrowserView.Coordinator {
    func observeWebView(_ webView: WKWebView) {
        observations = [
            webView.observe(\.canGoBack) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.viewModel.canGoBack = webView.canGoBack
                }
            },
            webView.observe(\.canGoForward) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.viewModel.canGoForward = webView.canGoForward
                }
            },
            webView.observe(\.isLoading) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.viewModel.isLoading = webView.isLoading
                }
            },
            webView.observe(\.title) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.viewModel.pageTitle = webView.title ?? ""
                }
            }
        ]
    }
}

// MARK: - WKNavigationDelegate

extension BrowserView.Coordinator {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.viewModel.isLoading = true
            self.viewModel.updateNavigationState()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.viewModel.isLoading = false
            self.viewModel.updateNavigationState()
            if let url = webView.url {
                self.viewModel.urlString = url.absoluteString
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        let nsError = error as NSError
        logger.error("Navigation failed: \(nsError.domain) code=\(nsError.code) - \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.viewModel.isLoading = false
            self.viewModel.updateNavigationState()
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled {
            logger.debug("Navigation cancelled (code -999)")
        } else {
            let desc = error.localizedDescription
            logger.error("Provisional nav failed: \(nsError.domain) code=\(nsError.code) - \(desc)")
        }

        DispatchQueue.main.async {
            self.viewModel.isLoading = false
            self.viewModel.updateNavigationState()
        }
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let protectionSpace = challenge.protectionSpace
        let authMethod = protectionSpace.authenticationMethod

        if authMethod == NSURLAuthenticationMethodServerTrust {
            if protectionSpace.host == "127.0.0.1" || protectionSpace.host == "localhost" {
                if let serverTrust = protectionSpace.serverTrust {
                    completionHandler(.useCredential, URLCredential(trust: serverTrust))
                    return
                }
            }

            if let serverTrust = protectionSpace.serverTrust {
                var error: CFError?
                let isTrusted = SecTrustEvaluateWithError(serverTrust, &error)

                if isTrusted {
                    completionHandler(.useCredential, URLCredential(trust: serverTrust))
                    return
                }
            }
        }

        completionHandler(.performDefaultHandling, nil)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url {
            let navType = navigationAction.navigationType.rawValue
            let targetFrame = navigationAction.targetFrame?.isMainFrame.description ?? "nil"
            logger.debug("Navigation action: \(navType) to \(url.absoluteString), targetFrame: \(targetFrame)")
        }

        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            logger.info("Loading target=_blank URL in current view: \(url.absoluteString)")
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if let httpResponse = navigationResponse.response as? HTTPURLResponse {
            let urlString = httpResponse.url?.absoluteString ?? "unknown"
            logger.debug("Navigation response: \(httpResponse.statusCode) for \(urlString)")
        }

        decisionHandler(.allow)
    }
}
