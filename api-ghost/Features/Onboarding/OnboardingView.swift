import SwiftUI

// MARK: - Onboarding Step

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case complete = 1
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @State private var currentStep: OnboardingStep = .welcome

    let onComplete: () -> Void

    var body: some View {
        ZStack {
            Color.ghostBase.ignoresSafeArea()

            VStack(spacing: 0) {
                OnboardingProgressIndicator(currentStep: currentStep)
                    .padding(.top, 40)
                    .padding(.bottom, 32)

                Group {
                    switch currentStep {
                    case .welcome:
                        WelcomeStepView {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentStep = .complete
                            }
                        }
                    case .complete:
                        OnboardingCompleteView {
                            completeOnboarding()
                        }
                    }
                }
                .frame(maxWidth: 600)
                .padding(.horizontal, 40)

                Spacer()
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    private func completeOnboarding() {
        Preferences.shared.hasCompletedOnboarding = true
        onComplete()
    }
}

// MARK: - Progress Indicator

struct OnboardingProgressIndicator: View {
    let currentStep: OnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step.rawValue <= currentStep.rawValue ? Color.ghostAccent : Color.ghostBorder)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Welcome Step

struct WelcomeStepView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.ghostAccentMuted)
                    .frame(width: 100, height: 100)

                Image(systemName: "network")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(.ghostAccent)
            }

            VStack(spacing: 12) {
                Text("Welcome to APIGhost")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.ghostTextPrimary)

                Text("Capture, inspect, and analyze API traffic from any web application")
                    .font(.system(size: 16))
                    .foregroundColor(.ghostTextSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "eye.fill",
                    title: "Capture Traffic",
                    description: "See every API call your browser makes in real-time"
                )

                FeatureRow(
                    icon: "doc.text.magnifyingglass",
                    title: "Inspect Requests",
                    description: "View headers, bodies, and response data with syntax highlighting"
                )

                FeatureRow(
                    icon: "map.fill",
                    title: "Map Endpoints",
                    description: "Automatically discover and organize API endpoints"
                )

                FeatureRow(
                    icon: "square.and.arrow.up.fill",
                    title: "Export Data",
                    description: "Export captures for analysis or LLM processing"
                )
            }
            .padding(.top, 16)

            Button(action: onContinue) {
                Text("Get Started")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ghostBase)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.ghostAccent)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
        }
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.ghostAccent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ghostTextPrimary)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.ghostTextSecondary)
            }
        }
    }
}

// MARK: - Onboarding Complete

struct OnboardingCompleteView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.ghostSuccess.opacity(0.2))
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.ghostSuccess)
            }

            VStack(spacing: 12) {
                Text("You're All Set!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.ghostTextPrimary)

                Text("APIGhost is ready to capture API traffic. Browse to any website and watch the requests flow in.")
                    .font(.system(size: 16))
                    .foregroundColor(.ghostTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onStart) {
                Text("Start Exploring")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ghostBase)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.ghostAccent)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView {}
        .preferredColorScheme(.dark)
        .frame(width: 800, height: 600)
}
