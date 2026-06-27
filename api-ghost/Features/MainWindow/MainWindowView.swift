//
//  MainWindowView.swift
//  APIGhost
//
//  Main window layout using a dual-sidebar design:
//  - Left sidebar (180-200pt): Navigation, Stats, Actions
//  - Center: Main content area (Browser with traffic, Map, SQL, Settings)
//  - Right sidebar (150-180pt): Domains list (only visible in Browser view)
//

import SwiftUI

struct MainWindowView: View {
    @State private var appState = AppState.shared
    @State private var trafficCapture = TrafficCapture.shared

    var body: some View {
        HSplitView {
            // Left Sidebar: Navigation (locked to minimum width, non-resizable)
            SidebarView()
                .frame(width: 200)
                .background(Color.ghostSurface)

            // Center: Main Content Area
            ContentAreaView()
                .frame(minWidth: 500)
                .background(Color.ghostBase)

            // Right Sidebar: Domains (only in Browser view)
            if appState.selectedTab.showsDomainsSidebar {
                DomainsSidebarView()
                    .frame(width: 200)
                    .background(Color.ghostSurface)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(Color.ghostBase)
        .animation(.easeInOut(duration: 0.2), value: appState.selectedTab)
    }
}

#Preview {
    MainWindowView()
        .preferredColorScheme(.dark)
        .frame(width: 1200, height: 800)
}
