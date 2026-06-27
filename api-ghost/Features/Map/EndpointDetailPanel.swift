import SwiftUI

// MARK: - Endpoint Detail Panel

struct EndpointDetailPanel: View {
    let endpoint: APIEndpoint
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Endpoint Details")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ghostTextPrimary)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.ghostTextMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.ghostSurface)

            Divider()
                .background(Color.ghostBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    requestSection
                    Divider().background(Color.ghostBorder)
                    statisticsSection
                    contentTypesSection
                    examplePathsSection
                }
                .padding(12)
            }
        }
        .background(Color.ghostSurface)
    }

    private var requestSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MapMethodBadge(method: endpoint.method, size: .normal)
                Text("Request")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.ghostTextSecondary)
            }

            Text(endpoint.normalizedPath)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.ghostTextPrimary)
                .textSelection(.enabled)
        }
    }

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Statistics")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.ghostTextSecondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                statItem(label: "Hit Count", value: "\(endpoint.hitCount)")
                let statusStr = endpoint.statusCodes.sorted().map(String.init).joined(separator: ", ")
                statItem(label: "Status Codes", value: statusStr)
            }
        }
    }

    @ViewBuilder private var contentTypesSection: some View {
        if !endpoint.contentTypes.isEmpty {
            Divider().background(Color.ghostBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Content Types")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.ghostTextSecondary)

                ForEach(Array(endpoint.contentTypes).sorted(), id: \.self) { contentType in
                    Text(contentType)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.ghostTextPrimary)
                }
            }
        }
    }

    @ViewBuilder private var examplePathsSection: some View {
        if !endpoint.examplePaths.isEmpty {
            Divider().background(Color.ghostBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Example Paths")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.ghostTextSecondary)

                ForEach(endpoint.examplePaths, id: \.self) { path in
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.ghostTextPrimary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.ghostTextMuted)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.ghostTextPrimary)
                .lineLimit(1)
        }
    }
}
