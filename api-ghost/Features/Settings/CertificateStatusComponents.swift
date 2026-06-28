import SwiftUI

// MARK: - Trust Status Presentation

extension CertificateAuthorityManager.TrustStatus {
    var stageIndex: Int {
        switch self {
        case .notGenerated: return 0
        case .generatedNotTrusted: return 1
        case .installedTrusted: return 2
        }
    }

    var statusTitle: String {
        switch self {
        case .notGenerated: return "No CA certificate generated"
        case .generatedNotTrusted: return "CA generated — not yet trusted"
        case .installedTrusted: return "CA installed and trusted"
        }
    }

    var statusDescription: String {
        switch self {
        case .notGenerated:
            return "Generate a local CA to enable Network Proxy mode. The private key stays in your Keychain."
        case .generatedNotTrusted:
            return """
            The CA key is in your Keychain. Install and trust it in macOS before Network Proxy works — \
            macOS prompts for your password.
            """
        case .installedTrusted:
            return "Network Proxy mode is ready. APIGhost decrypts TLS using this CA, trusted by macOS frameworks only."
        }
    }

    var accent: Color {
        switch self {
        case .notGenerated: return .ghostTextMuted
        case .generatedNotTrusted: return .ghostWarning
        case .installedTrusted: return .ghostSuccess
        }
    }

    var symbol: String {
        switch self {
        case .notGenerated: return "circle"
        case .generatedNotTrusted: return "exclamationmark.triangle.fill"
        case .installedTrusted: return "checkmark.seal.fill"
        }
    }
}

// MARK: - Stage Timeline

struct CertificateStageTimeline: View {
    let currentStage: Int

    private struct Stage {
        let symbol: String
        let title: String
        let detail: String
    }

    private let stages: [Stage] = [
        Stage(symbol: "circle", title: "Not Generated", detail: "No CA exists yet"),
        Stage(symbol: "key.fill", title: "Generated", detail: "Key in Keychain, not trusted"),
        Stage(symbol: "checkmark", title: "Installed & Trusted", detail: "Ready for Network mode")
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                stageNode(stage, isCurrent: index == currentStage, isReached: index <= currentStage)
                if index < stages.count - 1 {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                        .foregroundColor(.ghostTextMuted)
                }
            }
        }
    }

    private func stageNode(_ stage: Stage, isCurrent: Bool, isReached: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: stage.symbol)
                .font(.system(size: 18))
                .foregroundColor(isCurrent ? .ghostAccent : .ghostTextSecondary)
                .opacity(isReached ? 1 : 0.35)
            Text(stage.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isCurrent ? .ghostTextPrimary : .ghostTextSecondary)
                .opacity(isReached ? 1 : 0.5)
            Text(stage.detail)
                .font(.system(size: 11))
                .foregroundColor(.ghostTextMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(isCurrent ? Color.ghostAccentMuted : Color.ghostSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCurrent ? Color.ghostAccent : Color.ghostBorder, lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

// MARK: - Status Card

struct CertificateStatusCard: View {
    let status: CertificateAuthorityManager.TrustStatus

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: status.symbol)
                .font(.system(size: 20))
                .foregroundColor(status.accent)
                .frame(width: 44, height: 44)
                .background(status.accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(status.statusTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(status == .notGenerated ? .ghostTextPrimary : status.accent)
                Text(status.statusDescription)
                    .font(.system(size: 12))
                    .foregroundColor(.ghostTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(status == .notGenerated ? Color.ghostSurface : status.accent.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(status == .notGenerated ? Color.ghostBorder : status.accent.opacity(0.25), lineWidth: 1)
        )
        .cornerRadius(10)
    }
}

// MARK: - Detail Table

struct CertificateDetailTable: View {
    let status: CertificateAuthorityManager.TrustStatus

    private struct Row: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let valueColor: Color
    }

    private var rows: [Row] {
        [
            Row(label: "Subject", value: "APIGhost MITM Root", valueColor: .ghostTextSecondary),
            Row(label: "Key Type", value: "EC P-256 (secp256r1)", valueColor: .ghostTextSecondary),
            Row(label: "Key Storage", value: "Keychain (corelift.api-ghost)", valueColor: .ghostAccent),
            Row(label: "Validity", value: "10 years from generation", valueColor: .ghostTextSecondary),
            Row(label: "Trust Status", value: trustStatusText, valueColor: status.accent)
        ]
    }

    private var trustStatusText: String {
        status == .installedTrusted ? "Trusted in System Keychain" : "Not trusted in System Keychain"
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 12) {
                    Text(row.label)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.ghostTextMuted)
                        .frame(width: 120, alignment: .leading)
                    Text(row.value)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(row.valueColor)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                if index < rows.count - 1 {
                    Divider().overlay(Color.ghostBorder)
                }
            }
        }
        .background(Color.ghostSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.ghostBorder, lineWidth: 1)
        )
        .cornerRadius(8)
    }
}
