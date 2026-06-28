import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Certificates Settings Tab

struct CertificatesSettingsView: View {
    @State private var model = CertificateLifecycleModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Certificates")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.ghostTextPrimary)
                    Text("""
                    Network Proxy mode requires a local CA certificate to decrypt TLS traffic. \
                    The CA key is stored in your Keychain.
                    """)
                        .font(.system(size: 13))
                        .foregroundColor(.ghostTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                CertificateAuthoritySection(model: model)
            }
            .padding(24)
        }
        .background(Color.ghostBase)
        .onAppear { model.refresh() }
    }
}

// MARK: - Shared Authority Section

struct CertificateAuthoritySection: View {
    typealias Action = CertificateLifecycleModel.Action

    let model: CertificateLifecycleModel

    @State private var confirmingAction: Action?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            CertificateStageTimeline(currentStage: model.status.stageIndex)

            CertificateStatusCard(status: model.status)

            if let message = model.errorMessage {
                Label(message, systemImage: "xmark.octagon.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.ghostError)
                    .padding(.vertical, 4)
            }

            if model.status != .notGenerated {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: "Certificate Details", icon: "doc.text")
                    CertificateDetailTable(status: model.status)
                }
            }

            actionRow
        }
        .alert(
            alertTitle(for: confirmingAction),
            isPresented: Binding(
                get: { confirmingAction != nil },
                set: { if !$0 { confirmingAction = nil } }
            ),
            presenting: confirmingAction
        ) { action in
            Button(alertConfirmLabel(for: action), role: .destructive) { run(action) }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(alertMessage(for: action))
        }
    }

    @ViewBuilder private var actionRow: some View {
        HStack(spacing: 10) {
            switch model.status {
            case .notGenerated:
                primaryButton("Generate CA Certificate", systemImage: "lock.shield", action: .generate)
            case .generatedNotTrusted:
                primaryButton("Install & Trust in Keychain", systemImage: "lock.shield", action: .installTrust)
                exportButton
                destructiveButton("Remove CA", action: .remove)
            case .installedTrusted:
                secondaryButton("Rotate CA", systemImage: "arrow.triangle.2.circlepath", action: .rotate)
                exportButton
                destructiveButton("Remove CA & Revoke Trust", action: .remove)
            }

            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 4)
            }
        }
    }

    // MARK: - Buttons

    private func primaryButton(_ title: String, systemImage: String, action: Action) -> some View {
        Button {
            run(action)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(GhostPrimaryButtonStyle())
        .disabled(model.isBusy)
    }

    private func secondaryButton(_ title: String, systemImage: String, action: Action) -> some View {
        Button {
            confirmingAction = action
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .tint(.ghostAccent)
        .disabled(model.isBusy)
    }

    private func destructiveButton(_ title: String, action: Action) -> some View {
        Button(role: .destructive) {
            confirmingAction = action
        } label: {
            Text(title)
        }
        .buttonStyle(.bordered)
        .tint(.ghostError)
        .disabled(model.isBusy)
    }

    private var exportButton: some View {
        Button {
            exportCertificate()
        } label: {
            Label("Export Certificate (.pem)", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)
        .disabled(model.isBusy)
    }

    private func alertTitle(for action: Action?) -> String {
        switch action {
        case .rotate: return "Rotate CA?"
        case .remove: return "Remove CA?"
        case .generate, .installTrust, .none: return ""
        }
    }

    private func alertConfirmLabel(for action: Action) -> String {
        action == .rotate ? "Rotate" : "Remove"
    }

    private func alertMessage(for action: Action) -> String {
        switch action {
        case .rotate:
            return """
            A new key replaces the old trust anchor. Leaf certificates already issued become invalid. \
            macOS will prompt for your password.
            """
        case .remove:
            return """
            Deletes the CA and private key from your Keychain and revokes the trust anchor. \
            Network Proxy mode will stop working. Captured data is not affected.
            """
        case .generate, .installTrust:
            return ""
        }
    }

    // MARK: - Actions

    private func run(_ action: Action) {
        Task {
            switch action {
            case .generate: await model.generate()
            case .installTrust: await model.installTrust()
            case .rotate: await model.rotate()
            case .remove: await model.remove()
            }
        }
    }

    private func exportCertificate() {
        guard let data = try? KeychainManager.default.loadCARootCertificate(),
              let pem = String(data: data, encoding: .utf8) else {
            model.errorMessage = "No certificate available to export."
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "APIGhost-CA.pem"
        panel.allowedContentTypes = [.x509Certificate]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try pem.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Alert Identifiable Bridge

extension CertificateLifecycleModel.Action: Identifiable {
    var id: Self { self }
}
