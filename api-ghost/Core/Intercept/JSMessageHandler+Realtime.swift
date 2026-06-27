import Foundation
import os

private let rtLog = Logger(subsystem: "corelift.api-ghost", category: "JSRealtime")

// MARK: - WebSocket Handling

extension JSMessageHandler {
    func handleWebSocket(dict: [String: Any]) {
        guard let connectionId = dict["id"] as? String,
              let event = dict["event"] as? String else { return }
        let url = dict["url"] as? String ?? ""
        guard TrafficCapture.shared.isCapturing else { return }
        switch event {
        case "connecting":
            handleWSConnecting(dict: dict, connectionId: connectionId, url: url)
        case "open":
            handleWSOpen(dict: dict, connectionId: connectionId, url: url)
        case "message":
            handleWSMessage(dict: dict, connectionId: connectionId)
        case "close", "closing":
            handleWSClose(dict: dict, connectionId: connectionId)
        case "error":
            handleWSError(dict: dict, connectionId: connectionId)
        default:
            rtLog.warning("Unknown WebSocket event: \(event)")
        }
    }

    private func handleWSConnecting(dict: [String: Any], connectionId: String, url: String) {
        let connection = RealtimeConnection.create(
            connectionId: connectionId,
            sessionId: TrafficCapture.shared.sessionId,
            connectionType: .websocket,
            url: url
        )
        withLock {
            activeConnections[connectionId] = ConnectionState(connection: connection)
            messageSequence[connectionId] = 0
        }
        saveConnectionAsync(connection)
        rtLog.debug("WebSocket connecting: \(url)")
    }

    private func handleWSOpen(dict: [String: Any], connectionId: String, url: String) {
        let wsProtocol = dict["protocol"] as? String
        let extensions = dict["extensions"] as? String
        withLock {
            if var state = activeConnections[connectionId] {
                state.connection.status = .open
                state.connection.websocketProtocol = wsProtocol
                state.connection.extensions = extensions
                activeConnections[connectionId] = state
                Task {
                    try? RealtimeStore.shared.updateConnectionStatus(
                        connectionId: connectionId,
                        status: .open,
                        wsProtocol: wsProtocol,
                        extensions: extensions
                    )
                }
            }
        }
        storeRealtimeMsg(connectionId: connectionId, direction: .receive, eventType: "open")
        rtLog.debug("WebSocket opened: \(url)")
    }

    private func handleWSMessage(dict: [String: Any], connectionId: String) {
        let isSend = (dict["direction"] as? String) == "send"
        let direction: MessageDirection = isSend ? .send : .receive
        let messageType = dict["messageType"] as? String ?? "text"
        let data = dict["data"] as? String
        let dataSize = dict["dataSize"] as? Int ?? data?.count ?? 0
        withLock {
            if var state = activeConnections[connectionId] {
                if isSend {
                    state.messagesSent += 1; state.bytesSent += dataSize
                } else {
                    state.messagesReceived += 1; state.bytesReceived += dataSize
                }
                activeConnections[connectionId] = state
            }
        }
        let dataType: MessageDataType = messageType == "binary" ? .binary : .text
        storeRealtimeMsg(
            connectionId: connectionId,
            direction: direction,
            eventType: "message",
            dataType: dataType,
            data: data,
            dataSize: dataSize
        )
        rtLog.debug("WebSocket \(isSend ? "sent" : "received"): \(dataSize) bytes")
    }

    private func handleWSClose(dict: [String: Any], connectionId: String) {
        let code = dict["code"] as? Int
        let reason = dict["reason"] as? String
        withLock {
            activeConnections.removeValue(forKey: connectionId)
            messageSequence.removeValue(forKey: connectionId)
        }
        Task {
            try? RealtimeStore.shared.closeConnection(
                connectionId: connectionId,
                status: .closed,
                closeCode: code,
                closeReason: reason,
                wasClean: dict["wasClean"] as? Bool,
                durationMs: dict["duration"] as? Int,
                messagesSent: dict["messagesSent"] as? Int,
                messagesReceived: dict["messagesReceived"] as? Int
            )
        }
        storeRealtimeMsg(
            connectionId: connectionId,
            direction: .receive,
            eventType: "close",
            data: reason,
            dataSize: reason?.count ?? 0
        )
        rtLog.debug("WebSocket closed: code=\(code ?? 0) reason=\(reason ?? "")")
    }

    private func handleWSError(dict: [String: Any], connectionId: String) {
        let message = dict["message"] as? String ?? "WebSocket error"
        updateConnectionError(connectionId: connectionId)
        storeRealtimeMsg(
            connectionId: connectionId,
            direction: .receive,
            eventType: "error",
            data: message,
            dataSize: message.count
        )
        rtLog.error("WebSocket error: \(message)")
    }
}

// MARK: - SSE Handling

extension JSMessageHandler {
    func handleSSE(dict: [String: Any]) {
        guard let connectionId = dict["id"] as? String else { return }
        let type = dict["type"] as? String ?? "sse"
        let url = dict["url"] as? String ?? ""
        guard TrafficCapture.shared.isCapturing else { return }
        if type == "sse_connect" {
            handleSSEConnect(dict: dict, connectionId: connectionId, url: url)
            return
        }
        guard let event = dict["event"] as? String else { return }
        switch event {
        case "open": handleSSEOpen(connectionId: connectionId, url: url)
        case "close": handleSSEClose(dict: dict, connectionId: connectionId)
        case "error": handleSSEError(dict: dict, connectionId: connectionId)
        default: handleSSEMessage(dict: dict, connectionId: connectionId, event: event)
        }
    }

    private func handleSSEConnect(dict: [String: Any], connectionId: String, url: String) {
        let withCredentials = dict["withCredentials"] as? Bool ?? false
        let connection = RealtimeConnection.create(
            connectionId: connectionId,
            sessionId: TrafficCapture.shared.sessionId,
            connectionType: .sse,
            url: url,
            withCredentials: withCredentials
        )
        withLock {
            activeConnections[connectionId] = ConnectionState(connection: connection)
            messageSequence[connectionId] = 0
        }
        saveConnectionAsync(connection)
        rtLog.debug("SSE connecting: \(url)")
    }

    private func handleSSEOpen(connectionId: String, url: String) {
        withLock {
            if var state = activeConnections[connectionId] {
                state.connection.status = .open
                activeConnections[connectionId] = state
            }
        }
        Task {
            try? RealtimeStore.shared.updateConnectionStatus(
                connectionId: connectionId,
                status: .open
            )
        }
        storeRealtimeMsg(connectionId: connectionId, direction: .receive, eventType: "open")
        rtLog.debug("SSE opened: \(url)")
    }

    private func handleSSEClose(dict: [String: Any], connectionId: String) {
        let duration = dict["duration"] as? Int
        let messageCount = dict["messageCount"] as? Int
        withLock {
            activeConnections.removeValue(forKey: connectionId)
            messageSequence.removeValue(forKey: connectionId)
        }
        Task {
            try? RealtimeStore.shared.closeConnection(
                connectionId: connectionId,
                status: .closed,
                durationMs: duration,
                messagesReceived: messageCount
            )
        }
        storeRealtimeMsg(connectionId: connectionId, direction: .receive, eventType: "close")
        rtLog.debug("SSE closed after \(messageCount ?? 0) messages")
    }

    private func handleSSEError(dict: [String: Any], connectionId: String) {
        let data = dict["data"] as? String ?? "Connection error"
        updateConnectionError(connectionId: connectionId)
        storeRealtimeMsg(
            connectionId: connectionId,
            direction: .receive,
            eventType: "error",
            data: data,
            dataSize: data.count
        )
        rtLog.error("SSE error: \(data)")
    }

    private func handleSSEMessage(dict: [String: Any], connectionId: String, event: String) {
        let data = dict["data"] as? String
        let lastEventId = dict["lastEventId"] as? String
        let dataSize = data?.count ?? 0
        withLock {
            if var state = activeConnections[connectionId] {
                state.messagesReceived += 1
                state.bytesReceived += dataSize
                activeConnections[connectionId] = state
            }
        }
        storeRealtimeMsg(
            connectionId: connectionId,
            direction: .receive,
            eventType: event,
            data: data,
            dataSize: dataSize,
            lastEventId: lastEventId
        )
        rtLog.debug("SSE event '\(event)': \(dataSize) bytes")
    }
}

// MARK: - Realtime Helpers

extension JSMessageHandler {
    func storeRealtimeMsg(
        connectionId: String,
        direction: MessageDirection,
        eventType: String,
        dataType: MessageDataType = .text,
        data: String? = nil,
        dataSize: Int = 0,
        lastEventId: String? = nil
    ) {
        var seq = 0
        withLock {
            seq = messageSequence[connectionId] ?? 0
            messageSequence[connectionId] = seq + 1
        }
        let message: RealtimeMessage
        if dataType == .binary {
            message = RealtimeMessage.fromBinary(
                connectionId: connectionId,
                sessionId: TrafficCapture.shared.sessionId,
                direction: direction,
                eventType: eventType,
                base64Data: data,
                originalSize: dataSize,
                sequenceNum: seq
            )
        } else {
            message = RealtimeMessage.fromText(
                connectionId: connectionId,
                sessionId: TrafficCapture.shared.sessionId,
                direction: direction,
                eventType: eventType,
                text: data,
                lastEventId: lastEventId,
                sequenceNum: seq
            )
        }
        Task {
            do {
                try RealtimeStore.shared.saveMessage(message)
            } catch {
                rtLog.error("Failed to save realtime message: \(error)")
            }
        }
    }

    func updateConnectionError(connectionId: String) {
        withLock {
            if var state = activeConnections[connectionId] {
                state.connection.status = .error
                activeConnections[connectionId] = state
            }
        }
        Task {
            try? RealtimeStore.shared.updateConnectionStatus(
                connectionId: connectionId,
                status: .error
            )
        }
    }

    func saveConnectionAsync(_ connection: RealtimeConnection) {
        Task {
            do {
                try RealtimeStore.shared.saveConnection(connection)
            } catch {
                rtLog.error("Failed to save connection: \(error)")
            }
        }
    }
}
