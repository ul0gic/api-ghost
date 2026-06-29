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
            SidebarFooterButton(
                title: "Export DB",
                icon: "arrow.up",
                role: .export
            ) {
                showExportDialog = true
            }

            SidebarFooterButton(
                title: "Wipe Session",
                icon: "trash",
                role: .destructive
            ) {
                showWipeConfirmation = true
            }
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
}

// MARK: - Sidebar Footer Button

enum SidebarFooterButtonRole {
    case destructive
    case export
}

struct SidebarFooterButton: View {
    let title: String
    let icon: String
    let role: SidebarFooterButtonRole
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12))
            }
            .foregroundColor(foregroundColor)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var foregroundColor: Color {
        switch role {
        case .destructive:
            return isHovered ? .white : .ghostError
        case .export:
            return isHovered ? .ghostBase : .ghostAccent
        }
    }

    private var backgroundColor: Color {
        switch role {
        case .destructive:
            return isHovered ? .ghostError : .clear
        case .export:
            return isHovered ? .ghostAccent : .ghostAccentMuted
        }
    }

    private var borderColor: Color {
        switch role {
        case .destructive:
            return .ghostError
        case .export:
            return .ghostAccent
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
