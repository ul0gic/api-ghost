import SwiftUI
import UniformTypeIdentifiers
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "ExportDialogView")

// MARK: - Export Format

enum ExportFormat: String, CaseIterable, Identifiable {
    case sqlite = "SQLite Database"
    case json = "JSON"
    case har = "HAR (HTTP Archive)"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .sqlite: return "db"
        case .json: return "json"
        case .har: return "har"
        }
    }

    var description: String {
        switch self {
        case .sqlite:
            return "Recommended - Full database copy with all data. Best for LLM analysis."
        case .json:
            return "JSON array of captured requests. Portable and human-readable."
        case .har:
            return "HTTP Archive format. Compatible with browser developer tools."
        }
    }

    var isRecommended: Bool { self == .sqlite }
}

// MARK: - Export Options

struct ExportOptions {
    var format: ExportFormat = .sqlite
    var includeHeaders: Bool = true
    var includeBodies: Bool = true
    var includeFiltered: Bool = false
    var filename: String = ""
    var location: URL?
}

// MARK: - Export Dialog View

struct ExportDialogView: View {
    @Environment(\.dismiss)
    private var dismiss

    @State private var options = ExportOptions()
    @State private var isExporting: Bool = false
    @State private var exportError: String?
    @State private var showLocationPicker: Bool = false

    @State private var requestCount: Int = 0
    @State private var filteredCount: Int = 0
    @State private var databaseSize: String = "0 KB"

    var body: some View {
        VStack(spacing: 0) {
            dialogHeader
            Divider().background(Color.ghostBorder)
            dialogContent
            Divider().background(Color.ghostBorder)
            dialogFooter
        }
        .frame(width: 480, height: 560)
        .background(Color.ghostBase)
        .onAppear { loadStats(); generateDefaultFilename() }
        .fileExporter(
            isPresented: $showLocationPicker,
            document: ExportDocument(filename: options.filename, format: options.format),
            contentType: options.format == .sqlite ? .database : .json,
            defaultFilename: options.filename
        ) { result in
            switch result {
            case .success(let url):
                options.location = url
                doExport(to: url)
            case .failure(let error):
                exportError = error.localizedDescription
            }
        }
    }

    // MARK: - Header

    private var dialogHeader: some View {
        HStack {
            Text("Export Captured Data")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.ghostTextPrimary)
            Spacer()
            Button(action: { dismiss() }, label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.ghostTextMuted)
            })
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.ghostSurface)
    }

    // MARK: - Content

    private var dialogContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                formatSection
                Divider().background(Color.ghostBorder)
                fileSection
                Divider().background(Color.ghostBorder)
                includeOptionsSection
                statsSection
                errorSection
            }
            .padding(16)
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FORMAT").font(.system(size: 11, weight: .semibold)).foregroundColor(.ghostTextMuted)
            ForEach(ExportFormat.allCases) { format in
                FormatOptionRow(
                    format: format, isSelected: options.format == format
                ) { options.format = format }
            }
        }
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FILENAME").font(.system(size: 11, weight: .semibold)).foregroundColor(.ghostTextMuted)
            HStack(spacing: 8) {
                TextField("Enter filename", text: $options.filename)
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
                Text(".\(options.format.fileExtension)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.ghostTextMuted)
            }
        }
    }

    private var includeOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INCLUDE").font(.system(size: 11, weight: .semibold)).foregroundColor(.ghostTextMuted)
            VStack(alignment: .leading, spacing: 8) {
                CheckboxRow(title: "Request/Response Headers", isChecked: $options.includeHeaders)
                CheckboxRow(title: "Request/Response Bodies", isChecked: $options.includeBodies)
                CheckboxRow(
                    title: "Filtered Requests",
                    subtitle: "\(filteredCount) filtered requests",
                    isChecked: $options.includeFiltered
                )
            }
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DATA SUMMARY").font(.system(size: 11, weight: .semibold)).foregroundColor(.ghostTextMuted)
            HStack(spacing: 24) {
                ExportStatItem(label: "Requests", value: "\(requestCount)")
                ExportStatItem(label: "Filtered", value: "\(filteredCount)")
                ExportStatItem(label: "Database Size", value: databaseSize)
            }
            .padding(12)
            .background(Color.ghostSurfaceRaised)
            .cornerRadius(6)
        }
    }

    @ViewBuilder private var errorSection: some View {
        if let error = exportError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.ghostError)
                Text(error).font(.system(size: 12)).foregroundColor(.ghostError)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ghostError.opacity(0.1))
            .cornerRadius(6)
        }
    }

    // MARK: - Footer

    private var dialogFooter: some View {
        HStack {
            Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle())
            Spacer()
            Button(action: performExport) {
                if isExporting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .ghostBase))
                        .scaleEffect(0.8)
                } else {
                    Text("Export")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isExporting || options.filename.isEmpty)
        }
        .padding(16)
        .background(Color.ghostSurface)
    }

    // MARK: - Actions

    private func loadStats() {
        do {
            requestCount = try CaptureStore.shared.count()
            filteredCount = try CaptureStore.shared.filteredCount()
            databaseSize = DatabaseManager.shared.getDatabaseSize()
        } catch {
            logger.error("Failed to load stats: \(error)")
        }
    }

    private func generateDefaultFilename() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        options.filename = "apighost_export_\(formatter.string(from: Date()))"
    }

    private func performExport() { showLocationPicker = true }

    private func doExport(to url: URL) {
        isExporting = true
        exportError = nil
        let format = options.format
        let includeHeaders = options.includeHeaders
        let includeBodies = options.includeBodies
        let includeFiltered = options.includeFiltered
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try ExportManager.shared.export(
                        to: url,
                        format: format,
                        includeHeaders: includeHeaders,
                        includeBodies: includeBodies,
                        includeFiltered: includeFiltered
                    )
                }.value
                isExporting = false
                dismiss()
            } catch {
                isExporting = false
                exportError = error.localizedDescription
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ExportDialogView()
        .preferredColorScheme(.dark)
}
