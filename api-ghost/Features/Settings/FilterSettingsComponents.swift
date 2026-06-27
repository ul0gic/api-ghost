import SwiftUI

// MARK: - Response Size Limit

enum ResponseSizeLimit: CaseIterable {
    case oneMB
    case fiveMB
    case tenMB
    case fiftyMB
    case unlimited

    var bytes: Int {
        switch self {
        case .oneMB: return 1 * 1024 * 1024
        case .fiveMB: return 5 * 1024 * 1024
        case .tenMB: return 10 * 1024 * 1024
        case .fiftyMB: return 50 * 1024 * 1024
        case .unlimited: return Int.max
        }
    }

    var displayName: String {
        switch self {
        case .oneMB: return "1 MB"
        case .fiveMB: return "5 MB"
        case .tenMB: return "10 MB"
        case .fiftyMB: return "50 MB"
        case .unlimited: return "No Limit"
        }
    }
}

// MARK: - Filter List Item

struct FilterListItem: View {
    let text: String
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.ghostTextSecondary)
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.ghostTextMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.ghostSurfaceRaised)
        .cornerRadius(4)
    }
}

// MARK: - Capture All Toggle View

struct CaptureAllToggleView: View {
    @Binding var captureAllTraffic: Bool
    let noiseFilter: NoiseFilter

    var body: some View {
        GroupBox {
            HStack(spacing: 12) {
                captureAllIcon
                captureAllLabels
                Spacer()
                captureAllToggle
            }
            .padding(12)
        }
        .background(captureAllBackground)
        .backgroundStyle(captureAllBackgroundStyle)
    }

    private var captureAllIcon: some View {
        let iconName = captureAllTraffic
            ? "antenna.radiowaves.left.and.right"
            : "line.3.horizontal.decrease.circle"
        let iconColor: Color = captureAllTraffic ? .orange : .ghostAccent
        return Image(systemName: iconName)
            .font(.system(size: 24))
            .foregroundColor(iconColor)
            .frame(width: 32)
    }

    private var captureAllLabels: some View {
        let descriptionText = captureAllTraffic
            ? "All traffic is being captured, including analytics and noise."
            : "Filtering is active. Analytics and noise are being blocked."
        let descriptionColor: Color = captureAllTraffic ? .orange : .ghostTextMuted

        return VStack(alignment: .leading, spacing: 4) {
            Text("Capture All Traffic")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.ghostTextPrimary)
            Text(descriptionText)
                .font(.system(size: 11))
                .foregroundColor(descriptionColor)
        }
    }

    private var captureAllToggle: some View {
        Toggle("", isOn: $captureAllTraffic)
            .toggleStyle(.switch)
            .tint(.orange)
            .onChange(of: captureAllTraffic) { _, newValue in
                noiseFilter.isEnabled = !newValue
                Preferences.shared.filteringEnabled = !newValue
            }
    }

    private var captureAllBackground: some View {
        let strokeColor: Color = captureAllTraffic ? Color.orange.opacity(0.5) : Color.clear
        return RoundedRectangle(cornerRadius: 8)
            .stroke(strokeColor, lineWidth: 1)
    }

    private var captureAllBackgroundStyle: Color {
        captureAllTraffic ? Color.orange.opacity(0.1) : Color.ghostSurface
    }
}

// MARK: - Content Type Toggle

struct ContentTypeToggle: View {
    let label: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.ghostTextMuted)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.ghostTextSecondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(.ghostAccent)
    }
}
