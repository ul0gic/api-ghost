import SwiftUI

struct SidebarView: View {
    @State private var appState = AppState.shared
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("NAVIGATION")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.ghostTextMuted)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .bottomLeading)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(NavigationTab.allCases) { tab in
                            NavigationButton(
                                tab: tab,
                                isSelected: appState.selectedTab == tab
                            ) {
                                selectTab(tab)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }

                Divider()
                    .background(Color.ghostBorder)

                SidebarSection(title: "STATS") {
                    StatsView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ghostSurface)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooterView()
        }
    }

    private func selectTab(_ tab: NavigationTab) {
        if reduceMotion {
            appState.selectedTab = tab
        } else {
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.selectedTab = tab
            }
        }
    }
}

// MARK: - Navigation Button

struct NavigationButton: View {
    let tab: NavigationTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .ghostAccent : .ghostTextMuted)
                    .frame(width: 20)

                Text(tab.rawValue)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .ghostTextPrimary : .ghostTextSecondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(backgroundColor)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.ghostAccentMuted
        } else if isHovered {
            return Color.ghostSurfaceRaised
        } else {
            return Color.clear
        }
    }
}

// MARK: - Sidebar Footer

struct SidebarFooterView: View {
    @State private var showWipeConfirmation: Bool = false
    @State private var showExportDialog: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            Button {
                showExportDialog = true
            } label: {
                footerLabel(title: "Export Session", icon: "square.and.arrow.up")
            }
            .buttonStyle(GhostButtonStyle(role: .accent, fullWidth: true))

            Button {
                showWipeConfirmation = true
            } label: {
                footerLabel(title: "Wipe Session", icon: "trash")
            }
            .buttonStyle(GhostButtonStyle(role: .destructive, fullWidth: true))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.ghostSurface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.ghostBorder)
                .frame(height: 1)
        }
        .sheet(isPresented: $showWipeConfirmation) {
            WipeConfirmationView()
        }
        .sheet(isPresented: $showExportDialog) {
            ExportDialogView()
        }
    }

    private func footerLabel(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(title)
                .font(.system(size: 12))
        }
    }
}

// MARK: - Sidebar Section

struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.ghostTextMuted)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            content
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }
}

#Preview {
    SidebarView()
        .preferredColorScheme(.dark)
        .frame(width: 200, height: 600)
}
