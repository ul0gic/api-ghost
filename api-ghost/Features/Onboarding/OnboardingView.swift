import SwiftUI

// MARK: - Onboarding Step

enum OnboardingStep: Int, CaseIterable {
    case modeSelection = 0
    case certificates = 1
}

// MARK: - Onboarding View

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var step: OnboardingStep = .modeSelection
    @State private var selectedMode: InterceptMode?
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        ZStack {
            Color.ghostBase.ignoresSafeArea()

            Group {
                switch step {
                case .modeSelection:
                    ModeSelectionStep(selectedMode: $selectedMode, onContinue: continueFromModeSelection, onSkip: skip)
                case .certificates:
                    CertificateOnboardingStep(onBack: { advance(to: .modeSelection) }, onFinish: finish)
                }
            }
            .frame(maxWidth: 760)
            .padding(40)
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    private func continueFromModeSelection() {
        guard let mode = selectedMode else { return }
        AppState.shared.interceptMode = mode
        if mode == .networkProxy {
            advance(to: .certificates)
        } else {
            finish()
        }
    }

    private func skip() {
        AppState.shared.interceptMode = .jsInjection
        finish()
    }

    private func advance(to next: OnboardingStep) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            step = next
        }
    }

    private func finish() {
        Preferences.shared.hasCompletedOnboarding = true
        onComplete()
    }
}

// MARK: - Mode Selection Step

private struct ModeSelectionStep: View {
    @Binding var selectedMode: InterceptMode?
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.ghostAccentMuted)
                    .frame(width: 56, height: 56)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 26, weight: .light))
                    .foregroundColor(.ghostAccent)
            }
            .padding(.bottom, 24)

            Text("Choose your capture mode")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.ghostTextPrimary)
            Text("APIGhost can capture API traffic two ways. You can change this later in Settings.")
                .font(.system(size: 14))
                .foregroundColor(.ghostTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.bottom, 40)

            HStack(alignment: .top, spacing: 16) {
                ForEach(InterceptModeDescriptor.all) { descriptor in
                    ModeCard(descriptor: descriptor, isSelected: selectedMode == descriptor.mode) {
                        selectedMode = descriptor.mode
                    }
                }
            }

            HStack {
                Button("I'll decide later", action: onSkip)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.ghostTextMuted)
                Spacer()
                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(selectedMode == nil ? .ghostTextMuted : .ghostBase)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 9)
                        .background(selectedMode == nil ? Color.ghostSurfaceRaised : Color.ghostAccent)
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .disabled(selectedMode == nil)
            }
            .padding(.top, 32)
        }
    }
}

// MARK: - Certificate Onboarding Step

private struct CertificateOnboardingStep: View {
    let onBack: () -> Void
    let onFinish: () -> Void

    @State private var model = CertificateLifecycleModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up the CA certificate")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.ghostTextPrimary)
                Text("""
                Network Proxy needs a local CA to decrypt TLS. Generate it, then install and trust it — \
                macOS prompts for your password.
                """)
                    .font(.system(size: 13))
                    .foregroundColor(.ghostTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                CertificateAuthoritySection(model: model)
            }

            HStack {
                Button("Back", action: onBack)
                    .buttonStyle(.bordered)
                Spacer()
                Button(action: onFinish) {
                    Text(model.status == .installedTrusted ? "Finish" : "Finish — set up later")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.ghostBase)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 9)
                        .background(Color.ghostAccent)
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { model.refresh() }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView {}
        .preferredColorScheme(.dark)
        .frame(width: 900, height: 700)
}
