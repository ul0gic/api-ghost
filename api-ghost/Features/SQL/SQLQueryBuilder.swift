import SwiftUI

// MARK: - Query Builder Panel

struct QueryBuilderPanel: View {
    @Bindable var viewModel: SQLViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            builderHeader
            filterList
            builderFooter
        }
        .padding(12)
        .background(Color.ghostSurface.opacity(0.5))
    }

    private var builderHeader: some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 11))
                .foregroundColor(.ghostAccent)

            Text("Query Builder")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.ghostTextPrimary)

            Spacer()

            Picker("Time", selection: $viewModel.timeRangeFilter) {
                ForEach(TimeRangeFilter.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            if !viewModel.queryBuilderFilters.isEmpty || viewModel.timeRangeFilter != .all {
                Button(action: { viewModel.clearFilters() }, label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark").font(.system(size: 9))
                        Text("Clear").font(.system(size: 11))
                    }
                    .foregroundColor(.ghostTextSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.ghostSurfaceRaised)
                    .cornerRadius(4)
                })
                .buttonStyle(.plain)
            }
        }
    }

    private var filterList: some View {
        VStack(spacing: 8) {
            ForEach(Array(viewModel.queryBuilderFilters.enumerated()), id: \.element.id) { index, filter in
                QueryFilterRow(
                    filter: Binding(
                        get: { viewModel.queryBuilderFilters[index] },
                        set: { viewModel.queryBuilderFilters[index] = $0 }
                    )
                ) { viewModel.removeFilter(filter) }
            }
        }
    }

    private var builderFooter: some View {
        HStack {
            Button(action: { viewModel.addFilter() }, label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 10))
                    Text("Add Filter").font(.system(size: 11))
                }
                .foregroundColor(.ghostAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.ghostAccentMuted)
                .cornerRadius(6)
            })
            .buttonStyle(.plain)

            Spacer()

            Button(action: { viewModel.executeQueryFromFilters() }, label: {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill").font(.system(size: 10))
                    Text("Build & Execute").font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.ghostTextPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.ghostAccent)
                .cornerRadius(6)
            })
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Query Filter Row

struct QueryFilterRow: View {
    @Binding var filter: QueryBuilderFilter
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("Field", selection: $filter.field) {
                ForEach(QueryFilterField.allCases, id: \.self) { field in
                    Text(field.rawValue).tag(field)
                }
            }
            .labelsHidden()
            .frame(width: 140)

            Picker("Operation", selection: $filter.operation) {
                ForEach(operationsForField(filter.field), id: \.self) { op in
                    Text(op.rawValue).tag(op)
                }
            }
            .labelsHidden()
            .frame(width: 100)

            TextField("Value", text: $filter.value)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.ghostError)
            }
            .buttonStyle(.plain)
        }
    }

    private func operationsForField(_ field: QueryFilterField) -> [QueryFilterOperation] {
        switch field {
        case .sizeMin, .durationMin:
            return [.greaterThan]
        case .sizeMax, .durationMax:
            return [.lessThan]
        case .statusCode:
            return [.equals, .greaterThan, .lessThan]
        case .method:
            return [.equals]
        default:
            return [.contains, .equals, .startsWith, .endsWith, .like]
        }
    }
}
