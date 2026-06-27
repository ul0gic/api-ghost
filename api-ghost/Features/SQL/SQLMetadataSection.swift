//
//  SQLMetadataSection.swift
//  APIGhost
//
//  Metadata section for SQL capture detail view.
//

import SwiftUI

// MARK: - Metadata Section

struct MetadataSection: View {
    let capture: Capture
    @Binding var copiedItem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            timingCard
            sizesCard
            urlComponentsCard
            identifiersCard
            contentTypeCard
        }
    }

    private var timingCard: some View {
        CaptureDetailCard(title: "Timing") {
            VStack(alignment: .leading, spacing: 8) {
                MetadataRow(label: "Timestamp", value: formatTimestamp(capture.timestamp))
                if let duration = capture.durationMs {
                    MetadataRow(label: "Duration", value: formatDuration(duration))
                }
            }
        }
    }

    private var sizesCard: some View {
        CaptureDetailCard(title: "Sizes") {
            VStack(alignment: .leading, spacing: 8) {
                MetadataRow(label: "Request Body", value: formatBytes(capture.requestBodySize))
                MetadataRow(label: "Response Body", value: formatBytes(capture.responseBodySize))
            }
        }
    }

    private var urlComponentsCard: some View {
        CaptureDetailCard(title: "URL Components") {
            VStack(alignment: .leading, spacing: 8) {
                MetadataRow(label: "Scheme", value: capture.scheme)
                MetadataRow(label: "Host", value: capture.host)
                if let port = capture.port {
                    MetadataRow(label: "Port", value: "\(port)")
                }
                MetadataRow(label: "Path", value: capture.path)
                if let query = capture.query, !query.isEmpty {
                    MetadataRow(label: "Query", value: query)
                }
            }
        }
    }

    private var identifiersCard: some View {
        CaptureDetailCard(title: "Identifiers") {
            VStack(alignment: .leading, spacing: 8) {
                if let captureId = capture.id {
                    MetadataRow(label: "ID", value: "\(captureId)")
                }
                MetadataRow(label: "UUID", value: capture.uuid)
                if let sessionId = capture.sessionId {
                    MetadataRow(label: "Session ID", value: sessionId)
                }
            }
        }
    }

    @ViewBuilder private var contentTypeCard: some View {
        if let contentType = capture.contentType {
            CaptureDetailCard(title: "Content") {
                MetadataRow(label: "Content-Type", value: contentType)
            }
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatDuration(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms) ms" }
        return String(format: "%.2f s", Double(ms) / 1000)
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes == 0 { return "0 B" }
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
