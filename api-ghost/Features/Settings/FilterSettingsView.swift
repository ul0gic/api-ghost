import SwiftUI

// MARK: - Filter Settings View

struct FilterSettingsView: View {
    @State private var blockedDomains: [String] = []
    @State private var blockedPaths: [String] = []
    @State private var newDomain: String = ""
    @State private var newPath: String = ""

    @State private var captureAllTraffic: Bool = false

    @State private var selectedSizeLimit: ResponseSizeLimit = .tenMB

    @State private var showResetConfirmation: Bool = false

    @State private var categoryStore = FilterCategoryStore()

    private let noiseFilter = NoiseFilter.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CaptureAllToggleView(
                    captureAllTraffic: $captureAllTraffic,
                    noiseFilter: noiseFilter
                )

                FilterCategoriesSection(store: categoryStore)

                GroupBox(label: SettingsSectionHeader(title: "Custom Domain Blocklist", icon: "globe")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Requests to these domains will not be captured.")
                            .font(.system(size: 11))
                            .foregroundColor(.ghostTextMuted)

                        HStack {
                            TextField("Enter domain (e.g., *.google-analytics.com)", text: $newDomain)
                                .textFieldStyle(.roundedBorder)

                            Button(action: addDomain) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.ghostAccent)
                            }
                            .buttonStyle(.plain)
                            .disabled(newDomain.isEmpty)
                        }

                        if blockedDomains.isEmpty {
                            Text("No custom domains blocked")
                                .font(.system(size: 11))
                                .foregroundColor(.ghostTextMuted)
                                .padding(.vertical, 8)
                        } else {
                            ScrollView {
                                VStack(spacing: 4) {
                                    ForEach(blockedDomains, id: \.self) { domain in
                                        FilterListItem(text: domain) {
                                            removeDomain(domain)
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 100)
                        }
                    }
                    .padding(12)
                }
                .backgroundStyle(Color.ghostSurface)

                GroupBox(label: SettingsSectionHeader(title: "Custom Path Patterns", icon: "arrow.triangle.branch")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Requests with paths containing these patterns will not be captured.")
                            .font(.system(size: 11))
                            .foregroundColor(.ghostTextMuted)

                        HStack {
                            TextField("Enter path pattern (e.g., /analytics)", text: $newPath)
                                .textFieldStyle(.roundedBorder)

                            Button(action: addPath) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.ghostAccent)
                            }
                            .buttonStyle(.plain)
                            .disabled(newPath.isEmpty)
                        }

                        if blockedPaths.isEmpty {
                            Text("No custom path patterns")
                                .font(.system(size: 11))
                                .foregroundColor(.ghostTextMuted)
                                .padding(.vertical, 8)
                        } else {
                            ScrollView {
                                VStack(spacing: 4) {
                                    ForEach(blockedPaths, id: \.self) { path in
                                        FilterListItem(text: path) {
                                            removePath(path)
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 100)
                        }
                    }
                    .padding(12)
                }
                .backgroundStyle(Color.ghostSurface)

                GroupBox(label: SettingsSectionHeader(title: "Response Size Limit", icon: "arrow.up.arrow.down")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Max response size to capture.")
                            .font(.system(size: 11))
                            .foregroundColor(.ghostTextMuted)

                        Picker("Max Response Size", selection: $selectedSizeLimit) {
                            ForEach(ResponseSizeLimit.allCases, id: \.self) { limit in
                                Text(limit.displayName).tag(limit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedSizeLimit) { _, newValue in
                            noiseFilter.maxResponseSize = newValue.bytes
                            Preferences.shared.maxResponseSize = newValue.bytes
                        }
                    }
                    .padding(12)
                }
                .backgroundStyle(Color.ghostSurface)

                HStack {
                    Spacer()
                    Button(action: { showResetConfirmation = true }, label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to Defaults")
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.ghostWarning)
                    })
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)
                }
            }
            .padding()
        }
        .background(Color.ghostBase)
        .onAppear(perform: loadSettings)
        .alert("Reset Filter Settings", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetToDefaults()
            }
        } message: {
            Text("This will remove all custom filter rules and restore the default blocklist.")
        }
    }

    // MARK: - Actions

    private func addDomain() {
        let domain = newDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !domain.isEmpty, !blockedDomains.contains(domain) else { return }

        blockedDomains.append(domain)
        noiseFilter.addDomainRule(domain, isWildcard: domain.hasPrefix("*."))
        saveSettings()
        newDomain = ""
    }

    private func removeDomain(_ domain: String) {
        blockedDomains.removeAll { $0 == domain }
        noiseFilter.removeDomainRule(domain)
        saveSettings()
    }

    private func addPath() {
        let path = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !blockedPaths.contains(path) else { return }

        blockedPaths.append(path)
        noiseFilter.addPathRule(path)
        saveSettings()
        newPath = ""
    }

    private func removePath(_ path: String) {
        blockedPaths.removeAll { $0 == path }
        noiseFilter.removePathRule(path)
        saveSettings()
    }

    private func resetToDefaults() {
        noiseFilter.resetToDefaults()
        noiseFilter.isEnabled = true
        categoryStore.resetToDefaults()
        captureAllTraffic = false
        blockedDomains = []
        blockedPaths = []
        selectedSizeLimit = .tenMB
        Preferences.shared.filteringEnabled = true
        saveSettings()
    }

    private func loadSettings() {
        captureAllTraffic = !Preferences.shared.filteringEnabled

        blockedDomains = Preferences.shared.customBlockedDomains
        blockedPaths = Preferences.shared.customBlockedPaths

        let storedSize = Preferences.shared.maxResponseSize
        selectedSizeLimit = ResponseSizeLimit.allCases.first { $0.bytes == storedSize } ?? .tenMB
    }

    private func saveSettings() {
        Preferences.shared.customBlockedDomains = blockedDomains
        Preferences.shared.customBlockedPaths = blockedPaths
        Preferences.shared.maxResponseSize = selectedSizeLimit.bytes
    }
}

// MARK: - Preview

#Preview {
    FilterSettingsView()
        .preferredColorScheme(.dark)
        .frame(width: 550, height: 500)
}
