import Foundation
import SwiftMITM
import Testing

@testable import APIGhost

// MARK: - Proxy capture pipeline (4.2.9)

/// Feeds engine `CaptureEvent`s through `ProxyCaptureSink` and asserts the stored `Capture` matches JS-mode semantics.
/// Every test holds `CaptureStateGate` (shared with the JS suite) and scopes assertions to a unique-per-test host,
/// reading the in-memory mirror (`recentCaptures`) rather than a positive shared-DB-row check (QA-006).
@MainActor
@Suite(.serialized)
struct ProxyCaptureSinkTests {
    private func prepare(capturing: Bool = true) {
        TrafficCapture.shared.isCapturing = capturing
        NoiseFilter.shared.isEnabled = true
        TrafficCapture.shared.clearRecentCaptures()
    }

    @Test
    func responseBodyIsConcatenatedAndStored() async throws {
        try await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let host = CaptureBridge.uniqueHost("proxy-basic")
            let sink = ProxyCaptureSink()

            ProxyEventFixture.drive(
                into: sink,
                host: host,
                method: "GET",
                path: "/v1/users",
                status: 200,
                responseHeaders: [HTTPHeaderField(name: "Content-Type", value: "application/json")],
                responseChunks: [Array("{\"a\":".utf8), Array("1}".utf8)]
            )

            let captured = try #require(await CaptureBridge.waitForRecent(host: host))
            #expect(captured.method == "GET")
            #expect(captured.path == "/v1/users")
            #expect(captured.statusCode == 200)
            #expect(captured.responseBody == Data("{\"a\":1}".utf8), "chunks are concatenated in arrival order")
            #expect(captured.contentType == "application/json")
            #expect(captured.scheme == "https")
            #expect(captured.port == 443)
        }
    }

    @Test
    func gzippedResponseBodyIsDecoded() async throws {
        try await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let host = CaptureBridge.uniqueHost("proxy-gzip")
            let payload = Data(String(repeating: "payload-", count: 32).utf8)
            let gzipped = [UInt8](GzipFixture.gzip(payload))
            let sink = ProxyCaptureSink()

            ProxyEventFixture.drive(
                into: sink,
                host: host,
                responseHeaders: [
                    HTTPHeaderField(name: "Content-Type", value: "application/json"),
                    HTTPHeaderField(name: "Content-Encoding", value: "gzip")
                ],
                responseChunks: [gzipped]
            )

            let captured = try #require(await CaptureBridge.waitForRecent(host: host))
            #expect(captured.responseBody == payload, "Content-Encoding is decoded to match JS-mode output")
        }
    }

    @Test
    func totalSizeUsesSummedByteCountNotCapturedBytes() async throws {
        try await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let host = CaptureBridge.uniqueHost("proxy-truncated")
            let captured5 = Array("ABCDE".utf8)
            let sink = ProxyCaptureSink()

            // Captured slice is 5 bytes but the true chunk was 5000 — the bounded body shrinks, the size stays true.
            ProxyEventFixture.drive(
                into: sink,
                host: host,
                responseHeaders: [HTTPHeaderField(name: "Content-Type", value: "application/json")],
                responseChunks: [captured5],
                responseByteCounts: [5000],
                responseTruncated: true
            )

            let captured = try #require(await CaptureBridge.waitForRecent(host: host))
            #expect(captured.responseBodySize == 5000, "size is the summed true byteCount, not the captured slice")
            #expect(captured.responseBody?.count == 5, "the stored body is the bounded slice")
        }
    }

    @Test
    func requestBodySizeSumsAcrossChunks() async throws {
        try await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let host = CaptureBridge.uniqueHost("proxy-reqbody")
            let sink = ProxyCaptureSink()

            ProxyEventFixture.drive(
                into: sink,
                host: host,
                method: "POST",
                path: "/upload",
                requestHeaders: [HTTPHeaderField(name: "Content-Type", value: "application/octet-stream")],
                requestChunks: [Array("part1".utf8), Array("part2".utf8)],
                requestByteCounts: [5, 7]
            )

            let captured = try #require(await CaptureBridge.waitForRecent(host: host))
            #expect(captured.requestBody == Data("part1part2".utf8))
            #expect(captured.requestBodySize == 12)
        }
    }

    @Test
    func graphQLPostPopulatesOperationColumns() async throws {
        try await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let host = CaptureBridge.uniqueHost("proxy-gql")
            let body = Array(#"{"operationName":"GetUser","query":"query GetUser { user { id } }"}"#.utf8)
            let sink = ProxyCaptureSink()

            ProxyEventFixture.drive(
                into: sink,
                host: host,
                method: "POST",
                path: "/graphql",
                requestHeaders: [HTTPHeaderField(name: "Content-Type", value: "application/json")],
                requestChunks: [body]
            )

            let captured = try #require(await CaptureBridge.waitForRecent(host: host))
            #expect(captured.graphqlOperationName == "GetUser")
            #expect(captured.graphqlOperationType == "query")
        }
    }

    @Test
    func filteredRequestIsDroppedWhileSiblingIsCaptured() async throws {
        try await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let sink = ProxyCaptureSink()
            let allowedHost = CaptureBridge.uniqueHost("proxy-allowed")
            let filteredHost = CaptureBridge.uniqueHost("proxy-filtered")

            // `/collect` matches the analytics category (enabled by default) → dropped, mirroring JS-mode NoiseFilter.
            ProxyEventFixture.drive(into: sink, host: filteredHost, path: "/collect")
            ProxyEventFixture.drive(into: sink, host: allowedHost, path: "/v1/users")

            _ = try #require(await CaptureBridge.waitForRecent(host: allowedHost), "the sibling request is captured")
            #expect(await CaptureBridge.confirmNeverCaptured(host: filteredHost),
                    "a request matching an enabled filter category is dropped, never stored")
        }
    }

    @Test
    func nothingIsCapturedWhilePaused() async {
        await CaptureBridge.withExclusiveCaptureState {
            prepare(capturing: false)
            let host = CaptureBridge.uniqueHost("proxy-paused")
            let sink = ProxyCaptureSink()

            ProxyEventFixture.drive(into: sink, host: host, path: "/v1/users")

            #expect(await CaptureBridge.confirmNeverCaptured(host: host), "a paused session ingests nothing")
        }
    }

    @Test
    func streamErrorDropsPendingWithoutStoring() async {
        await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let host = CaptureBridge.uniqueHost("proxy-streamerror")
            let id = UUID()
            let sink = ProxyCaptureSink()

            sink.receive(.requestHead(ProxyEventFixture.requestHead(id: id, host: host, method: "GET", path: "/x")))
            sink.receive(.requestEnd(requestID: id, truncated: false))
            sink.receive(.streamError(requestID: id, message: "connection reset"))
            // A responseEnd after the error must find nothing pending and store nothing.
            sink.receive(.responseEnd(requestID: id, truncated: false))

            #expect(await CaptureBridge.confirmNeverCaptured(host: host), "a stream error discards the capture")
        }
    }

    @Test
    func upgradeHandshakeIsClassifiedAsStreaming() async throws {
        try await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let host = CaptureBridge.uniqueHost("proxy-ws")
            let sink = ProxyCaptureSink()

            ProxyEventFixture.drive(
                into: sink,
                host: host,
                method: "GET",
                path: "/socket",
                requestHeaders: [HTTPHeaderField(name: "Upgrade", value: "websocket")],
                status: 101,
                responseHeaders: [HTTPHeaderField(name: "Upgrade", value: "websocket")]
            )

            let captured = try #require(await CaptureBridge.waitForRecent(host: host))
            #expect(captured.trafficType == .streaming)
            #expect(captured.isStreaming)
        }
    }

    @Test
    func authorityWithPortIsSplit() async throws {
        try await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let bareHost = CaptureBridge.uniqueHost("proxy-port")
            let sink = ProxyCaptureSink()

            ProxyEventFixture.drive(into: sink, host: "\(bareHost):8443", path: "/v1/ping")

            let captured = try #require(await CaptureBridge.waitForRecent(host: bareHost))
            #expect(captured.port == 8443, "an explicit authority port overrides the scheme default")
        }
    }
}

// MARK: - CaptureEvent fixtures

@MainActor
enum ProxyEventFixture {
    static func requestHead(
        id: UUID,
        host: String,
        method: String,
        path: String,
        headers: [HTTPHeaderField] = []
    ) -> CapturedRequestHead {
        CapturedRequestHead(
            id: id,
            timestamp: Date(),
            scheme: "https",
            authority: host,
            method: method,
            path: path,
            version: .http11,
            headers: headers
        )
    }

    @discardableResult
    static func drive(
        into sink: ProxyCaptureSink,
        host: String,
        method: String = "GET",
        path: String = "/",
        requestHeaders: [HTTPHeaderField] = [],
        requestChunks: [[UInt8]] = [],
        requestByteCounts: [Int]? = nil,
        requestTruncated: Bool = false,
        status: Int = 200,
        responseHeaders: [HTTPHeaderField] = [HTTPHeaderField(name: "Content-Type", value: "application/json")],
        responseChunks: [[UInt8]] = [Array("{\"ok\":true}".utf8)],
        responseByteCounts: [Int]? = nil,
        responseTruncated: Bool = false
    ) -> UUID {
        let id = UUID()
        sink.receive(.requestHead(requestHead(id: id, host: host, method: method, path: path, headers: requestHeaders)))
        for (index, chunk) in requestChunks.enumerated() {
            let byteCount = requestByteCounts?[index] ?? chunk.count
            sink.receive(.requestBodyChunk(requestID: id, bytes: chunk, byteCount: byteCount))
        }
        sink.receive(.requestEnd(requestID: id, truncated: requestTruncated))
        sink.receive(.responseHead(CapturedResponseHead(
            requestID: id,
            timestamp: Date(),
            status: status,
            version: .http11,
            headers: responseHeaders
        )))
        for (index, chunk) in responseChunks.enumerated() {
            let byteCount = responseByteCounts?[index] ?? chunk.count
            sink.receive(.responseBodyChunk(requestID: id, bytes: chunk, byteCount: byteCount))
        }
        sink.receive(.responseEnd(requestID: id, truncated: responseTruncated))
        return id
    }
}
