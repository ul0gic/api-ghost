import SwiftUI
import GRDB

// MARK: - Resizable Table View

struct ResizableTableView: View {
    let columns: [String]
    let rows: [[DatabaseValue]]
    @Bindable var viewModel: SQLViewModel
    @Binding var hoveredRowIndex: Int?
    @Binding var hoveredColumnIndex: Int?
    let onRowTap: (Int) -> Void
    let containerWidth: CGFloat

    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                ResizableTableHeader(
                    columns: columns,
                    viewModel: viewModel,
                    hoveredColumnIndex: $hoveredColumnIndex
                )
            }
            .frame(height: 32)
            .background(Color.ghostSurface)

            Divider().background(Color.ghostBorder)

            ScrollView([.vertical]) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        ScrollView(.horizontal, showsIndicators: false) {
                            ResizableTableRow(
                                columns: columns,
                                row: row,
                                rowIndex: rowIndex,
                                viewModel: viewModel,
                                isHovered: hoveredRowIndex == rowIndex
                            )
                        }
                        .background(hoveredRowIndex == rowIndex ? Color.ghostSurfaceRaised : Color.clear)
                        .onHover { hovering in hoveredRowIndex = hovering ? rowIndex : nil }
                        .onTapGesture { onRowTap(rowIndex) }
                        .contextMenu { RowContextMenu(columns: columns, row: row) }

                        if rowIndex < rows.count - 1 {
                            Divider().background(Color.ghostBorder.opacity(0.5))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Resizable Table Header

struct ResizableTableHeader: View {
    let columns: [String]
    @Bindable var viewModel: SQLViewModel
    @Binding var hoveredColumnIndex: Int?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                ResizableColumnHeader(
                    column: column,
                    columnIndex: index,
                    width: viewModel.columnWidth(for: column),
                    sortConfig: viewModel.sortConfig,
                    isHovered: hoveredColumnIndex == index,
                    isNumeric: viewModel.isNumericColumn(column),
                    onTap: { viewModel.toggleSort(for: index) },
                    onWidthChange: { newWidth in
                        viewModel.setColumnWidth(newWidth, for: column)
                    }
                )
                .onHover { hovering in
                    hoveredColumnIndex = hovering ? index : nil
                }
            }
        }
    }
}

// MARK: - Resizable Column Header

struct ResizableColumnHeader: View {
    let column: String
    let columnIndex: Int
    let width: CGFloat
    let sortConfig: SortConfiguration
    let isHovered: Bool
    let isNumeric: Bool
    let onTap: () -> Void
    let onWidthChange: (CGFloat) -> Void

    @State private var isDragging: Bool = false
    @State private var dragWidth: CGFloat = 0

    private var isSorted: Bool { sortConfig.columnIndex == columnIndex }
    private var currentWidth: CGFloat { isDragging ? dragWidth : width }

    var body: some View {
        HStack(spacing: 0) {
            columnButton
            resizeHandle
        }
        .frame(width: currentWidth)
    }

    private var columnButton: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if isNumeric { Spacer() }
                Text(column)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(isSorted ? .ghostAccent : .ghostTextSecondary)
                    .lineLimit(1)
                if isSorted {
                    Image(systemName: sortConfig.ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.ghostAccent)
                } else if isHovered {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.ghostTextMuted)
                }
                if !isNumeric { Spacer() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(width: currentWidth - 4, alignment: isNumeric ? .trailing : .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color.ghostSurfaceRaised : Color.clear)
        .help("Click to sort by \(column)")
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(isDragging ? Color.ghostAccent : Color.ghostBorder)
            .frame(width: 4)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragWidth = width
                        }
                        let newWidth = max(50, dragWidth + value.translation.width)
                        dragWidth = min(500, newWidth)
                    }
                    .onEnded { _ in
                        onWidthChange(dragWidth)
                        isDragging = false
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }
}

// MARK: - Resizable Table Row

struct ResizableTableRow: View {
    let columns: [String]
    let row: [DatabaseValue]
    let rowIndex: Int
    @Bindable var viewModel: SQLViewModel
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.offset) { index, value in
                let column = columns[index]
                let width = viewModel.columnWidth(for: column)
                let isNumeric = viewModel.isNumericColumn(column)

                SmartCell(column: column, value: value, width: width, isNumeric: isNumeric)

                Rectangle()
                    .fill(Color.ghostBorder.opacity(0.3))
                    .frame(width: 1)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
