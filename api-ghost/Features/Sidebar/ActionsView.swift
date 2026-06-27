//
//  ActionsView.swift
//  APIGhost
//
//  Sidebar action buttons for Wipe, Export, Map, and Settings.
//  Action handlers will be connected to actual functionality in later phases.
//

import SwiftUI

struct ActionsView: View {
    // Action handlers - will be connected to actual functionality in Phase 4 (Export/Wipe)
    // and Phase 5 (Settings) of the build plan
    var onWipe: () -> Void = {
        // TODO: Phase 4.6 - Will trigger wipe confirmation dialog
    }
    var onExport: () -> Void = {
        // TODO: Phase 4.5 - Will trigger export dialog sheet
    }
    var onOpenMap: () -> Void = {
        // TODO: Phase 4.2 - Will navigate to Endpoint Map tab
    }
    var onOpenSettings: () -> Void = {
        // TODO: Phase 5.1 - Will open Settings window
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ActionButton(
                title: "Wipe Data",
                icon: "trash",
                style: .destructive,
                action: onWipe
            )

            ActionButton(
                title: "Export",
                icon: "square.and.arrow.up",
                style: .primary,
                action: onExport
            )

            Divider()
                .background(Color.ghostBorder)
                .padding(.vertical, 4)

            ActionButton(
                title: "Endpoint Map",
                icon: "map",
                style: .secondary,
                action: onOpenMap
            )

            ActionButton(
                title: "Settings",
                icon: "gearshape",
                style: .secondary,
                action: onOpenSettings
            )
        }
    }
}

// MARK: - Action Button Style

enum ActionButtonStyle {
    case primary
    case secondary
    case destructive
}

// MARK: - Action Button

struct ActionButton: View {
    let title: String
    let icon: String
    let style: ActionButtonStyle
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return isHovered ? .ghostBase : .ghostAccent
        case .secondary:
            return .ghostTextSecondary
        case .destructive:
            return isHovered ? .white : .ghostError
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            return isHovered ? .ghostAccent : .clear
        case .secondary:
            return isHovered ? .ghostSurfaceRaised : .clear
        case .destructive:
            return isHovered ? .ghostError : .clear
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary:
            return .ghostAccent
        case .secondary:
            return .ghostBorder
        case .destructive:
            return .ghostError
        }
    }
}

#Preview {
    ActionsView()
        .preferredColorScheme(.dark)
        .padding()
        .frame(width: 240)
        .background(Color.ghostSurface)
}
