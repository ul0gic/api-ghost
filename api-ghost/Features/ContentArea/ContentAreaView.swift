import SwiftUI

// MARK: - Content Area View

struct ContentAreaView: View {
    @State private var appState = AppState.shared
    @State private var browserViewModel = BrowserViewModel()

    var body: some View {
        Group {
            switch appState.selectedTab {
            case .browser:
                BrowserWithTrafficView(viewModel: browserViewModel)
            case .map:
                MapContentView()
            case .sql:
                SQLContentView()
            case .settings:
                EmbeddedSettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ghostBase)
    }
}

// MARK: - Browser With Traffic View

struct BrowserWithTrafficView: View {
    @Bindable var viewModel: BrowserViewModel
    @State private var splitRatio = CGFloat(Preferences.shared.browserTrafficSplitRatio)

    private let minimumSectionHeight: CGFloat = 150
    private let dividerHeight: CGFloat = 8
    private let minimumTotalHeight: CGFloat = 400

    var body: some View {
        GeometryReader { geometry in
            let totalHeight = max(minimumTotalHeight, geometry.size.height)

            let clampedRatio = min(0.8, max(0.2, splitRatio))

            let availableHeight = totalHeight - dividerHeight
            let browserHeight = max(minimumSectionHeight, availableHeight * clampedRatio)
            let trafficHeight = max(minimumSectionHeight, availableHeight - browserHeight)

            let safeMinimumRatio = totalHeight > 0 ? minimumSectionHeight / totalHeight : 0.2

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    NavigationBar(viewModel: viewModel)

                    Divider()
                        .background(Color.ghostBorder)

                    BrowserView(viewModel: viewModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: browserHeight)
                .frame(minHeight: minimumSectionHeight)

                ResizableDivider(
                    splitRatio: $splitRatio,
                    totalHeight: totalHeight,
                    minimumRatio: safeMinimumRatio
                )

                TrafficInspectorView()
                    .frame(height: trafficHeight)
                    .frame(minHeight: minimumSectionHeight)
            }
        }
        .frame(minHeight: minimumTotalHeight)
        .onChange(of: splitRatio) { _, newValue in
            let clampedValue = min(0.8, max(0.2, newValue))
            Preferences.shared.browserTrafficSplitRatio = Double(clampedValue)
        }
        .onAppear {
            let storedRatio = CGFloat(Preferences.shared.browserTrafficSplitRatio)
            if storedRatio < 0.2 || storedRatio > 0.8 {
                splitRatio = min(0.8, max(0.2, storedRatio))
            }
        }
    }
}

// MARK: - Resizable Divider

struct ResizableDivider: View {
    @Binding var splitRatio: CGFloat
    let totalHeight: CGFloat
    let minimumRatio: CGFloat

    @State private var isDragging: Bool = false

    private var safeMinimumRatio: CGFloat {
        max(0.1, min(0.4, minimumRatio))
    }

    private var safeMaximumRatio: CGFloat {
        min(0.9, max(0.6, 1.0 - safeMinimumRatio))
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.ghostBorder)
                .frame(height: 1)

            RoundedRectangle(cornerRadius: 2)
                .fill(isDragging ? Color.ghostAccent : Color.ghostTextMuted)
                .frame(width: 40, height: 4)
                .opacity(isDragging ? 1.0 : 0.6)
        }
        .frame(height: 8)
        .frame(minHeight: 8)
        .contentShape(Rectangle())
        .cursor(.resizeUpDown)
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true

                    guard totalHeight > 0 else { return }

                    let dragPosition = value.location.y
                    let newRatio = (splitRatio * totalHeight + dragPosition) / totalHeight

                    splitRatio = max(safeMinimumRatio, min(safeMaximumRatio, newRatio))
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .animation(.easeOut(duration: 0.1), value: isDragging)
    }
}

// MARK: - Map Content View

struct MapContentView: View {
    var body: some View {
        MapView()
    }
}

// MARK: - SQL Content View

struct SQLContentView: View {
    var body: some View {
        SQLExplorerView()
    }
}

// MARK: - Embedded Settings View

struct EmbeddedSettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var appState = AppState.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.ghostAccent)

                    Text("Settings")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.ghostTextPrimary)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        appState.selectedTab = .browser
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ghostTextSecondary)
                        .frame(width: 24, height: 24)
                        .background(Color.ghostSurfaceRaised)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Close Settings")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.ghostSurface)

            Divider()
                .background(Color.ghostBorder)

            HSplitView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        SettingsSidebarButton(
                            tab: tab,
                            isSelected: selectedTab == tab
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTab = tab
                            }
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .frame(minWidth: 160, idealWidth: 180, maxWidth: 200)
                .background(Color.ghostSurface)

                Group {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsTab()
                    case .filtering:
                        FilteringSettingsTab()
                    case .dataManagement:
                        DataManagementSettingsTab()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.ghostBase)
    }
}

// MARK: - Settings Sidebar Button

struct SettingsSidebarButton: View {
    let tab: SettingsTab
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

#Preview {
    ContentAreaView()
        .preferredColorScheme(.dark)
        .frame(width: 800, height: 600)
}
