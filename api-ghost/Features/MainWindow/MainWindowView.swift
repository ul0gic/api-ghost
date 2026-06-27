import SwiftUI

struct MainWindowView: View {
    @State private var appState = AppState.shared
    @State private var trafficCapture = TrafficCapture.shared

    var body: some View {
        HSplitView {
            SidebarView()
                .frame(width: 200)
                .background(Color.ghostSurface)

            ContentAreaView()
                .frame(minWidth: 500)
                .background(Color.ghostBase)

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
