//
//  Preferences.swift
//  api-ghost
//
//  UserDefaults wrapper for persistent user preferences
//

import Foundation

final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let isCAInstalled = "isCAInstalled"
        static let proxyPort = "proxyPort"
        static let inspectorPanelHeight = "inspectorPanelHeight"
        static let inspectorPanelWidth = "inspectorPanelWidth"
        static let inspectorPanelCollapsed = "inspectorPanelCollapsed"
        static let browserTrafficSplitRatio = "browserTrafficSplitRatio"

        // Filter settings
        static let filteringEnabled = "filteringEnabled"
        static let customBlockedDomains = "customBlockedDomains"
        static let customBlockedPaths = "customBlockedPaths"
        static let blockImages = "blockImages"
        static let blockFonts = "blockFonts"
        static let blockVideo = "blockVideo"
        static let blockAudio = "blockAudio"
        static let maxResponseSize = "maxResponseSize"

        // Recording settings
        static let autoStartRecording = "autoStartRecording"
        static let isRecordingPaused = "isRecordingPaused"
    }

    // MARK: - Onboarding & Certificate

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    var isCAInstalled: Bool {
        get { defaults.bool(forKey: Keys.isCAInstalled) }
        set { defaults.set(newValue, forKey: Keys.isCAInstalled) }
    }

    // MARK: - Proxy Settings

    var proxyPort: Int {
        get {
            let port = defaults.integer(forKey: Keys.proxyPort)
            return port == 0 ? 8080 : port
        }
        set { defaults.set(newValue, forKey: Keys.proxyPort) }
    }

    // MARK: - Inspector Panel

    var inspectorPanelHeight: Double {
        get {
            let height = defaults.double(forKey: Keys.inspectorPanelHeight)
            return height == 0 ? 300 : height
        }
        set { defaults.set(newValue, forKey: Keys.inspectorPanelHeight) }
    }

    var inspectorPanelWidth: Double {
        get {
            let width = defaults.double(forKey: Keys.inspectorPanelWidth)
            return width == 0 ? 450 : width
        }
        set { defaults.set(newValue, forKey: Keys.inspectorPanelWidth) }
    }

    var inspectorPanelCollapsed: Bool {
        get { defaults.bool(forKey: Keys.inspectorPanelCollapsed) }
        set { defaults.set(newValue, forKey: Keys.inspectorPanelCollapsed) }
    }

    /// Browser/Traffic split ratio (0.0 to 1.0, where 0.5 means equal split)
    /// Higher values mean more space for the browser, lower for traffic
    var browserTrafficSplitRatio: Double {
        get {
            let ratio = defaults.double(forKey: Keys.browserTrafficSplitRatio)
            return ratio == 0 ? 0.55 : ratio // Default 55% browser, 45% traffic
        }
        set { defaults.set(newValue, forKey: Keys.browserTrafficSplitRatio) }
    }

    // MARK: - Filter Settings

    /// Whether the noise filter is enabled (true = filtering active, false = capture all traffic)
    var filteringEnabled: Bool {
        get {
            // Default to true (filtering enabled) if not set
            if defaults.object(forKey: Keys.filteringEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.filteringEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.filteringEnabled) }
    }

    var customBlockedDomains: [String] {
        get { defaults.stringArray(forKey: Keys.customBlockedDomains) ?? [] }
        set { defaults.set(newValue, forKey: Keys.customBlockedDomains) }
    }

    var customBlockedPaths: [String] {
        get { defaults.stringArray(forKey: Keys.customBlockedPaths) ?? [] }
        set { defaults.set(newValue, forKey: Keys.customBlockedPaths) }
    }

    var blockImages: Bool {
        get {
            if defaults.object(forKey: Keys.blockImages) == nil {
                return true // Default to true
            }
            return defaults.bool(forKey: Keys.blockImages)
        }
        set { defaults.set(newValue, forKey: Keys.blockImages) }
    }

    var blockFonts: Bool {
        get {
            if defaults.object(forKey: Keys.blockFonts) == nil {
                return true // Default to true
            }
            return defaults.bool(forKey: Keys.blockFonts)
        }
        set { defaults.set(newValue, forKey: Keys.blockFonts) }
    }

    var blockVideo: Bool {
        get {
            if defaults.object(forKey: Keys.blockVideo) == nil {
                return true // Default to true
            }
            return defaults.bool(forKey: Keys.blockVideo)
        }
        set { defaults.set(newValue, forKey: Keys.blockVideo) }
    }

    var blockAudio: Bool {
        get {
            if defaults.object(forKey: Keys.blockAudio) == nil {
                return true // Default to true
            }
            return defaults.bool(forKey: Keys.blockAudio)
        }
        set { defaults.set(newValue, forKey: Keys.blockAudio) }
    }

    var maxResponseSize: Int {
        get {
            let size = defaults.integer(forKey: Keys.maxResponseSize)
            return size == 0 ? 10 * 1024 * 1024 : size // Default 10MB
        }
        set { defaults.set(newValue, forKey: Keys.maxResponseSize) }
    }

    // MARK: - Recording Settings

    var autoStartRecording: Bool {
        get {
            if defaults.object(forKey: Keys.autoStartRecording) == nil {
                return false // Default to false - app starts paused
            }
            return defaults.bool(forKey: Keys.autoStartRecording)
        }
        set { defaults.set(newValue, forKey: Keys.autoStartRecording) }
    }

    var isRecordingPaused: Bool {
        get { defaults.bool(forKey: Keys.isRecordingPaused) }
        set { defaults.set(newValue, forKey: Keys.isRecordingPaused) }
    }

    private init() {}
}
