import SwiftUI

struct InterceptModeSection: View {
    @State private var interceptMode: InterceptMode = AppState.shared.interceptMode
    @State private var caStatus: CertificateAuthorityManager.TrustStatus = CertificateAuthorityManager.default.status()

    private var needsCertificateSetup: Bool {
        interceptMode == .networkProxy && caStatus != .installedTrusted
    }

    var body: some View {
        GroupBox(label: SettingsSectionHeader(title: "Interception Mode", icon: "dot.radiowaves.left.and.right")) {
            VStack(alignment: .leading, spacing: 12) {
                Text("How APIGhost captures API traffic. Network Proxy needs a trusted local CA.")
                    .font(.system(size: 11))
                    .foregroundColor(.ghostTextMuted)

                Picker("", selection: $interceptMode) {
                    ForEach(InterceptMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: interceptMode) { _, newValue in
                    AppState.shared.interceptMode = newValue
                    caStatus = CertificateAuthorityManager.default.status()
                }

                if needsCertificateSetup {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.ghostWarning)
                        Text("Network Proxy needs a trusted CA certificate.")
                            .font(.system(size: 12))
                            .foregroundColor(.ghostTextSecondary)
                        Spacer()
                        Button("Set Up Certificate") {
                            NotificationCenter.default.post(name: .openSettingsToTab, object: SettingsTab.certificates)
                        }
                        .buttonStyle(.bordered)
                        .tint(.ghostAccentSoft)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(Color.ghostWarning.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.ghostWarning.opacity(0.25), lineWidth: 1)
                    )
                    .cornerRadius(6)
                }
            }
            .padding(16)
        }
        .backgroundStyle(Color.ghostSurface)
        .onAppear {
            interceptMode = AppState.shared.interceptMode
            caStatus = CertificateAuthorityManager.default.status()
        }
    }
}
