import SwiftUI

// MARK: - Endpoint Detail Panel

struct EndpointDetailPanel: View {
    let detail: EndpointDetail?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let detail {
                header(detail)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        rollupSection(detail)
                        if !detail.statusCounts.isEmpty {
                            statusDistributionSection(detail)
                        }
                        if !detail.examplePaths.isEmpty {
                            observedSection(detail)
                        }
                        if !detail.contentTypes.isEmpty {
                            contentTypesSection(detail)
                        }
                    }
                }
            } else {
                emptyState
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.ghostSurface)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 28))
                .foregroundColor(.ghostTextMuted)
            Text("Select an endpoint")
                .font(.system(size: 13))
                .foregroundColor(.ghostTextMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private func header(_ detail: EndpointDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let gqlType = detail.graphqlType {
                    GraphQLOpTypeBadge(type: gqlType)
                } else {
                    OpMethodBadge(method: detail.method)
                }
                Text(detail.title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.ghostTextPrimary)
                    .textSelection(.enabled)
                    .lineLimit(1)
            }
            Text("\(detail.host) · \(detail.summary)")
                .font(.system(size: 11))
                .foregroundColor(.ghostTextMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.ghostSurface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.ghostBorder).frame(height: 1)
        }
    }

    // MARK: - Rollup

    private func rollupSection(_ detail: EndpointDetail) -> some View {
        sectionContainer(label: "Rollup") {
            HStack(spacing: 8) {
                statCard(
                    value: "\(detail.hitCount)",
                    label: "Total requests",
                    color: .ghostAccent
                )
                statCard(
                    value: successRateText(detail),
                    label: "Success rate",
                    color: .ghostSuccess
                )
            }
        }
    }

    private func successRateText(_ detail: EndpointDetail) -> String {
        guard let rate = detail.successRate else { return "—" }
        return "\(Int((rate * 100).rounded()))%"
    }

    private func statCard(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.ghostTextMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.ghostSurfaceRaised)
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(Color.ghostBorder, lineWidth: 1)
        )
        .cornerRadius(6)
    }

    // MARK: - Status Distribution

    private func statusDistributionSection(_ detail: EndpointDetail) -> some View {
        let maxCount = detail.statusCounts.values.max() ?? 1
        return sectionContainer(label: "Status Distribution") {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(detail.sortedStatusCounts, id: \.code) { entry in
                    statusBar(code: entry.code, count: entry.count, maxCount: maxCount)
                }
            }
        }
    }

    private func statusBar(code: Int, count: Int, maxCount: Int) -> some View {
        let color = MapStatusPalette.color(for: code)
        return HStack(spacing: 8) {
            Text("\(code)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(color)
                .frame(width: 32, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ghostSurfaceRaised)
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * fraction(count, maxCount))
                }
            }
            .frame(height: 4)
            Text("\(count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.ghostTextMuted)
                .frame(width: 24, alignment: .trailing)
        }
    }

    private func fraction(_ count: Int, _ maxCount: Int) -> CGFloat {
        guard maxCount > 0 else { return 0 }
        return CGFloat(count) / CGFloat(maxCount)
    }

    // MARK: - Observed IDs

    private func observedSection(_ detail: EndpointDetail) -> some View {
        sectionContainer(label: "Observed Paths") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(detail.examplePaths, id: \.self) { path in
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.ghostTextSecondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
        }
    }

    // MARK: - Content Types

    private func contentTypesSection(_ detail: EndpointDetail) -> some View {
        sectionContainer(label: "Content Types") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(detail.contentTypes, id: \.self) { contentType in
                    Text(contentType)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.ghostTextSecondary)
                }
            }
        }
    }

    // MARK: - Section Container

    private func sectionContainer<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.ghostTextMuted)
                .tracking(0.8)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.ghostBorder).frame(height: 1)
        }
    }
}
