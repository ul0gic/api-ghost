//
//  AppState.swift
//  api-ghost
//
//  Global application state using @Observable macro
//

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

    /// Whether this tab shows the domains sidebar
    var showsDomainsSidebar: Bool {
        self == .browser
    }

    /// Whether this tab shows the traffic inspector
    var showsTrafficInspector: Bool {
        self == .browser
    }
}

@Observable
final class AppState {
    static let shared = AppState()

    // Recording state
    var isRecording: Bool = false

    // Navigation state
    var selectedTab: NavigationTab = .browser
    var selectedDomain: String?
    var selectedCapture: UUID?

    // Stats
    var capturedRequestsCount: Int = 0
    var filteredRequestsCount: Int = 0

    private init() {}
}
