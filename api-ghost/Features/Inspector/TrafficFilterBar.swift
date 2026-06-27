//
//  TrafficFilterBar.swift
//  api-ghost
//
//  Filter bar for traffic list with domain, method, status, and search filters
//

import SwiftUI

// MARK: - Traffic Filter Bar

struct TrafficFilterBar: View {
    let domains: [String]
    @Binding var selectedDomain: String?
    @Binding var selectedMethod: String?
    @Binding var selectedStatus: String?
    @Binding var searchText: String
    let onClearFilters: () -> Void

    @FocusState private var isSearchFocused: Bool

    private let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"]
    private let statusCategories = ["2xx", "3xx", "4xx", "5xx"]

    var body: some View {
        HStack(spacing: 12) {
            // Domain filter
            FilterDropdown(
                title: "Domain",
                selection: $selectedDomain,
                options: domains.map { ($0, $0) }
            )

            // Method filter
            FilterDropdown(
                title: "Method",
                selection: $selectedMethod,
                options: methods.map { ($0, $0) }
            )

            // Status filter
            FilterDropdown(
                title: "Status",
                selection: $selectedStatus,
                options: statusCategories.map { ($0, $0) }
            )

            // Search field
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

            // Clear filters button
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.ghostSurface)
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            isSearchFocused = true
        }
    }

    private var hasActiveFilters: Bool {
        selectedDomain != nil || selectedMethod != nil || selectedStatus != nil || !searchText.isEmpty
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
                Text(selection ?? title)
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
}

// MARK: - Preview

#Preview {
    TrafficFilterBar(
        domains: ["api.example.com", "cdn.example.com", "auth.example.com"],
        selectedDomain: .constant(nil),
        selectedMethod: .constant(nil),
        selectedStatus: .constant(nil),
        searchText: .constant("")
    ) {}
    .preferredColorScheme(.dark)
    .frame(width: 800)
}
