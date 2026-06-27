//
//  SQLResultsSheets.swift
//  APIGhost
//
//  Sheet views for SQL results: row detail, empty states, and executing view.
//

import SwiftUI
import GRDB

// MARK: - Empty States

struct EmptyResultsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundColor(.ghostTextMuted)
            Text("No Results")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.ghostTextSecondary)
            Text("Query executed successfully but returned no rows.")
                .font(.system(size: 12))
                .foregroundColor(.ghostTextMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoQueryView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.and.pencil.and.ellipsis")
                .font(.system(size: 36))
                .foregroundColor(.ghostTextMuted)
            Text("No Query Executed")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.ghostTextSecondary)
            Text("Write a SQL query above and click Execute to see results.")
                .font(.system(size: 12))
                .foregroundColor(.ghostTextMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ExecutingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().scaleEffect(1.2)
            Text("Executing query...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.ghostTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row Detail Sheet

struct RowDetailSheet: View {
    let columns: [String]
    let row: [DatabaseValue]
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Row Details")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.ghostTextPrimary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ghostTextSecondary)
                        .frame(width: 24, height: 24)
                        .background(Color.ghostSurfaceRaised)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(16)
            .background(Color.ghostSurface)

            Divider().background(Color.ghostBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(column)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.ghostTextMuted)
                            Text(fullValue(for: row[index]))
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.ghostTextPrimary)
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.ghostInput)
                                .cornerRadius(6)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 500, height: 400)
        .background(Color.ghostBase)
    }

    private func fullValue(for value: DatabaseValue) -> String {
        switch value.storage {
        case .null: return "NULL"
        case .int64(let int): return String(int)
        case .double(let double): return String(double)
        case .string(let string): return string
        case .blob(let data):
            if let str = String(data: data, encoding: .utf8) { return str }
            return "<BLOB \(data.count) bytes>"
        }
    }
}
