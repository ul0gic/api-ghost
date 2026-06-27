import SwiftUI

struct SidebarView: View {
    @State private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarSection(title: "NAVIGATION") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(NavigationTab.allCases) { tab in
                        NavigationButton(
                            tab: tab,
                            isSelected: appState.selectedTab == tab
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                appState.selectedTab = tab
                            }
                        }
                    }
                }
            }

            Divider()
                .background(Color.ghostBorder)

            SidebarSection(title: "STATS") {
                StatsView()
            }

            Divider()
                .background(Color.ghostBorder)

            SidebarSection(title: "QUICK ACTIONS") {
                CompactActionsView()
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ghostSurface)
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

// MARK: - Compact Actions View

struct CompactActionsView: View {
    @State private var showWipeConfirmation: Bool = false
    @State private var showExportDialog: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CompactActionButton(
                    title: "Wipe",
                    icon: "trash",
                    style: .destructive
                ) {
                    showWipeConfirmation = true
                }

                CompactActionButton(
                    title: "Export",
                    icon: "square.and.arrow.up",
                    style: .primary
                ) {
                    showExportDialog = true
                }
            }
        }
        .sheet(isPresented: $showWipeConfirmation) {
            WipeConfirmationView()
        }
        .sheet(isPresented: $showExportDialog) {
            ExportDialogView()
        }
    }
}

// MARK: - Compact Action Button

struct CompactActionButton: View {
    let title: String
    let icon: String
    let style: ActionButtonStyle
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11))
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return isHovered ? .ghostBase : .ghostAccent
        case .secondary:
            return .ghostTextSecondary
        case .destructive:
            return isHovered ? .white : .ghostError
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            return isHovered ? .ghostAccent : .clear
        case .secondary:
            return isHovered ? .ghostSurfaceRaised : .clear
        case .destructive:
            return isHovered ? .ghostError : .clear
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary:
            return .ghostAccent
        case .secondary:
            return .ghostBorder
        case .destructive:
            return .ghostError
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
        .frame(width: 180, height: 600)
}
