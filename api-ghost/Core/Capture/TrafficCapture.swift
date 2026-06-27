import Foundation
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "TrafficCapture")

@Observable
final class TrafficCapture {
    // MARK: - Singleton

    static let shared = TrafficCapture()

    // MARK: - Observable State

    var recentCaptures: [Capture] = []

    var isCapturing: Bool = false

    // MARK: - Configuration

    var maxRecentCaptures: Int = 500

    var sessionId: String = UUID().uuidString

    // MARK: - Dependencies

    private let captureStore = CaptureStore.shared
    private let noiseFilter = NoiseFilter.shared

    // MARK: - Initialization

    private init() {}

    // MARK: - Session Management

    func initializeSession(paused: Bool = false) {
        sessionId = UUID().uuidString
        isCapturing = !paused
        AppState.shared.isRecording = !paused
        logger.info("Initialized capture session: \(self.sessionId), capturing: \(!paused)")
    }

    func startSession() {
        sessionId = UUID().uuidString
        isCapturing = true
        AppState.shared.isRecording = true
        logger.info("Started capture session: \(self.sessionId)")
    }

    func endSession() {
        isCapturing = false
        AppState.shared.isRecording = false
        logger.info("Ended capture session: \(self.sessionId)")
    }

    func pauseCapture() {
        isCapturing = false
        AppState.shared.isRecording = false
        Preferences.shared.isRecordingPaused = true
        logger.info("Paused capture")
    }

    func resumeCapture() {
        isCapturing = true
        AppState.shared.isRecording = true
        Preferences.shared.isRecordingPaused = false
        logger.info("Resumed capture")
    }

    func clearRecentCaptures() {
        recentCaptures.removeAll()
    }
}

// MARK: - Capture Processing

extension TrafficCapture {
    func processCapture(
        scheme: String,
        host: String,
        port: Int,
        requestData: Data,
        responseData: Data?,
        startTime: Date
    ) {
        guard isCapturing else { return }

        guard let request = RequestParser.parseRequest(from: requestData) else {
            logger.error("Failed to parse request")
            return
        }

        let response = responseData.flatMap { RequestParser.parseResponse(from: $0) }

        let contentType = response.flatMap { RequestParser.getContentType(from: $0.headers) }

        let filterResult = noiseFilter.shouldCapture(
            host: host,
            path: request.path,
            contentType: contentType,
            responseSize: responseData?.count
        )

        if !filterResult.shouldCapture {
            DispatchQueue.main.async {
                AppState.shared.filteredRequestsCount += 1
            }
            logger.debug("Filtered: \(host)\(request.path) - \(filterResult.reason ?? "blocked")")
            return
        }

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

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

        storeCapture(capture)
    }

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
    func shouldCaptureRequest(host: String, path: String) -> NoiseFilter.FilterResult {
        noiseFilter.shouldCapture(host: host, path: path)
    }

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

    var filterStats: (captured: Int, filtered: Int) {
        (
            AppState.shared.capturedRequestsCount,
            AppState.shared.filteredRequestsCount
        )
    }
}

// MARK: - Storage

extension TrafficCapture {
    private func storeCapture(_ capture: Capture) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.recentCaptures.insert(capture, at: 0)

            if self.recentCaptures.count > self.maxRecentCaptures {
                self.recentCaptures.removeLast(self.recentCaptures.count - self.maxRecentCaptures)
            }
        }

        Task {
            do {
                try captureStore.save(capture)
            } catch {
                logger.error("Failed to save capture: \(error)")
            }
        }

        updateAppState(with: capture)
    }

    func store(_ capture: Capture) {
        storeCapture(capture)
    }

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

    func getDatabaseSize() -> String {
        DatabaseManager.shared.getDatabaseSize()
    }
}

// MARK: - AppState Integration

extension TrafficCapture {
    private func updateAppState(with capture: Capture) {
        DispatchQueue.main.async {
            AppState.shared.capturedRequestsCount += 1
        }
    }

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

    func resetAll() async {
        do {
            try captureStore.deleteAll()

            await MainActor.run {
                self.recentCaptures.removeAll()
                AppState.shared.capturedRequestsCount = 0
                AppState.shared.filteredRequestsCount = 0
            }

            startSession()
        } catch {
            logger.error("Failed to reset captures: \(error)")
        }
    }
}
