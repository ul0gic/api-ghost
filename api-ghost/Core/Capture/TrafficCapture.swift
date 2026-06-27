//
//  TrafficCapture.swift
//  api-ghost
//
//  Created for APIGhost project
//

import Foundation
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "TrafficCapture")

/// Central traffic capture coordinator that ties together proxy, capture, and storage systems.
/// Manages capture sessions and provides observable state for UI updates.
@Observable
final class TrafficCapture {
    // MARK: - Singleton

    static let shared = TrafficCapture()

    // MARK: - Observable State

    /// Recent captures stored in memory for UI display
    var recentCaptures: [Capture] = []

    /// Whether capture is currently active
    var isCapturing: Bool = false

    // MARK: - Configuration

    /// Maximum number of recent captures to keep in memory
    var maxRecentCaptures: Int = 500

    /// Current session identifier for grouping captures
    var sessionId: String = UUID().uuidString

    // MARK: - Dependencies

    private let captureStore = CaptureStore.shared
    private let noiseFilter = NoiseFilter.shared

    // MARK: - Initialization

    private init() {}

    // MARK: - Session Management

    /// Initializes a new capture session with optional paused state.
    /// - Parameter paused: If true, session starts paused (not capturing). Default is false.
    func initializeSession(paused: Bool = false) {
        sessionId = UUID().uuidString
        isCapturing = !paused
        AppState.shared.isRecording = !paused
        logger.info("Initialized capture session: \(self.sessionId), capturing: \(!paused)")
    }

    /// Starts a new capture session with a fresh session ID.
    func startSession() {
        sessionId = UUID().uuidString
        isCapturing = true
        AppState.shared.isRecording = true
        logger.info("Started capture session: \(self.sessionId)")
    }

    /// Ends the current capture session.
    func endSession() {
        isCapturing = false
        AppState.shared.isRecording = false
        logger.info("Ended capture session: \(self.sessionId)")
    }

    /// Pauses the current capture session without ending it.
    func pauseCapture() {
        isCapturing = false
        AppState.shared.isRecording = false
        Preferences.shared.isRecordingPaused = true
        logger.info("Paused capture")
    }

    /// Resumes a paused capture session.
    func resumeCapture() {
        isCapturing = true
        AppState.shared.isRecording = true
        Preferences.shared.isRecordingPaused = false
        logger.info("Resumed capture")
    }

    /// Clears recent captures from memory (does not affect database).
    func clearRecentCaptures() {
        recentCaptures.removeAll()
    }
}

// MARK: - Capture Processing

extension TrafficCapture {
    /// Processes and stores a capture from raw request/response data.
    /// - Parameters:
    ///   - scheme: URL scheme (http or https)
    ///   - host: Target host
    ///   - port: Target port
    ///   - requestData: Raw HTTP request data
    ///   - responseData: Raw HTTP response data (optional)
    ///   - startTime: Time when the request started
    func processCapture(
        scheme: String,
        host: String,
        port: Int,
        requestData: Data,
        responseData: Data?,
        startTime: Date
    ) {
        guard isCapturing else { return }

        // Parse request
        guard let request = RequestParser.parseRequest(from: requestData) else {
            logger.error("Failed to parse request")
            return
        }

        // Parse response if available
        let response = responseData.flatMap { RequestParser.parseResponse(from: $0) }

        // Get content type from response
        let contentType = response.flatMap { RequestParser.getContentType(from: $0.headers) }

        // Apply noise filter
        let filterResult = noiseFilter.shouldCapture(
            host: host,
            path: request.path,
            contentType: contentType,
            responseSize: responseData?.count
        )

        // Skip filtered requests entirely - don't store noise
        if !filterResult.shouldCapture {
            DispatchQueue.main.async {
                AppState.shared.filteredRequestsCount += 1
            }
            logger.debug("Filtered: \(host)\(request.path) - \(filterResult.reason ?? "blocked")")
            return
        }

        // Calculate duration
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        // Create capture
        let capture = Capture(
            sessionId: sessionId,
            method: request.method,
            scheme: scheme,
            host: host,
            port: port,
            path: request.path,
            query: request.query,
            requestHeaders: request.headers.toJSONString(),
            requestBody: request.body,
            requestBodySize: request.body?.count ?? 0,
            statusCode: response?.statusCode,
            statusMessage: response?.statusMessage,
            responseHeaders: response?.headers.toJSONString(),
            responseBody: response?.body,
            responseBodySize: response?.body?.count ?? 0,
            contentType: contentType,
            durationMs: durationMs
        )

        // Store and notify
        storeCapture(capture)
    }

    /// Creates a capture directly from parsed components.
    /// - Parameter parameters: All parameters needed to build the capture
    /// - Returns: A configured Capture instance
    func createCapture(from parameters: CaptureParameters) -> Capture {
        Capture(
            sessionId: sessionId,
            method: parameters.method,
            scheme: parameters.scheme,
            host: parameters.host,
            port: parameters.port,
            path: parameters.path,
            query: parameters.query,
            requestHeaders: parameters.requestHeaders.toJSONString(),
            requestBody: parameters.requestBody,
            requestBodySize: parameters.requestBody?.count ?? 0,
            statusCode: parameters.statusCode,
            statusMessage: parameters.statusMessage,
            responseHeaders: parameters.responseHeaders?.toJSONString(),
            responseBody: parameters.responseBody,
            responseBodySize: parameters.responseBody?.count ?? 0,
            contentType: parameters.contentType,
            durationMs: parameters.durationMs
        )
    }
}

// MARK: - Filtering

extension TrafficCapture {
    /// Pre-checks if a request should be captured before processing.
    /// - Parameters:
    ///   - host: The target host
    ///   - path: The request path
    /// - Returns: FilterResult indicating whether to capture
    func shouldCaptureRequest(host: String, path: String) -> NoiseFilter.FilterResult {
        noiseFilter.shouldCapture(host: host, path: path)
    }

    /// Checks if a response should be captured based on content type and size.
    /// - Parameters:
    ///   - host: The target host
    ///   - path: The request path
    ///   - contentType: The Content-Type header value (optional)
    ///   - responseSize: The response size in bytes (optional)
    /// - Returns: FilterResult indicating whether to capture
    func shouldCaptureResponse(
        host: String,
        path: String,
        contentType: String?,
        responseSize: Int?
    ) -> NoiseFilter.FilterResult {
        noiseFilter.shouldCapture(
            host: host,
            path: path,
            contentType: contentType,
            responseSize: responseSize
        )
    }

    /// Gets current filter statistics (captured vs filtered counts).
    var filterStats: (captured: Int, filtered: Int) {
        (
            AppState.shared.capturedRequestsCount,
            AppState.shared.filteredRequestsCount
        )
    }
}

// MARK: - Storage

extension TrafficCapture {
    /// Stores a capture in memory and persists to database.
    /// - Parameter capture: The capture to store
    private func storeCapture(_ capture: Capture) {
        // Add to recent captures (in memory) on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.recentCaptures.insert(capture, at: 0)

            // Trim to max size
            if self.recentCaptures.count > self.maxRecentCaptures {
                self.recentCaptures.removeLast(self.recentCaptures.count - self.maxRecentCaptures)
            }
        }

        // Store in database (background)
        Task {
            do {
                try captureStore.save(capture)
            } catch {
                logger.error("Failed to save capture: \(error)")
            }
        }

        // Update AppState
        updateAppState(with: capture)
    }

    /// Stores a capture directly (used by delegate callbacks).
    /// - Parameter capture: The capture to store
    func store(_ capture: Capture) {
        storeCapture(capture)
    }

    /// Loads recent captures from the database into memory.
    func loadRecentCaptures() async {
        do {
            let captures = try captureStore.fetchAll(limit: maxRecentCaptures)
            await MainActor.run {
                self.recentCaptures = captures
            }
        } catch {
            logger.error("Failed to load recent captures: \(error)")
        }
    }

    /// Gets the current database size as a formatted string.
    /// - Returns: Human-readable database size (e.g., "4.5 MB")
    func getDatabaseSize() -> String {
        DatabaseManager.shared.getDatabaseSize()
    }
}

// MARK: - AppState Integration

extension TrafficCapture {
    /// Updates AppState counters when a capture is stored.
    /// Note: Only non-filtered captures reach this point - filtered ones are dropped earlier.
    /// - Parameter capture: The captured request
    private func updateAppState(with capture: Capture) {
        DispatchQueue.main.async {
            AppState.shared.capturedRequestsCount += 1
        }
    }

    /// Refreshes AppState counts from the database.
    func refreshCounts() async {
        do {
            let totalCount = try captureStore.count()
            let filteredCount = try captureStore.filteredCount()

            await MainActor.run {
                AppState.shared.capturedRequestsCount = totalCount - filteredCount
                AppState.shared.filteredRequestsCount = filteredCount
            }
        } catch {
            logger.error("Failed to refresh counts: \(error)")
        }
    }

    /// Resets all counts and clears captured data.
    func resetAll() async {
        do {
            try captureStore.deleteAll()

            await MainActor.run {
                self.recentCaptures.removeAll()
                AppState.shared.capturedRequestsCount = 0
                AppState.shared.filteredRequestsCount = 0
            }

            // Start new session
            startSession()
        } catch {
            logger.error("Failed to reset captures: \(error)")
        }
    }
}

// Verification, CaptureParameters, and CaptureSystemStatus are in TrafficCapture+Models.swift
