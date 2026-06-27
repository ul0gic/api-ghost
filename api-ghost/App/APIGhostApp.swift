//
//  APIGhostApp.swift
//  api-ghost
//
//  Created by ul0gic on 12/16/25.
//

import SwiftUI
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "APIGhostApp")

@main
struct APIGhostApp: App {
    @State private var showOnboarding: Bool = !Preferences.shared.hasCompletedOnboarding

    init() {
        logger.info("Initializing...")
        // Initialize database
        initializeDatabase()

        // Initialize capture session (starts paused by default)
        let shouldPause = !Preferences.shared.autoStartRecording || Preferences.shared.isRecordingPaused
        TrafficCapture.shared.initializeSession(paused: shouldPause)

        logger.info("Initialization complete")
    }

    var body: some Scene {
        WindowGroup {
            MainContentWrapper(showOnboarding: $showOnboarding)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1200, minHeight: 800)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 900)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    // Switch to Settings tab via AppState
                    AppState.shared.selectedTab = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // Custom keyboard shortcuts
            CommandGroup(after: .toolbar) {
                Button("Reload Page") {
                    NotificationCenter.default.post(name: .reloadPage, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Focus URL Bar") {
                    NotificationCenter.default.post(name: .focusURLBar, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Export Database") {
                    NotificationCenter.default.post(name: .exportDatabase, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Clear Traffic List") {
                    NotificationCenter.default.post(name: .clearTrafficList, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Focus Search") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()

                Button("Browser") {
                    AppState.shared.selectedTab = .browser
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Map") {
                    AppState.shared.selectedTab = .map
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("SQL") {
                    AppState.shared.selectedTab = .sql
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Settings") {
                    AppState.shared.selectedTab = .settings
                }
                .keyboardShortcut("4", modifiers: .command)
            }
        }
    }

    // MARK: - Private Methods

    private func initializeDatabase() {
        // Access the shared instance to trigger initialization
        let manager = DatabaseManager.shared

        if manager.isReady {
            logger.info("Database ready at: \(manager.path ?? "unknown")")
            logger.info("Database size: \(manager.getDatabaseSize())")
        } else if let error = manager.error {
            logger.error("Database initialization failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Main Content Wrapper

/// Wrapper view that handles navigation notifications
private struct MainContentWrapper: View {
    @Binding var showOnboarding: Bool

    var body: some View {
        Group {
            if showOnboarding {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showOnboarding = false
                    }
                }
            } else {
                MainWindowView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            // Navigate to Settings tab via AppState
            AppState.shared.selectedTab = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportDatabase)) { _ in
            // Switch to Settings tab, then to Data Management
            AppState.shared.selectedTab = .settings
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .openSettingsToTab, object: SettingsTab.dataManagement)
            }
        }
    }
}

// MARK: - Notification Names for Keyboard Shortcuts

extension Notification.Name {
    static let reloadPage = Notification.Name("reloadPage")
    static let focusURLBar = Notification.Name("focusURLBar")
    static let exportDatabase = Notification.Name("exportDatabase")
    static let clearTrafficList = Notification.Name("clearTrafficList")
    static let focusSearch = Notification.Name("focusSearch")
    static let switchToTab = Notification.Name("switchToTab")
    static let openSettings = Notification.Name("openSettings")
    static let openSettingsToTab = Notification.Name("openSettingsToTab")
}
