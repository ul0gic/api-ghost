import Foundation
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "TrafficCapture")

// MARK: - Verification & Debugging

extension TrafficCapture {
    func verifyCaptureSystem() async -> CaptureSystemStatus {
        var status = CaptureSystemStatus()

        do {
            status.databaseConnected = true
            status.captureCount = try CaptureStore.shared.count()
        } catch {
            status.databaseConnected = false
            status.databaseError = error.localizedDescription
        }

        status.filteredCount = await MainActor.run { AppState.shared.filteredRequestsCount }
        status.isCapturing = isCapturing
        status.sessionId = sessionId
        status.recentCapturesCount = recentCaptures.count

        return status
    }

    func printSystemStatus() async {
        let status = await verifyCaptureSystem()

        logger.info("=== APIGhost Capture System Status ===")
        logger.info("Database Connected: \(status.databaseConnected)")
        logger.info("Captures in DB: \(status.captureCount)")
        logger.debug("Filtered in DB: \(status.filteredCount)")
        logger.info("Is Capturing: \(status.isCapturing)")
        logger.info("Session ID: \(status.sessionId)")
        logger.info("Recent Captures: \(status.recentCapturesCount)")
        if let error = status.databaseError {
            logger.error("DB Error: \(error)")
        }
        logger.info("=====================================")
    }
}

// MARK: - Capture Parameters

struct CaptureParameters {
    let scheme: String
    let host: String
    let port: Int
    let method: String
    let path: String
    let query: String?
    let requestHeaders: [String: String]
    let requestBody: Data?
    let statusCode: Int?
    let statusMessage: String?
    let responseHeaders: [String: String]?
    let responseBody: Data?
    let contentType: String?
    let durationMs: Int?
    let graphqlOperationName: String?
    let graphqlOperationType: String?
    let sourceTabId: String?
}

// MARK: - Capture System Status

struct CaptureSystemStatus {
    var databaseConnected: Bool = false
    var databaseError: String?
    var captureCount: Int = 0
    var filteredCount: Int = 0
    var isCapturing: Bool = false
    var sessionId: String = ""
    var recentCapturesCount: Int = 0
}
