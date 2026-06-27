import SwiftUI

// MARK: - GraphQL Operation Type

enum GraphQLOperationKind {
    case query
    case mutation
    case subscription
    case unknown

    init(rawValue: String?) {
        switch rawValue?.lowercased() {
        case "query": self = .query
        case "mutation": self = .mutation
        case "subscription": self = .subscription
        default: self = .unknown
        }
    }

    var label: String {
        switch self {
        case .query: return "query"
        case .mutation: return "mutation"
        case .subscription: return "subscription"
        case .unknown: return "operation"
        }
    }

    var color: Color {
        switch self {
        case .query: return .ghostAccent
        case .mutation: return .ghostSuccess
        case .subscription: return .ghostWarning
        case .unknown: return .ghostTextSecondary
        }
    }
}

// MARK: - Operation Type Badge

struct GraphQLOperationBadge: View {
    let operationType: String?

    private var kind: GraphQLOperationKind { GraphQLOperationKind(rawValue: operationType) }

    var body: some View {
        Text(kind.label)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(kind.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(kind.color.opacity(0.1))
            .cornerRadius(3)
    }
}

// MARK: - GraphQL Meta Row

struct GraphQLMetaRow: View {
    let operationName: String?
    let operationType: String?

    var body: some View {
        if let operationName = operationName, !operationName.isEmpty {
            HStack(spacing: 8) {
                Text("GraphQL")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.ghostAccent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.ghostAccentMuted)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.ghostAccent.opacity(0.2), lineWidth: 1)
                    )
                    .cornerRadius(3)

                Text(operationName)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.ghostTextPrimary)
                    .textSelection(.enabled)

                if let operationType = operationType, !operationType.isEmpty {
                    Text(operationType.lowercased())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.ghostTextMuted)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.ghostAccent.opacity(0.04))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.ghostAccent.opacity(0.1)),
                alignment: .bottom
            )
        }
    }
}

// MARK: - Compact Inline Tag

struct GraphQLInlineTag: View {
    let operationName: String?
    let operationType: String?

    var body: some View {
        if let operationName = operationName, !operationName.isEmpty {
            HStack(spacing: 4) {
                GraphQLOperationBadge(operationType: operationType)
                Text(operationName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.ghostAccent)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        GraphQLMetaRow(operationName: "HomeTimeline", operationType: "query")
        GraphQLMetaRow(operationName: "DeleteTweet", operationType: "mutation")
        GraphQLInlineTag(operationName: "UserProfile", operationType: "query")
    }
    .padding()
    .background(Color.ghostBase)
    .preferredColorScheme(.dark)
}
