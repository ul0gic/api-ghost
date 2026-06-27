import SwiftUI

// MARK: - SQL Explorer View

struct SQLExplorerView: View {
    @State private var viewModel = SQLViewModel()
    @State private var schemaBrowserWidth: CGFloat = 220
    @State private var editorHeight: CGFloat = 200

    private let minimumBrowserWidth: CGFloat = 180
    private let maximumBrowserWidth: CGFloat = 350

    private let minimumEditorHeight: CGFloat = 120
    private let minimumResultsHeight: CGFloat = 150

    var body: some View {
        HStack(spacing: 0) {
            SQLSchemaBrowser(viewModel: viewModel)
                .frame(width: schemaBrowserWidth)

            SchemaBrowserResizeHandle(
                width: $schemaBrowserWidth,
                minWidth: minimumBrowserWidth,
                maxWidth: maximumBrowserWidth
            )

            VStack(spacing: 0) {
                GeometryReader { geometry in
                    let totalHeight = geometry.size.height
                    let clampedEditorHeight = min(
                        max(minimumEditorHeight, editorHeight),
                        totalHeight - minimumResultsHeight - 8
                    )

                    VStack(spacing: 0) {
                        SQLEditorView(viewModel: viewModel)
                            .frame(height: clampedEditorHeight)

                        EditorResultsResizeHandle(
                            height: $editorHeight,
                            totalHeight: totalHeight,
                            minEditorHeight: minimumEditorHeight,
                            minResultsHeight: minimumResultsHeight
                        )

                        SQLResultsView(viewModel: viewModel)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.ghostBase)
        .onAppear {
            viewModel.loadSchema()
            viewModel.loadStatistics()
        }
    }
}

// MARK: - Schema Browser Resize Handle

struct SchemaBrowserResizeHandle: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat

    @State private var isDragging: Bool = false
    @State private var startWidth: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.ghostBorder)
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .cursor(.resizeLeftRight)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    startWidth = width
                                }
                                let newWidth = startWidth + value.translation.width
                                width = max(minWidth, min(maxWidth, newWidth))
                            }
                            .onEnded { _ in
                                isDragging = false
                                startWidth = 0
                            }
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .fill(isDragging ? Color.ghostAccent : Color.ghostTextMuted)
                    .frame(width: 3, height: 24)
                    .opacity(isDragging ? 1.0 : 0.3)
            )
    }
}

// MARK: - Editor/Results Resize Handle

struct EditorResultsResizeHandle: View {
    @Binding var height: CGFloat
    let totalHeight: CGFloat
    let minEditorHeight: CGFloat
    let minResultsHeight: CGFloat

    @State private var isDragging: Bool = false
    @State private var startHeight: CGFloat = 0

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.ghostBorder)
                .frame(height: 1)

            RoundedRectangle(cornerRadius: 2)
                .fill(isDragging ? Color.ghostAccent : Color.ghostTextMuted)
                .frame(width: 40, height: 4)
                .opacity(isDragging ? 1.0 : 0.6)
        }
        .frame(height: 8)
        .contentShape(Rectangle())
        .cursor(.resizeUpDown)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        startHeight = height
                    }

                    let newHeight = startHeight + value.translation.height
                    let maxEditorHeight = totalHeight - minResultsHeight - 8

                    height = max(minEditorHeight, min(maxEditorHeight, newHeight))
                }
                .onEnded { _ in
                    isDragging = false
                    startHeight = 0
                }
        )
        .animation(.easeOut(duration: 0.1), value: isDragging)
    }
}

// MARK: - SQL Explorer Header

struct SQLExplorerHeader: View {
    @State private var appState = AppState.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "cylinder.fill")
                .font(.system(size: 16))
                .foregroundColor(.ghostAccent)

            Text("SQL Database Explorer")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.ghostTextPrimary)

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    appState.selectedTab = .browser
                }
            }, label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.ghostTextSecondary)
                    .frame(width: 24, height: 24)
                    .background(Color.ghostSurfaceRaised)
                    .cornerRadius(6)
            })
            .buttonStyle(.plain)
            .help("Close SQL Explorer")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.ghostSurface)
    }
}

// MARK: - Full SQL Content View

struct SQLContentViewWithHeader: View {
    var body: some View {
        VStack(spacing: 0) {
            SQLExplorerHeader()

            Divider()
                .background(Color.ghostBorder)

            SQLExplorerView()
        }
        .background(Color.ghostBase)
    }
}

// MARK: - Preview

#Preview("SQL Explorer") {
    SQLExplorerView()
        .preferredColorScheme(.dark)
        .frame(width: 1200, height: 700)
}

#Preview("SQL Explorer with Header") {
    SQLContentViewWithHeader()
        .preferredColorScheme(.dark)
        .frame(width: 1200, height: 700)
}
