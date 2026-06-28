import SwiftUI

// MARK: - Browser Tab Bar

struct BrowserTabBar: View {
    @Bindable var manager: BrowserTabManager
    @State private var appState = AppState.shared
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if let notice = manager.proxyFallbackNotice {
                fallbackBanner(notice)
            }
            tabRow
        }
        .background(closeActiveTabShortcut)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: manager.proxyFallbackNotice)
        .task(id: appState.interceptMode) {
            await manager.applyInterceptionState()
        }
    }

    private var tabRow: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(manager.tabs) { tab in
                        BrowserTabItem(
                            tab: tab,
                            isActive: tab.id == manager.activeTabId,
                            reduceMotion: reduceMotion,
                            onSelect: { manager.selectTab(tab.id) },
                            onClose: { close(tab.id) }
                        )
                    }
                }
            }

            newTabButton

            Spacer(minLength: 0)
        }
        .frame(height: 36)
        .background(Color.ghostSurface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.ghostBorder)
                .frame(height: 1)
        }
    }

    private func fallbackBanner(_ notice: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 12))
                .foregroundColor(.ghostAccent)

            Text(notice)
                .font(.system(size: 12))
                .foregroundColor(.ghostTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button(action: manager.dismissProxyFallbackNotice) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.ghostTextMuted)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.ghostSurfaceRaised)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.ghostBorder)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var newTabButton: some View {
        Button {
            withAnimation(animation) { _ = manager.newTab() }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.ghostTextMuted)
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.ghostBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut("t", modifiers: .command)
        .help("New Tab")
        .padding(.horizontal, 6)
    }

    private var closeActiveTabShortcut: some View {
        Button {
            close(manager.activeTabId)
        } label: {
            EmptyView()
        }
        .buttonStyle(.plain)
        .keyboardShortcut("w", modifiers: .command)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var animation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.15)
    }

    private func close(_ id: String) {
        withAnimation(animation) { manager.closeTab(id) }
    }
}

// MARK: - Browser Tab Item

struct BrowserTabItem: View {
    let tab: BrowserTab
    let isActive: Bool
    let reduceMotion: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.displayTitle)
                .font(.system(size: 12))
                .foregroundColor(isActive ? .ghostTextPrimary : .ghostTextSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(closeColor)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Close Tab")
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 120, maxWidth: 200)
        .frame(height: 36)
        .background(isActive ? Color.ghostSurfaceRaised : Color.ghostSurface)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.ghostBorder)
                .frame(width: 1)
        }
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.ghostSurfaceRaised)
                    .frame(height: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var closeColor: Color {
        isHovered ? .ghostError : .ghostTextMuted
    }
}
