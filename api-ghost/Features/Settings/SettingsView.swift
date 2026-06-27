//
//  SettingsView.swift
//  api-ghost
//
//  Comprehensive settings window with tabs for General, Proxy, Filtering,
//  Certificate, and Data Management settings.
//

import SwiftUI
import UniformTypeIdentifiers
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "SettingsView")

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case filtering = "Filtering"
    case dataManagement = "Data Management"

    var icon: String {
        switch self {
        case .general: return "gear"
        case .filtering: return "line.3.horizontal.decrease.circle"
        case .dataManagement: return "cylinder.split.1x2"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem {
                    Label(SettingsTab.general.rawValue, systemImage: SettingsTab.general.icon)
                }
                .tag(SettingsTab.general)

            FilteringSettingsTab()
                .tabItem {
                    Label(SettingsTab.filtering.rawValue, systemImage: SettingsTab.filtering.icon)
                }
                .tag(SettingsTab.filtering)

            DataManagementSettingsTab()
                .tabItem {
                    Label(SettingsTab.dataManagement.rawValue, systemImage: SettingsTab.dataManagement.icon)
                }
                .tag(SettingsTab.dataManagement)
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color.ghostBase)
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsToTab)) { notification in
            if let tab = notification.object as? SettingsTab {
                selectedTab = tab
            }
        }
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @State private var autoStartRecording: Bool = Preferences.shared.autoStartRecording
    @State private var defaultURL: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                aboutSection
                recordingSection
                defaultURLSection
                appearanceSection
                Spacer()
            }
            .padding(20)
        }
        .background(Color.ghostBase)
    }

    private var aboutSection: some View {
        GroupBox(label: SettingsSectionHeader(title: "About", icon: "info.circle")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Image("AppLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("APIGhost")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.ghostTextPrimary)
                        Text("Version 1.0.0")
                            .font(.system(size: 13))
                            .foregroundColor(.ghostTextMuted)
                        Text("API traffic capture and analysis tool for macOS")
                            .font(.system(size: 12))
                            .foregroundColor(.ghostTextSecondary)
                            .padding(.top, 2)
                    }
                    Spacer()
                }
            }
            .padding(16)
        }
        .backgroundStyle(Color.ghostSurface)
    }

    private var recordingSection: some View {
        GroupBox(label: SettingsSectionHeader(title: "Recording", icon: "record.circle")) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-start recording on launch")
                            .font(.system(size: 13))
                            .foregroundColor(.ghostTextPrimary)
                        Text("Automatically begin capturing traffic when the app starts")
                            .font(.system(size: 11))
                            .foregroundColor(.ghostTextMuted)
                    }
                    Spacer()
                    Toggle("", isOn: $autoStartRecording)
                        .toggleStyle(.switch)
                        .tint(.ghostAccent)
                        .onChange(of: autoStartRecording) { _, newValue in
                            Preferences.shared.autoStartRecording = newValue
                        }
                }
            }
            .padding(16)
        }
        .backgroundStyle(Color.ghostSurface)
    }

    private var defaultURLSection: some View {
        GroupBox(label: SettingsSectionHeader(title: "Default URL", icon: "link")) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Set a default URL to load when the browser starts")
                    .font(.system(size: 11))
                    .foregroundColor(.ghostTextMuted)
                TextField("https://example.com", text: $defaultURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.ghostTextPrimary)
                    .padding(10)
                    .background(Color.ghostInput)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.ghostBorder, lineWidth: 1)
                    )
            }
            .padding(16)
        }
        .backgroundStyle(Color.ghostSurface)
    }

    private var appearanceSection: some View {
        GroupBox(label: SettingsSectionHeader(title: "Appearance", icon: "paintbrush")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Theme")
                            .font(.system(size: 13))
                            .foregroundColor(.ghostTextPrimary)
                        Text("Dark mode only (more themes coming soon)")
                            .font(.system(size: 11))
                            .foregroundColor(.ghostTextMuted)
                    }
                    Spacer()
                    Text("Dark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ghostTextSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.ghostSurfaceRaised)
                        .cornerRadius(6)
                }
            }
            .padding(16)
        }
        .backgroundStyle(Color.ghostSurface)
    }
}

// MARK: - Filtering Settings Tab

struct FilteringSettingsTab: View {
    var body: some View {
        FilterSettingsView()
    }
}

// MARK: - Data Stat Row

struct DataStatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.ghostTextMuted)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.ghostTextSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.ghostAccent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Export Format Row

struct ExportFormatRow: View {
    let format: ExportFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .ghostAccent : .ghostTextMuted)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(format.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.ghostTextPrimary)
                        if format.isRecommended {
                            Text("Recommended")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.ghostAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.ghostAccentMuted)
                                .cornerRadius(4)
                        }
                    }
                    Text(format.description)
                        .font(.system(size: 10))
                        .foregroundColor(.ghostTextMuted)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(8)
            .background(isSelected ? Color.ghostAccentMuted.opacity(0.5) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Export Checkbox Row

struct ExportCheckboxRow: View {
    let title: String
    var subtitle: String?
    @Binding var isChecked: Bool

    var body: some View {
        Button(action: { isChecked.toggle() }, label: {
            HStack(spacing: 10) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(isChecked ? .ghostAccent : .ghostTextMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12))
                        .foregroundColor(.ghostTextPrimary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundColor(.ghostTextMuted)
                    }
                }
                Spacer()
            }
        })
        .buttonStyle(.plain)
    }
}

// MARK: - Settings Section Header

struct SettingsSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.ghostAccent)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.ghostTextPrimary)
        }
    }
}

// MARK: - Button Styles

struct GhostPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.ghostBase)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? Color.ghostAccent.opacity(0.8) : Color.ghostAccent)
            .cornerRadius(6)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
