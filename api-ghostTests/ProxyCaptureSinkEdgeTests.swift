import Foundation
import SwiftMITM
import Testing

@testable import APIGhost

// MARK: - Proxy sink edge branches (5.2.2)

/// Edge branches of `ProxyCaptureSink` not covered by `ProxyCaptureSinkTests`: IPv6 authorities, query splitting,
/// request-body decode, deflate-through-the-sink, and the two independent websocket triggers. Same isolation contract
/// as the base suite — holds `CaptureStateGate`, scopes to unique hosts, reads the in-memory mirror (QA-006).
@MainActor
@Suite(.serialized)
struct ProxyCaptureSinkEdgeTests {
    private func prepare() {
        TrafficCapture.shared.isCapturing = true
        NoiseFilter.shared.isEnabled = true
        TrafficCapture.shared.clearRecentCaptures()
    }

    @Test
    func bracketedIPv6AuthorityWithPortIsSplit() async throws {
        try await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let sink = ProxyCaptureSink()

            ProxyEventFixture.drive(into: sink, host: "[2001:db8::1]:8443", path: "/v1/ping")

            let captured = try #require(await CaptureBridge.waitForRecent(host: "2001:db8::1"))
            #expect(captured.port == 8443, "the bracketed literal is unwrapped and the trailing port parsed")
        }
    }

    @Test
    func bracketedIPv6AuthorityWithoutPortUsesSchemeDefault() async throws {
        try await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let sink = ProxyCaptureSink()

            ProxyEventFixture.drive(into: sink, host: "[2001:db8::2]", path: "/v1/ping")

            let captured = try #require(await CaptureBridge.waitForRecent(host: "2001:db8::2"))
            #expect(captured.port == 443, "no authority port falls back to the https default")
        }
    }

    @Test
    func queryStringIsSplitFromPath() async throws {
        try await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let host = CaptureBridge.uniqueHost("proxy-query")
            let sink = ProxyCaptureSink()

            ProxyEventFixture.drive(into: sink, host: host, path: "/v1/search?q=ghost&page=2")

            let captured = try #require(await CaptureBridge.waitForRecent(host: host))
            #expect(captured.path == "/v1/search")
            #expect(captured.query == "q=ghost&page=2")
        }
    }

    @Test
    func emptyPathDefaultsToRoot() async throws {
        try await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let host = CaptureBridge.uniqueHost("proxy-rootpath")
            let sink = ProxyCaptureSink()

            ProxyEventFixture.drive(into: sink, host: host, path: "")

            let captured = try #require(await CaptureBridge.waitForRecent(host: host))
            #expect(captured.path == "/", "an empty target normalizes to root")
        }
    }

    @Test
    func gzippedRequestBodyIsDecoded() async throws {
        try await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let host = CaptureBridge.uniqueHost("proxy-reqgzip")
            let payload = Data(String(repeating: "request-", count: 24).utf8)
            let gzipped = [UInt8](GzipFixture.gzip(payload))
            let sink = ProxyCaptureSink()

            ProxyEventFixture.drive(
                into: sink,
                host: host,
                method: "POST",
                path: "/upload",
                requestHeaders: [
                    HTTPHeaderField(name: "Content-Type", value: "application/octet-stream"),
                    HTTPHeaderField(name: "Content-Encoding", value: "gzip")
                ],
                requestChunks: [gzipped]
            )

            let captured = try #require(await CaptureBridge.waitForRecent(host: host))
            #expect(captured.requestBody == payload, "request Content-Encoding is decoded, mirroring the response path")
        }
    }

    @Test
    func deflatedResponseBodyIsDecodedThroughTheSink() async throws {
        try await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let host = CaptureBridge.uniqueHost("proxy-deflate")
            let payload = Data(String(repeating: "deflate-", count: 32).utf8)
            let deflated = [UInt8](GzipFixture.zlibDeflate(payload))
            let sink = ProxyCaptureSink()

            ProxyEventFixture.drive(
                into: sink,
                host: host,
                responseHeaders: [
                    HTTPHeaderField(name: "Content-Type", value: "application/json"),
                    HTTPHeaderField(name: "Content-Encoding", value: "deflate")
                ],
                responseChunks: [deflated]
            )

            let captured = try #require(await CaptureBridge.waitForRecent(host: host))
            #expect(captured.responseBody == payload, "deflate decodes end-to-end through the sink")
        }
    }

    @Test
    func status101WithoutUpgradeHeaderIsStreaming() async throws {
        try await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let host = CaptureBridge.uniqueHost("proxy-101")
            let sink = ProxyCaptureSink()

            ProxyEventFixture.drive(into: sink, host: host, path: "/socket", status: 101)

            let captured = try #require(await CaptureBridge.waitForRecent(host: host))
            #expect(captured.isStreaming, "a 101 status alone classifies the exchange as streaming")
        }
    }

    @Test
    func upgradeHeaderWithoutStatus101IsStreaming() async throws {
        try await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let host = CaptureBridge.uniqueHost("proxy-upgrade")
            let sink = ProxyCaptureSink()

            ProxyEventFixture.drive(
                into: sink,
                host: host,
                path: "/socket",
                requestHeaders: [HTTPHeaderField(name: "Upgrade", value: "websocket")],
                status: 200
            )

            let captured = try #require(await CaptureBridge.waitForRecent(host: host))
            #expect(captured.isStreaming, "an Upgrade: websocket request header alone classifies as streaming")
        }
    }
}
