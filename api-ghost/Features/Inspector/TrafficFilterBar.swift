import SwiftUI

// MARK: - Traffic Filter Bar

struct TrafficFilterBar: View {
    let domains: [String]
    var tabOptions: [(value: String, label: String)] = []
    @Binding var selectedDomain: String?
    @Binding var selectedMethod: String?
    @Binding var selectedStatus: String?
    @Binding var selectedTab: String?
    @Binding var searchText: String
    let onClearFilters: () -> Void
    var onCollapsePanel: (() -> Void)?

    @FocusState private var isSearchFocused: Bool

    private let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"]
    private let statusCategories = ["2xx", "3xx", "4xx", "5xx"]

    var body: some View {
        HStack(spacing: 12) {
            FilterDropdown(
                title: "Domain",
                selection: $selectedDomain,
                options: domains.map { ($0, $0) }
            )

            FilterDropdown(
                title: "Method",
                selection: $selectedMethod,
                options: methods.map { ($0, $0) }
            )

            FilterDropdown(
                title: "Status",
                selection: $selectedStatus,
                options: statusCategories.map { ($0, $0) }
            )

            if !tabOptions.isEmpty {
                FilterDropdown(
                    title: "Tab",
                    selection: $selectedTab,
                    options: tabOptions
                )
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.ghostTextMuted)

                TextField("Search path or body...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.ghostTextPrimary)
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }, label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.ghostTextMuted)
                    })
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.ghostInput)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSearchFocused ? Color.ghostAccent : Color.ghostBorder, lineWidth: 1)
            )
            .frame(minWidth: 150, maxWidth: 250)

            Spacer()

            if hasActiveFilters {
                Button(action: onClearFilters) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Clear Filters")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.ghostTextSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.ghostSurfaceRaised)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.ghostBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            if let onCollapsePanel {
                Button(action: onCollapsePanel) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.ghostTextSecondary)
                        .frame(width: 24, height: 24)
                        .background(Color.ghostSurfaceRaised)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Collapse traffic panel")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.ghostSurface)
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            isSearchFocused = true
        }
    }

    private var hasActiveFilters: Bool {
        selectedDomain != nil
            || selectedMethod != nil
            || selectedStatus != nil
            || selectedTab != nil
            || !searchText.isEmpty
    }
}

// MARK: - Filter Dropdown

struct FilterDropdown: View {
    let title: String
    @Binding var selection: String?
    let options: [(value: String, label: String)]

    var body: some View {
        Menu {
            Button("All \(title)s") {
                selection = nil
            }

            Divider()

            ForEach(options, id: \.value) { option in
                Button(option.label) {
                    selection = option.value
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectionLabel)
                    .font(.system(size: 12))
                    .foregroundColor(selection != nil ? .ghostAccent : .ghostTextSecondary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.ghostTextMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selection != nil ? Color.ghostAccentMuted : Color.ghostSurfaceRaised)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selection != nil ? Color.ghostAccent.opacity(0.5) : Color.ghostBorder, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var selectionLabel: String {
        guard let selection else { return title }
        return options.first { $0.value == selection }?.label ?? selection
    }
}

// MARK: - Preview

#Preview {
    TrafficFilterBar(
        domains: ["api.example.com", "cdn.example.com", "auth.example.com"],
        selectedDomain: .constant(nil),
        selectedMethod: .constant(nil),
        selectedStatus: .constant(nil),
        selectedTab: .constant(nil),
        searchText: .constant(""),
        onClearFilters: {},
        onCollapsePanel: nil
    )
    .preferredColorScheme(.dark)
    .frame(width: 800)
}
