import WebKit

/// Shared persistent data store keeps cookies/localStorage alive across tabs and relaunches (3.3.1).
@MainActor
@Observable
final class BrowserTabManager {
    private(set) var tabs: [BrowserTab]
    var activeTabId: String

    private let dataStore: WKWebsiteDataStore

    convenience init() {
        self.init(dataStore: .default())
    }

    init(dataStore: WKWebsiteDataStore) {
        self.dataStore = dataStore
        let initial = BrowserTab(dataStore: dataStore)
        self.tabs = [initial]
        self.activeTabId = initial.id
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
