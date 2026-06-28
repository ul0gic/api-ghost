import Network
import WebKit
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "BrowserTabManager")

/// Shared persistent data store keeps cookies/localStorage alive across tabs and relaunches (3.3.1).
@MainActor
@Observable
final class BrowserTabManager {
    private(set) var tabs: [BrowserTab]
    var activeTabId: String

    /// Set when network-proxy capture is force-disabled by anti-MITM breakage; drives the fallback banner.
    var proxyFallbackNotice: String?

    private let dataStore: WKWebsiteDataStore
    private let proxyController = ProxyController()
    private var appliedMode: InterceptMode?
    @ObservationIgnored private var fallbackObserver: (any NSObjectProtocol)?

    convenience init() {
        self.init(dataStore: .default())
    }

    init(dataStore: WKWebsiteDataStore) {
        self.dataStore = dataStore
        let initial = BrowserTab(dataStore: dataStore)
        self.tabs = [initial]
        self.activeTabId = initial.id

        fallbackObserver = NotificationCenter.default.addObserver(
            forName: ProxyFallback.mitmHandshakeFailed,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let host = note.userInfo?[ProxyFallback.hostKey] as? String
            MainActor.assumeIsolated { self?.handleProxyFallback(host: host) }
        }
    }

    deinit {
        if let fallbackObserver {
            NotificationCenter.default.removeObserver(fallbackObserver)
        }
    }

    var activeTab: BrowserTab? {
        tabs.first { $0.id == activeTabId }
    }

    @discardableResult
    func newTab(url: String = BrowserTab.defaultURL) -> BrowserTab {
        let tab = BrowserTab(url: url, dataStore: dataStore)
        tabs.append(tab)
        activeTabId = tab.id
        return tab
    }

    func selectTab(_ id: String) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
    }

    func closeTab(_ id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].teardown()
        tabs.remove(at: index)

        if tabs.isEmpty {
            let replacement = BrowserTab(dataStore: dataStore)
            tabs = [replacement]
            activeTabId = replacement.id
            return
        }

        if activeTabId == id {
            activeTabId = tabs[min(index, tabs.count - 1)].id
        }
    }

    func closeActiveTab() {
        closeTab(activeTabId)
    }
}

// MARK: - Interception Mode

extension BrowserTabManager {
    /// Reconciles proxy lifecycle + WebKit proxy routing to the active `InterceptMode`. Idempotent; safe to call on appear and on mode change.
    func applyInterceptionState() async {
        let mode = AppState.shared.interceptMode
        let needsRebuild: Bool

        switch mode {
        case .networkProxy:
            needsRebuild = appliedMode != .networkProxy
            do {
                let port = try await proxyController.start()
                if let configuration = Self.proxyConfiguration(port: port) {
                    dataStore.proxyConfigurations = [configuration]
                }
            } catch {
                logger.error("Failed to start proxy: \(error.localizedDescription)")
            }
        case .jsInjection:
            needsRebuild = appliedMode == .networkProxy
            await proxyController.stop()
            dataStore.proxyConfigurations = []
        }

        appliedMode = mode
        if needsRebuild { rebuildTabs() }
    }

    private func rebuildTabs() {
        let urls = tabs.map(\.viewModel.urlString)
        let activeIndex = tabs.firstIndex { $0.id == activeTabId } ?? 0
        for tab in tabs { tab.teardown() }

        let rebuilt = urls.map { BrowserTab(url: $0, dataStore: dataStore) }
        tabs = rebuilt.isEmpty ? [BrowserTab(dataStore: dataStore)] : rebuilt
        activeTabId = tabs[min(activeIndex, tabs.count - 1)].id
    }

    private static func proxyConfiguration(port: Int) -> ProxyConfiguration? {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return nil }
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)
        return ProxyConfiguration(httpCONNECTProxy: endpoint)
    }
}

// MARK: - Anti-MITM Fallback (4.3.1)

extension BrowserTabManager {
    /// Force-disables proxy capture when the MITM leaf is rejected (pinning); the mode flip reloads tabs via
    /// `applyInterceptionState`, and capture continues over JS injection so browsing isn't blocked.
    func handleProxyFallback(host: String?) {
        guard AppState.shared.interceptMode == .networkProxy else { return }
        AppState.shared.interceptMode = .jsInjection
        let target = host.map { "“\($0)”" } ?? "this site"
        proxyFallbackNotice =
            "Couldn't intercept \(target) in Network Proxy mode (likely certificate pinning). "
            + "Switched to JavaScript Injection."
        logger.info("Proxy MITM rejected for \(host ?? "unknown"); fell back to JS injection mode")
    }

    func dismissProxyFallbackNotice() {
        proxyFallbackNotice = nil
    }
}
