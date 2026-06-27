import SwiftUI

// MARK: - Schema Browser View

struct SQLSchemaBrowser: View {
    @Bindable var viewModel: SQLViewModel
    @State private var isColumnsExpanded: Bool = true
    @State private var isIndexesExpanded: Bool = false
    @State private var isStatisticsExpanded: Bool = true
    @State private var isHistoryExpanded: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SchemaSectionHeader(title: "SCHEMA")

                SchemaTableSection(
                    viewModel: viewModel,
                    isExpanded: $isColumnsExpanded
                )

                SchemaIndexesSection(
                    viewModel: viewModel,
                    isExpanded: $isIndexesExpanded
                )

                Divider()
                    .background(Color.ghostBorder)
                    .padding(.vertical, 8)

                SchemaStatisticsSection(
                    viewModel: viewModel,
                    isExpanded: $isStatisticsExpanded
                )

                Divider()
                    .background(Color.ghostBorder)
                    .padding(.vertical, 8)

                SchemaHistorySection(
                    viewModel: viewModel,
                    isExpanded: $isHistoryExpanded
                )

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
        .background(Color.ghostSurface)
    }
}

// MARK: - Section Header

struct SchemaSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.ghostTextMuted)
            .tracking(1)
            .padding(.vertical, 8)
    }
}

// MARK: - Table Section

struct SchemaTableSection: View {
    @Bindable var viewModel: SQLViewModel
    @Binding var isExpanded: Bool
    @State private var hoveredColumn: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }, label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.ghostTextMuted)
                        .frame(width: 12)

                    Image(systemName: "tablecells")
                        .font(.system(size: 12))
                        .foregroundColor(.ghostAccent)

                    Text("captures")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ghostTextPrimary)

                    Spacer()

                    Text("\(viewModel.schemaColumns.count)")
                        .font(.system(size: 10))
                        .foregroundColor(.ghostTextMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.ghostSurfaceRaised)
                        .cornerRadius(4)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            })
            .buttonStyle(.plain)
            .onTapGesture(count: 2) {
                viewModel.generateSelectQuery(for: "captures")
            }
            .help("Double-click to generate SELECT query")

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.schemaColumns) { column in
                        SchemaColumnRow(
                            column: column,
                            isHovered: hoveredColumn == column.name
                        ) {
                            viewModel.insertColumnName(column.name)
                        }
                        .onHover { hovering in
                            hoveredColumn = hovering ? column.name : nil
                        }
                    }
                }
                .padding(.leading, 18)
            }
        }
    }
}

// MARK: - Column Row

struct SchemaColumnRow: View {
    let column: SchemaColumn
    let isHovered: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: columnIcon)
                    .font(.system(size: 10))
                    .foregroundColor(columnColor)
                    .frame(width: 14)

                Text(column.name)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.ghostTextSecondary)
                    .lineLimit(1)

                Spacer()

                Text(shortTypeName)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.ghostTextMuted)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isHovered ? Color.ghostSurfaceRaised : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to insert '\(column.name)' into query")
    }

    private var columnIcon: String {
        if column.isPrimaryKey {
            return "key.fill"
        }
        switch column.type.uppercased() {
        case "INTEGER", "INT", "INT64":
            return "number"
        case "TEXT", "VARCHAR":
            return "textformat"
        case "BLOB":
            return "doc.fill"
        case "DATETIME", "DATE":
            return "calendar"
        case "BOOLEAN", "BOOL":
            return "checkmark.square"
        default:
            return "circle.fill"
        }
    }

    private var columnColor: Color {
        if column.isPrimaryKey {
            return .ghostAccent
        }
        switch column.type.uppercased() {
        case "INTEGER", "INT", "INT64":
            return .ghostJsonNumber
        case "TEXT", "VARCHAR":
            return .ghostJsonString
        case "BLOB":
            return .ghostTextMuted
        case "DATETIME", "DATE":
            return .ghostMethodPut
        case "BOOLEAN", "BOOL":
            return .ghostJsonBool
        default:
            return .ghostTextMuted
        }
    }

    private var shortTypeName: String {
        switch column.type.uppercased() {
        case "INTEGER": return "int"
        case "TEXT": return "text"
        case "BLOB": return "blob"
        case "DATETIME": return "date"
        case "BOOLEAN": return "bool"
        default: return column.type.lowercased()
        }
    }
}

// MARK: - Indexes Section

struct SchemaIndexesSection: View {
    @Bindable var viewModel: SQLViewModel
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }, label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.ghostTextMuted)
                        .frame(width: 12)

                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 12))
                        .foregroundColor(.ghostTextSecondary)

                    Text("INDEXES")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.ghostTextMuted)
                        .tracking(0.5)

                    Spacer()

                    Text("\(viewModel.schemaIndexes.count)")
                        .font(.system(size: 10))
                        .foregroundColor(.ghostTextMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.ghostSurfaceRaised)
                        .cornerRadius(4)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            })
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.schemaIndexes) { index in
                        HStack(spacing: 6) {
                            Image(systemName: index.isUnique ? "lock.fill" : "list.number")
                                .font(.system(size: 9))
                                .foregroundColor(index.isUnique ? .ghostAccent : .ghostTextMuted)
                                .frame(width: 14)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(index.name)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.ghostTextSecondary)
                                    .lineLimit(1)

                                Text(index.columns.joined(separator: ", "))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.ghostTextMuted)
                                    .lineLimit(1)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                    }
                }
                .padding(.leading, 18)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SQLSchemaBrowser(viewModel: SQLViewModel())
        .preferredColorScheme(.dark)
        .frame(width: 240, height: 600)
}
