import SwiftUI
import AppKit

// MARK: - SQL Editor View

struct SQLEditorView: View {
    @Bindable var viewModel: SQLViewModel
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            QuickQueryBar(viewModel: viewModel)

            Divider()
                .background(Color.ghostBorder)

            if viewModel.showQueryBuilder {
                QueryBuilderPanel(viewModel: viewModel)

                Divider()
                    .background(Color.ghostBorder)
            }

            VStack(spacing: 0) {
                EditorHeader(viewModel: viewModel)

                SQLTextEditor(
                    text: $viewModel.queryText,
                    isFocused: $isEditorFocused
                )
                .frame(minHeight: 80, maxHeight: .infinity)

                EditorFooter(
                    viewModel: viewModel
                ) { viewModel.executeQuery() }
            }
            .background(Color.ghostBase)
        }
    }
}

// MARK: - Quick Query Bar

struct QuickQueryBar: View {
    @Bindable var viewModel: SQLViewModel
    @State private var hoveredQuery: QuickQueryType?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.ghostAccent)

                Text("Quick:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.ghostTextSecondary)

                ForEach(QuickQueryType.allCases) { queryType in
                    QuickQueryButton(
                        queryType: queryType,
                        isHovered: hoveredQuery == queryType
                    ) { viewModel.executeQuickQuery(queryType) }
                    .onHover { hovering in
                        hoveredQuery = hovering ? queryType : nil
                    }
                }

                Spacer()

                Button(action: { viewModel.showQueryBuilder.toggle() }, label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10))
                        Text("Builder")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(viewModel.showQueryBuilder ? .ghostAccent : .ghostTextSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(viewModel.showQueryBuilder ? Color.ghostAccentMuted : Color.ghostSurfaceRaised)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                viewModel.showQueryBuilder ? Color.ghostAccent.opacity(0.5) : Color.ghostBorder,
                                lineWidth: 1
                            )
                    )
                })
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.ghostSurface)
    }
}

struct QuickQueryButton: View {
    let queryType: QuickQueryType
    let isHovered: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: queryType.icon)
                    .font(.system(size: 10))
                Text(queryType.rawValue)
                    .font(.system(size: 11))
            }
            .foregroundColor(isHovered ? .ghostAccent : .ghostTextSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isHovered ? Color.ghostAccentMuted : Color.ghostSurfaceRaised)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovered ? Color.ghostAccent.opacity(0.5) : Color.ghostBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(queryType.description)
    }
}

// MARK: - Editor Header

struct EditorHeader: View {
    @Bindable var viewModel: SQLViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 11))
                .foregroundColor(.ghostTextMuted)

            Text("SQL Editor")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.ghostTextPrimary)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .font(.system(size: 10))
                    .foregroundColor(.ghostTextMuted)

                Text("Limit: \(viewModel.queryRowLimit)")
                    .font(.system(size: 10))
                    .foregroundColor(.ghostTextMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.ghostSurfaceRaised)
            .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.ghostSurface.opacity(0.5))
    }
}

// MARK: - Editor Footer

struct EditorFooter: View {
    @Bindable var viewModel: SQLViewModel
    let onExecute: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onExecute) {
                HStack(spacing: 6) {
                    if viewModel.isExecuting {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                    }
                    Text("Execute")
                        .font(.system(size: 12, weight: .medium))

                    Text("Cmd+Return")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.ghostTextMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.ghostSurfaceRaised)
                        .cornerRadius(3)
                }
                .foregroundColor(.ghostTextPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.ghostAccent)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isExecuting || viewModel.queryText.isEmpty)
            .opacity(viewModel.queryText.isEmpty ? 0.5 : 1)
            .keyboardShortcut(.return, modifiers: .command)

            Button(action: { viewModel.formatQuery() }, label: {
                HStack(spacing: 4) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 10))
                    Text("Format")
                        .font(.system(size: 11))
                }
                .foregroundColor(.ghostTextSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.ghostSurfaceRaised)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.ghostBorder, lineWidth: 1)
                )
            })
            .buttonStyle(.plain)
            .disabled(viewModel.queryText.isEmpty)

            Button(action: { viewModel.clearQuery() }, label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                    Text("Clear")
                        .font(.system(size: 11))
                }
                .foregroundColor(.ghostTextSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.ghostSurfaceRaised)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.ghostBorder, lineWidth: 1)
                )
            })
            .buttonStyle(.plain)
            .disabled(viewModel.queryText.isEmpty)

            Spacer()

            if let error = viewModel.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.ghostError)

                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.ghostError)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.ghostSurface)
    }
}

// MARK: - SQL Text Editor with Syntax Highlighting

struct SQLTextEditor: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    @State private var highlightedText: AttributedString?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let highlighted = highlightedText, !text.isEmpty {
                Text(highlighted)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.clear)
                .scrollContentBackground(.hidden)
                .padding(8)
                .focused($isFocused)
                .onChange(of: text) { _, newValue in
                    highlightedText = highlightSQL(newValue)
                }
                .onAppear {
                    highlightedText = highlightSQL(text)
                }

            if text.isEmpty {
                Text("Enter SQL query...")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.ghostTextMuted)
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.ghostInput)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? Color.ghostAccent : Color.ghostBorder, lineWidth: 1)
        )
        .cornerRadius(6)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - SQL Syntax Highlighting

    private func highlightSQL(_ sql: String) -> AttributedString {
        SQLHighlighter.highlight(sql)
    }
}

// MARK: - Preview

#Preview {
    SQLEditorView(viewModel: SQLViewModel())
        .preferredColorScheme(.dark)
        .frame(width: 700, height: 400)
}
