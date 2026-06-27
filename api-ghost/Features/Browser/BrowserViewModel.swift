//
//  BrowserViewModel.swift
//  APIGhost
//
//  ViewModel for the embedded browser, managing navigation state and URL handling.
//

import SwiftUI
import WebKit

@Observable
class BrowserViewModel {
    var urlString: String = "https://www.google.com"
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var isLoading: Bool = false
    var pageTitle: String = ""

    weak var webView: WKWebView?

    // URL validation and normalization
    var validatedURL: URL? {
        var urlStr = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add https:// if no scheme present
        if !urlStr.contains("://") {
            urlStr = "https://" + urlStr
        }

        return URL(string: urlStr)
    }

    init() {
        // Proxy startup is now handled at the app level in APIGhostApp.swift
        // to prevent multiple start attempts when SwiftUI recreates views
    }

    func loadURL() {
        guard let url = validatedURL, let webView = webView else { return }
        urlString = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    func goHome() {
        urlString = "https://www.google.com"
        loadURL()
    }

    func updateNavigationState() {
        guard let webView = webView else { return }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        pageTitle = webView.title ?? ""
    }
}
