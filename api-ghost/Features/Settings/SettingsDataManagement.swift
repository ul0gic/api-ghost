import SwiftUI
import UniformTypeIdentifiers
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "SettingsView")

// MARK: - Data Management Settings Tab

struct DataManagementSettingsTab: View {
    @State private var requestCount: Int = 0
    @State private var filteredCount: Int = 0
    @State private var uniqueDomains: Int = 0
    @State private var uniqueEndpoints: Int = 0
    @State private var databaseSize: String = "0 KB"

    @State private var selectedFormat: ExportFormat = .sqlite
    @State private var includeHeaders: Bool = true
    @State private var includeBodies: Bool = true
    @State private var includeFiltered: Bool = false
    @State private var exportFilename: String = ""
    @State private var isExporting: Bool = false
    @State private var exportError: String?
    @State private var showExportSuccess: Bool = false

    @State private var exportBackupBeforeWipe: Bool = false
    @State private var showWipeConfirmation: Bool = false
    @State private var isWiping: Bool = false
    @State private var wipeError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statisticsSection
                exportSection
                wipeSection
                Spacer()
            }
            .padding(20)
        }
        .background(Color.ghostBase)
        .onAppear { loadStats(); generateDefaultFilename() }
        .alert("Wipe All Data?", isPresented: $showWipeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Wipe", role: .destructive) {
                if exportBackupBeforeWipe { performExport() }
                executeWipe()
            }
        } message: {
            Text(
                "This will permanently delete \(requestCount) captured requests, "
                + "\(filteredCount) filtered requests, and all associated data. "
                + "This action cannot be undone."
            )
        }
        .alert("Export Successful", isPresented: $showExportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your data has been exported successfully.")
        }
    }

    // MARK: - Statistics Section

    private var statisticsSection: some View {
        GroupBox(label: SettingsSectionHeader(title: "Database Statistics", icon: "chart.bar")) {
            VStack(spacing: 0) {
                DataStatRow(icon: "arrow.up.arrow.down", label: "Total Requests", value: "\(requestCount)")
                Divider().background(Color.ghostBorder)
                DataStatRow(icon: "eye.slash", label: "Filtered Requests", value: "\(filteredCount)")
                Divider().background(Color.ghostBorder)
                DataStatRow(icon: "globe", label: "Unique Domains", value: "\(uniqueDomains)")
                Divider().background(Color.ghostBorder)
                DataStatRow(
                    icon: "point.3.connected.trianglepath.dotted",
                    label: "Unique Endpoints",
                    value: "\(uniqueEndpoints)"
                )
                Divider().background(Color.ghostBorder)
                DataStatRow(icon: "externaldrive", label: "Database Size", value: databaseSize)
            }
            .background(Color.ghostSurfaceRaised)
            .cornerRadius(6)
            .padding(16)
        }
        .backgroundStyle(Color.ghostSurface)
    }

    // MARK: - Export Section

    private var exportSection: some View {
        GroupBox(label: SettingsSectionHeader(title: "Export Data", icon: "square.and.arrow.up")) {
            VStack(alignment: .leading, spacing: 16) {
                formatPicker
                Divider().background(Color.ghostBorder)
                includeOptions
                exportButton
                exportErrorView
            }
            .padding(16)
        }
        .backgroundStyle(Color.ghostSurface)
    }

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FORMAT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.ghostTextMuted)
            ForEach(ExportFormat.allCases) { format in
                ExportFormatRow(
                    format: format,
                    isSelected: selectedFormat == format
                ) { selectedFormat = format }
            }
        }
    }

    private var includeOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INCLUDE")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.ghostTextMuted)
            ExportCheckboxRow(title: "Request/Response Headers", isChecked: $includeHeaders)
            ExportCheckboxRow(title: "Request/Response Bodies", isChecked: $includeBodies)
            ExportCheckboxRow(
                title: "Filtered Requests",
                subtitle: "\(filteredCount) filtered",
                isChecked: $includeFiltered
            )
        }
    }

    private var exportButton: some View {
        HStack {
            Spacer()
            Button(action: performExport) {
                if isExporting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .ghostBase))
                        .scaleEffect(0.7)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export")
                    }
                }
            }
            .buttonStyle(GhostPrimaryButtonStyle())
            .disabled(isExporting || requestCount == 0)
        }
    }

    @ViewBuilder private var exportErrorView: some View {
        if let error = exportError {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.ghostError)
                Text(error).font(.system(size: 11)).foregroundColor(.ghostError)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ghostError.opacity(0.1))
            .cornerRadius(6)
        }
    }

    // MARK: - Wipe Section

    private var wipeSection: some View {
        GroupBox(label: SettingsSectionHeader(title: "Wipe Data", icon: "trash")) {
            VStack(alignment: .leading, spacing: 16) {
                wipeWarningBanner
                backupCheckbox
                wipeButton
                wipeErrorView
            }
            .padding(16)
        }
        .backgroundStyle(Color.ghostSurface)
    }

    private var wipeWarningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18)).foregroundColor(.ghostError)
            VStack(alignment: .leading, spacing: 2) {
                Text("Danger Zone")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.ghostError)
                Text("This action permanently deletes all captured traffic data and cannot be undone.")
                    .font(.system(size: 11)).foregroundColor(.ghostTextSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ghostError.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.ghostError.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(6)
    }

    private var backupCheckbox: some View {
        Button(action: { exportBackupBeforeWipe.toggle() }, label: {
            HStack(spacing: 10) {
                Image(systemName: exportBackupBeforeWipe ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(exportBackupBeforeWipe ? .ghostAccent : .ghostTextMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export backup before wiping")
                        .font(.system(size: 13)).foregroundColor(.ghostTextPrimary)
                    Text("Save a copy of the database before deletion")
                        .font(.system(size: 11)).foregroundColor(.ghostTextMuted)
                }
                Spacer()
            }
        })
        .buttonStyle(.plain)
    }

    private var wipeButton: some View {
        HStack {
            Spacer()
            Button(action: { showWipeConfirmation = true }, label: {
                if isWiping {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.7)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                        Text("Wipe All Data")
                    }
                }
            })
            .buttonStyle(WipeDestructiveButtonStyle())
            .disabled(isWiping || requestCount == 0)
        }
    }

    @ViewBuilder private var wipeErrorView: some View {
        if let error = wipeError {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.ghostError)
                Text(error).font(.system(size: 11)).foregroundColor(.ghostError)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ghostError.opacity(0.1))
            .cornerRadius(6)
        }
    }

    // MARK: - Actions

    private func loadStats() {
        do {
            requestCount = try CaptureStore.shared.count()
            filteredCount = try CaptureStore.shared.filteredCount()
            uniqueDomains = try CaptureStore.shared.uniqueDomainCount()
            uniqueEndpoints = try CaptureStore.shared.uniqueEndpointCount()
            databaseSize = DatabaseManager.shared.getDatabaseSize()
        } catch {
            logger.error("Failed to load stats: \(error)")
        }
    }

    private func generateDefaultFilename() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        exportFilename = "apighost_export_\(formatter.string(from: Date()))"
    }

    private func performExport() {
        isExporting = true
        exportError = nil
        let format = selectedFormat
        let headers = includeHeaders
        let bodies = includeBodies
        let filtered = includeFiltered
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [format == .sqlite ? .database : .json]
        savePanel.nameFieldStringValue = "\(exportFilename).\(format.fileExtension)"
        savePanel.canCreateDirectories = true
        savePanel.title = "Export Captured Data"
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try ExportManager.shared.export(
                            to: url,
                            format: format,
                            includeHeaders: headers,
                            includeBodies: bodies,
                            includeFiltered: filtered
                        )
                        DispatchQueue.main.async { isExporting = false; showExportSuccess = true }
                    } catch {
                        DispatchQueue.main.async { isExporting = false; exportError = error.localizedDescription }
                    }
                }
            } else {
                DispatchQueue.main.async { isExporting = false }
            }
        }
    }

    private func executeWipe() {
        isWiping = true
        wipeError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try DatabaseManager.shared.wipeAllData()
                try DatabaseManager.shared.vacuum()
                DispatchQueue.main.async {
                    AppState.shared.capturedRequestsCount = 0
                    AppState.shared.filteredRequestsCount = 0
                    isWiping = false
                    loadStats()
                    NotificationCenter.default.post(name: .clearTrafficList, object: nil)
                }
            } catch {
                DispatchQueue.main.async { isWiping = false; wipeError = error.localizedDescription }
            }
        }
    }
}
