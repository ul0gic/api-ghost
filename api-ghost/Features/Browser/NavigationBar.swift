import SwiftUI

// MARK: - Navigation Bar

struct NavigationBar: View {
    @Bindable var viewModel: BrowserViewModel
    @FocusState private var urlFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            NavigationButtons(viewModel: viewModel)

            URLTextField(viewModel: viewModel, isFocused: $urlFieldFocused)

            RecordingIndicator()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.ghostSurface)
        .onReceive(NotificationCenter.default.publisher(for: .reloadPage)) { _ in
            viewModel.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusURLBar)) { _ in
            urlFieldFocused = true
        }
    }
}

// MARK: - Navigation Buttons

struct NavigationButtons: View {
    @Bindable var viewModel: BrowserViewModel

    var body: some View {
        HStack(spacing: 4) {
            NavButton(icon: "chevron.left", enabled: viewModel.canGoBack) {
                viewModel.goBack()
            }
            NavButton(icon: "chevron.right", enabled: viewModel.canGoForward) {
                viewModel.goForward()
            }
            NavButton(icon: "arrow.clockwise", enabled: true) {
                viewModel.reload()
            }
            NavButton(icon: "house", enabled: true) {
                viewModel.goHome()
            }
        }
    }
}

// MARK: - Nav Button

struct NavButton: View {
    let icon: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(enabled ? .ghostTextSecondary : .ghostTextMuted)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - URL Text Field

struct URLTextField: View {
    @Bindable var viewModel: BrowserViewModel
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.isLoading ? "arrow.triangle.2.circlepath" : "lock.fill")
                .font(.system(size: 12))
                .foregroundColor(.ghostTextMuted)
                .frame(width: 16)

            TextField("Enter URL", text: $viewModel.urlString)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.ghostTextPrimary)
                .focused(isFocused)
                .onSubmit {
                    viewModel.loadURL()
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.ghostSurfaceActive)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused.wrappedValue ? Color.ghostAccent : Color.ghostBorder, lineWidth: 1)
        )
    }
}

// MARK: - Recording Indicator

struct RecordingIndicator: View {
    @State private var isRecording: Bool = false
    @State private var pulseScale: CGFloat = 1.0

    private let trafficCapture = TrafficCapture.shared

    var body: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isRecording ? Color.ghostError : Color.ghostAccent)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulseScale)
                    .animation(
                        isRecording ?
                            Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true) :
                            .default,
                        value: pulseScale
                    )

                Text(isRecording ? "Stop Capture" : "Start Capture")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isRecording ? .ghostError : .ghostAccent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isRecording ? Color.ghostError.opacity(0.1) : Color.ghostAccentMuted)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.ghostError.opacity(0.5) : Color.ghostAccent.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            isRecording = AppState.shared.isRecording
            startPulseAnimation()
        }
    }

    private func toggleRecording() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isRecording.toggle()
        }

        if isRecording {
            trafficCapture.resumeCapture()
        } else {
            trafficCapture.pauseCapture()
        }

        startPulseAnimation()
    }

    private func startPulseAnimation() {
        if isRecording {
            pulseScale = 1.2
        } else {
            pulseScale = 1.0
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationBar(viewModel: BrowserViewModel())
        .preferredColorScheme(.dark)
        .frame(width: 800)
}
