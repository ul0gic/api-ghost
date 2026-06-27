//
//  WipeConfirmationView.swift
//  api-ghost
//
//  Confirmation dialog for wiping all captured traffic data.
//  Displays stats and offers backup option before destructive action.
//

import SwiftUI
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "WipeConfirmationView")

// MARK: - Wipe Confirmation View

struct WipeConfirmationView: View {
    @Environment(\.dismiss)
    private var dismiss

    // Callback when wipe is completed
    var onWipeComplete: (() -> Void)?

    // State
    @State private var exportBackupFirst: Bool = false
    @State private var isWiping: Bool = false
    @State private var showExportSheet: Bool = false
    @State private var wipeError: String?

    // Stats
    @State private var requestCount: Int = 0
    @State private var filteredCount: Int = 0
    @State private var endpointCount: Int = 0
    @State private var domainCount: Int = 0
    @State private var databaseSize: String = "0 KB"

    var body: some View {
        VStack(spacing: 0) {
            // Header with warning icon
            headerSection

            Divider()
                .background(Color.ghostBorder)

            // Content
            VStack(alignment: .leading, spacing: 20) {
                // Warning message
                warningMessage

                // Stats display
                statsDisplay

                // Export backup option
                exportBackupOption

                // Error display
                if let error = wipeError {
                    errorDisplay(error)
                }
            }
            .padding(20)

            Divider()
                .background(Color.ghostBorder)

            // Footer with buttons
            footerButtons
        }
        .frame(width: 420)
        .background(Color.ghostBase)
        .onAppear {
            loadStats()
        }
        .sheet(isPresented: $showExportSheet) {
            ExportDialogView()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(.ghostError)

            VStack(alignment: .leading, spacing: 2) {
                Text("Wipe All Data")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.ghostTextPrimary)

                Text("This action cannot be undone")
                    .font(.system(size: 12))
                    .foregroundColor(.ghostError)
            }

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

    // MARK: - Warning Message

    private var warningMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You are about to permanently delete all captured traffic data from the database.")
                .font(.system(size: 13))
                .foregroundColor(.ghostTextSecondary)

            Text("This includes all requests, responses, headers, and bodies.")
                .font(.system(size: 13))
                .foregroundColor(.ghostTextSecondary)
        }
    }

    // MARK: - Stats Display

    private var statsDisplay: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DATA TO BE DELETED")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.ghostTextMuted)

            VStack(spacing: 0) {
                statsRow(icon: "arrow.up.arrow.down", label: "Requests", value: "\(requestCount)")
                Divider().background(Color.ghostBorder)
                statsRow(icon: "eye.slash", label: "Filtered", value: "\(filteredCount)")
                Divider().background(Color.ghostBorder)
                statsRow(icon: "point.3.connected.trianglepath.dotted", label: "Endpoints", value: "\(endpointCount)")
                Divider().background(Color.ghostBorder)
                statsRow(icon: "globe", label: "Domains", value: "\(domainCount)")
                Divider().background(Color.ghostBorder)
                statsRow(icon: "externaldrive", label: "Database Size", value: databaseSize)
            }
            .background(Color.ghostSurfaceRaised)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.ghostError.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private func statsRow(icon: String, label: String, value: String) -> some View {
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
                .foregroundColor(.ghostTextPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Export Backup Option

    private var exportBackupOption: some View {
        Button(action: { exportBackupFirst.toggle() }, label: {
            HStack(spacing: 10) {
                Image(systemName: exportBackupFirst ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(exportBackupFirst ? .ghostAccent : .ghostTextMuted)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Export backup before wiping")
                        .font(.system(size: 13))
                        .foregroundColor(.ghostTextPrimary)

                    Text("Save a copy of the database before deletion")
                        .font(.system(size: 11))
                        .foregroundColor(.ghostTextMuted)
                }

                Spacer()
            }
            .padding(12)
            .background(Color.ghostSurfaceRaised)
            .cornerRadius(6)
        })
        .buttonStyle(.plain)
    }

    // MARK: - Error Display

    private func errorDisplay(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.ghostError)
            Text(error)
                .font(.system(size: 12))
                .foregroundColor(.ghostError)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ghostError.opacity(0.1))
        .cornerRadius(6)
    }

    // MARK: - Footer Buttons

    private var footerButtons: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(WipeSecondaryButtonStyle())

            Spacer()

            Button(action: performWipe) {
                if isWiping {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                        Text("Wipe Data")
                    }
                }
            }
            .buttonStyle(WipeDestructiveButtonStyle())
            .disabled(isWiping)
        }
        .padding(16)
        .background(Color.ghostSurface)
    }

    // MARK: - Actions

    private func loadStats() {
        do {
            requestCount = try CaptureStore.shared.count()
            filteredCount = try CaptureStore.shared.filteredCount()
            // Use simple counts instead of expensive aggregation functions
            // uniqueEndpointCount() runs regex on all response bodies - way too slow
            endpointCount = try CaptureStore.shared.uniquePathCount()
            domainCount = try CaptureStore.shared.uniqueDomainCount()
            databaseSize = DatabaseManager.shared.getDatabaseSize()
        } catch {
            logger.error("Failed to load stats: \(error)")
        }
    }

    private func performWipe() {
        if exportBackupFirst {
            showExportSheet = true
            return
        }

        executeWipe()
    }

    private func executeWipe() {
        isWiping = true
        wipeError = nil

        // Pause capture to prevent database contention during wipe
        let wasCapturing = TrafficCapture.shared.isCapturing
        TrafficCapture.shared.pauseCapture()

        // Clear in-memory captures FIRST to stop UI from reading database
        TrafficCapture.shared.clearRecentCaptures()
        AppState.shared.capturedRequestsCount = 0
        AppState.shared.filteredRequestsCount = 0

        // Give UI time to update and release any database reads
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) {
            do {
                // Wipe all data
                try DatabaseManager.shared.wipeAllData()

                // Vacuum to reclaim space
                try DatabaseManager.shared.vacuum()

                // Complete on main thread
                DispatchQueue.main.async {
                    isWiping = false
                    onWipeComplete?()
                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    // Resume capture if it was running before
                    if wasCapturing {
                        TrafficCapture.shared.resumeCapture()
                    }
                    isWiping = false
                    wipeError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Button Styles

struct WipeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.ghostTextSecondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? Color.ghostSurfaceRaised : Color.ghostSurface)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.ghostBorder, lineWidth: 1)
            )
    }
}

struct WipeDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? Color.ghostError.opacity(0.8) : Color.ghostError)
            .cornerRadius(6)
    }
}

// MARK: - Preview

#Preview {
    WipeConfirmationView()
        .preferredColorScheme(.dark)
}
