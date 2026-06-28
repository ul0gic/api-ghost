import SwiftUI
import UniformTypeIdentifiers
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "ExportDialogView")

// MARK: - Format Option Row

struct FormatOptionRow: View {
    let format: ExportFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .ghostAccent : .ghostTextMuted)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(format.rawValue)
                            .font(.system(size: 13, weight: .medium))
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
                        .font(.system(size: 11))
                        .foregroundColor(.ghostTextMuted)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(10)
            .background(isSelected ? Color.ghostAccentMuted.opacity(0.5) : Color.ghostSurfaceRaised)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.ghostAccent : Color.ghostBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Checkbox Row

struct CheckboxRow: View {
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
                        .font(.system(size: 13))
                        .foregroundColor(.ghostTextPrimary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.ghostTextMuted)
                    }
                }
                Spacer()
            }
        })
        .buttonStyle(.plain)
    }
}

// MARK: - Export Stat Item

struct ExportStatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.ghostAccent)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.ghostTextMuted)
        }
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.ghostBase)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? Color.ghostAccentHover : Color.ghostAccent)
            .cornerRadius(6)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
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

// MARK: - Export Document (for file exporter)

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .database] }

    let filename: String
    let format: ExportFormat

    init(filename: String, format: ExportFormat) {
        self.filename = filename
        self.format = format
    }

    init(configuration: ReadConfiguration) throws {
        self.filename = "export"
        self.format = .json
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data())
    }
}

// MARK: - UTType Extension

extension UTType {
    nonisolated static let database = UTType(filenameExtension: "db") ?? .data
}
