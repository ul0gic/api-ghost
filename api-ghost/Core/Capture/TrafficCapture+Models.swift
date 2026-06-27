//
//  TrafficCapture+Models.swift
//  APIGhost
//
//  Verification/debugging extension and supporting models for TrafficCapture.
//

import Foundation
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "TrafficCapture")

// MARK: - Verification & Debugging

extension TrafficCapture {
    /// Verifies the capture pipeline is working.
    /// - Returns: A status object with detailed system state
    func verifyCaptureSystem() async -> CaptureSystemStatus {
        var status = CaptureSystemStatus()

        // Check database
        do {
            status.databaseConnected = true
            status.captureCount = try CaptureStore.shared.count()
            status.filteredCount = try CaptureStore.shared.filteredCount()
        } catch {
            status.databaseConnected = false
            status.databaseError = error.localizedDescription
        }

        // Check capture state
        status.isCapturing = isCapturing
        status.sessionId = sessionId
        status.recentCapturesCount = recentCaptures.count

        return status
    }

    /// Debug: prints current system status to the console.
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

/// Groups all parameters needed to create a capture from parsed components.
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
}

// MARK: - Capture System Status

/// Status of the capture system for verification and debugging.
struct CaptureSystemStatus {
    var databaseConnected: Bool = false
    var databaseError: String?
    var captureCount: Int = 0
    var filteredCount: Int = 0
    var isCapturing: Bool = false
    var sessionId: String = ""
    var recentCapturesCount: Int = 0
}
