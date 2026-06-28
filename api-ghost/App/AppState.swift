import SwiftUI

// MARK: - Navigation Tab Enum

enum NavigationTab: String, CaseIterable, Identifiable {
    case browser = "Browser"
    case map = "API Map"
    case sql = "Database Explorer"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .browser: return "globe"
        case .map: return "map"
        case .sql: return "cylinder"
        case .settings: return "gearshape"
        }
    }

    var showsDomainsSidebar: Bool {
        self == .browser
    }

    var showsTrafficInspector: Bool {
        self == .browser
    }
}

// MARK: - Intercept Mode

enum InterceptMode: String, CaseIterable, Identifiable {
    case jsInjection
    case networkProxy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jsInjection: return "JavaScript Injection"
        case .networkProxy: return "Network Proxy"
        }
    }
}

@Observable
final class AppState {
    static let shared = AppState()

    var isRecording: Bool = false

    var selectedTab: NavigationTab = .browser
    var selectedDomain: String?
    var selectedCapture: UUID?

    var capturedRequestsCount: Int = 0
    var filteredRequestsCount: Int = 0

    var interceptMode: InterceptMode = Preferences.shared.interceptMode {
        didSet { Preferences.shared.interceptMode = interceptMode }
    }

    private init() {}
}
