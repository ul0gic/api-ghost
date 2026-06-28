import SwiftUI

// MARK: - Mode Descriptor

struct InterceptModeDescriptor: Identifiable {
    struct Tradeoff: Identifiable {
        let id = UUID()
        let isPro: Bool
        let label: String
        let detail: String
    }

    let mode: InterceptMode
    let badge: String
    let headline: String
    let tagline: String
    let tradeoffs: [Tradeoff]
    let footer: String

    var id: InterceptMode { mode }
    var requiresCertificate: Bool { mode == .networkProxy }

    static let all: [InterceptModeDescriptor] = [jsInjection, networkProxy]

    static let jsInjection = InterceptModeDescriptor(
        mode: .jsInjection,
        badge: "JS Injection",
        headline: "Zero Setup",
        tagline: "Works immediately. No certificate required. Captures everything the page sees.",
        tradeoffs: [
            Tradeoff(isPro: true, label: "No cert install", detail: "works out of the box on all sites"),
            Tradeoff(isPro: true, label: "Certificate pinning", detail: "works even on sites with pinned certs"),
            Tradeoff(isPro: false, label: "Service workers", detail: "service-worker traffic is invisible"),
            Tradeoff(isPro: false, label: "Browser headers", detail: "Cookie, Set-Cookie, Sec-* not captured")
        ],
        footer: "Best for quick sessions, pinned-cert sites, or when service-worker traffic isn't needed."
    )

    static let networkProxy = InterceptModeDescriptor(
        mode: .networkProxy,
        badge: "Network Proxy",
        headline: "Complete Coverage",
        tagline: "Captures everything on the wire — service workers, all headers, raw bytes.",
        tradeoffs: [
            Tradeoff(isPro: true, label: "Service workers", detail: "captured; x.com-style routing fully visible"),
            Tradeoff(isPro: true, label: "All headers", detail: "Cookie, Set-Cookie, User-Agent, Sec-* on the wire"),
            Tradeoff(isPro: true, label: "h1 + h2", detail: "ALPN-negotiated; WebSocket over h1.1 captured"),
            Tradeoff(isPro: false, label: "CA cert required", detail: "install a local CA once to decrypt TLS traffic")
        ],
        footer: "Requires a one-time CA certificate install — you'll be guided through setup after continuing."
    )
}

// MARK: - Mode Card

struct ModeCard: View {
    let descriptor: InterceptModeDescriptor
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Text(descriptor.headline)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.ghostTextPrimary)
                    .padding(.top, 16)
                Text(descriptor.tagline)
                    .font(.system(size: 12))
                    .foregroundColor(.ghostTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(descriptor.tradeoffs) { tradeoff in
                        tradeoffRow(tradeoff)
                    }
                }
                .padding(.top, 20)

                Divider()
                    .overlay(Color.ghostBorder)
                    .padding(.top, 20)

                Text(descriptor.footer)
                    .font(.system(size: 11))
                    .foregroundColor(.ghostTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: 2)
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(descriptor.badge), \(descriptor.headline)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var cardBackground: Color {
        if isSelected { return .ghostAccentMuted }
        return isHovering ? .ghostSurfaceRaised : .ghostSurface
    }

    private var borderColor: Color {
        if isSelected { return .ghostAccent }
        return isHovering ? Color.ghostTextMuted : Color.ghostBorder
    }

    private var header: some View {
        HStack(alignment: .top) {
            Text(descriptor.badge.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(descriptor.requiresCertificate ? .ghostAccent : .ghostTextSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(descriptor.requiresCertificate ? Color.ghostAccentMuted : Color.ghostSurfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.ghostBorder, lineWidth: 1)
                )
                .cornerRadius(4)
            Spacer()
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 16))
                .foregroundColor(isSelected ? .ghostAccent : .ghostBorder)
        }
    }

    private func tradeoffRow(_ tradeoff: InterceptModeDescriptor.Tradeoff) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tradeoff.isPro ? "checkmark" : "exclamationmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(tradeoff.isPro ? .ghostSuccess : .ghostWarning)
                .frame(width: 16, height: 16)
                .background((tradeoff.isPro ? Color.ghostSuccess : Color.ghostWarning).opacity(0.14))
                .clipShape(Circle())
            Text(tradeoffText(tradeoff))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tradeoffText(_ tradeoff: InterceptModeDescriptor.Tradeoff) -> AttributedString {
        var label = AttributedString(tradeoff.label)
        label.foregroundColor = .ghostTextPrimary
        label.font = .system(size: 12, weight: .medium)
        var detail = AttributedString(" — \(tradeoff.detail)")
        detail.foregroundColor = .ghostTextSecondary
        detail.font = .system(size: 12)
        return label + detail
    }
}
