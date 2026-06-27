import SwiftUI

// MARK: - Categories Section

struct FilterCategoriesSection: View {
    @Bindable var store: FilterCategoryStore

    var body: some View {
        GroupBox(label: SettingsSectionHeader(title: "Prebuilt Filter Categories", icon: "square.stack.3d.up")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Noise categories applied before capture. A matched request is dropped entirely.")
                    .font(.system(size: 11))
                    .foregroundColor(.ghostTextMuted)

                ForEach(store.categories) { category in
                    FilterCategoryCard(category: category, store: store)
                }
            }
            .padding(12)
        }
        .backgroundStyle(Color.ghostSurface)
    }
}

// MARK: - Category Card

struct FilterCategoryCard: View {
    let category: FilterCategory
    @Bindable var store: FilterCategoryStore

    @State private var isExpanded: Bool = false

    private var isEnabled: Bool { store.isCategoryEnabled(category) }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                Divider().background(Color.ghostBorder)
                rulesList
            }
        }
        .background(Color.ghostSurfaceRaised)
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.ghostBorder, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: { isExpanded.toggle() }, label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.ghostTextMuted)
                    .frame(width: 14)
            })
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(category.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.ghostTextPrimary)
                    DefaultStateBadge(defaultOn: store.isCategoryDefaultOn(category))
                }
                Text(category.description)
                    .font(.system(size: 11))
                    .foregroundColor(.ghostTextMuted)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(store.enabledRuleCount(in: category))/\(category.rules.count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.ghostTextMuted)

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { store.setCategory(category, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(.ghostAccent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { isExpanded.toggle() }
    }

    private var rulesList: some View {
        VStack(spacing: 0) {
            ForEach(category.rules) { rule in
                FilterRuleRow(rule: rule, store: store, categoryEnabled: isEnabled)
                if rule.id != category.rules.last?.id {
                    Divider().background(Color.ghostBorder.opacity(0.4))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Rule Row

struct FilterRuleRow: View {
    let rule: FilterRule
    @Bindable var store: FilterCategoryStore
    let categoryEnabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            RuleTypeBadge(type: rule.type)

            Text(rule.pattern)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(categoryEnabled ? .ghostTextSecondary : .ghostTextMuted)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(rule.isCustom ? "Custom" : "Default")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.ghostTextMuted)

            Toggle("", isOn: Binding(
                get: { store.isRuleEnabled(rule) },
                set: { store.setRule(rule, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(.ghostAccent)
            .disabled(!categoryEnabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .opacity(categoryEnabled ? 1 : 0.5)
    }
}

// MARK: - Badges

struct DefaultStateBadge: View {
    let defaultOn: Bool

    var body: some View {
        Text(defaultOn ? "default on" : "default off")
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(defaultOn ? .ghostSuccess : .ghostWarning)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background((defaultOn ? Color.ghostSuccess : Color.ghostWarning).opacity(0.12))
            .cornerRadius(3)
    }
}

struct RuleTypeBadge: View {
    let type: FilterRuleType

    private var label: String {
        switch type {
        case .domainExact, .domainWildcard: return "domain"
        case .pathContains, .pathPrefix: return "path"
        case .pathRegex: return "regex"
        case .contentType: return "type"
        case .statusCode: return "status"
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.ghostTextMuted)
            .frame(width: 48, alignment: .leading)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        FilterCategoriesSection(store: FilterCategoryStore())
            .padding()
    }
    .background(Color.ghostBase)
    .preferredColorScheme(.dark)
    .frame(width: 560, height: 600)
}
