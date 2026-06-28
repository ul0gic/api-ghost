import Foundation
import SwiftMITM
import Testing

@testable import APIGhost

// MARK: - JS vs Network mode stored-shape parity (5.2.1)

/// Drives one logical request through BOTH capture pipelines — the JS bridge (`JSMessageHandler`) and the proxy
/// engine sink (`ProxyCaptureSink`) — and asserts the stored `Capture` carries the same shape. Both modes share the
/// same `TrafficCapture.shared` global state, so each test holds `CaptureStateGate` and scopes to unique hosts (QA-006).
@MainActor
@Suite(.serialized)
struct CaptureModeParityTests {
    private func prepare() {
        TrafficCapture.shared.isCapturing = true
        NoiseFilter.shared.isEnabled = true
        TrafficCapture.shared.clearRecentCaptures()
    }

    private func captureViaJS(host: String, method: String, path: String, requestBody: String?) {
        let handler = JSMessageHandler()
        CaptureBridge.capture(
            through: handler,
            url: "https://\(host)\(path)",
            method: method,
            requestHeaders: ["Content-Type": "application/json"],
            requestBody: requestBody
        )
    }

    private func captureViaProxy(host: String, method: String, path: String, requestBody: String?) {
        let sink = ProxyCaptureSink()
        ProxyEventFixture.drive(
            into: sink,
            host: host,
            method: method,
            path: path,
            requestHeaders: [HTTPHeaderField(name: "Content-Type", value: "application/json")],
            requestChunks: requestBody.map { [Array($0.utf8)] } ?? [],
            responseHeaders: [HTTPHeaderField(name: "Content-Type", value: "application/json")],
            responseChunks: [Array(#"{"ok":true}"#.utf8)]
        )
    }

    @Test
    func bothModesStoreEquivalentShapeForAGraphQLPost() async throws {
        try await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let jsHost = CaptureBridge.uniqueHost("parity-js")
            let proxyHost = CaptureBridge.uniqueHost("parity-proxy")
            let body = #"{"operationName":"GetUser","query":"query GetUser { user { id } }"}"#

            captureViaJS(host: jsHost, method: "POST", path: "/graphql", requestBody: body)
            captureViaProxy(host: proxyHost, method: "POST", path: "/graphql", requestBody: body)

            let js = try #require(await CaptureBridge.waitForRecent(host: jsHost))
            let proxy = try #require(await CaptureBridge.waitForRecent(host: proxyHost))

            #expect(js.method == proxy.method)
            #expect(js.scheme == proxy.scheme)
            #expect(js.port == proxy.port)
            #expect(js.path == proxy.path)
            #expect(js.statusCode == proxy.statusCode)
            #expect(js.contentType == proxy.contentType)
            #expect(js.requestBody == proxy.requestBody, "the same request body bytes are stored in both modes")
            #expect(js.responseBody == proxy.responseBody, "the same response body bytes are stored in both modes")
            #expect(js.graphqlOperationName == proxy.graphqlOperationName)
            #expect(js.graphqlOperationType == proxy.graphqlOperationType)
            #expect(js.graphqlOperationName == "GetUser")
            #expect(js.graphqlOperationType == "query")
        }
    }

    @Test
    func bothModesPreserveQueryStringAndPort() async throws {
        try await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let jsHost = CaptureBridge.uniqueHost("parity-q-js")
            let proxyHost = CaptureBridge.uniqueHost("parity-q-proxy")

            captureViaJS(host: jsHost, method: "GET", path: "/v1/search?q=ghost&page=2", requestBody: nil)
            captureViaProxy(host: proxyHost, method: "GET", path: "/v1/search?q=ghost&page=2", requestBody: nil)

            let js = try #require(await CaptureBridge.waitForRecent(host: jsHost))
            let proxy = try #require(await CaptureBridge.waitForRecent(host: proxyHost))

            #expect(js.path == "/v1/search")
            #expect(proxy.path == "/v1/search")
            #expect(js.query == proxy.query)
            #expect(proxy.query == "q=ghost&page=2")
            #expect(js.port == 443)
            #expect(proxy.port == 443)
        }
    }

    @Test
    func bothModesDropAFilteredRequest() async {
        await CaptureBridge.withExclusiveCaptureState {
            prepare()
            defer { TrafficCapture.shared.isCapturing = false }
            let jsHost = CaptureBridge.uniqueHost("parity-drop-js")
            let proxyHost = CaptureBridge.uniqueHost("parity-drop-proxy")

            // `/collect` matches the analytics category (enabled by default) → dropped identically in both pipelines.
            captureViaJS(host: jsHost, method: "GET", path: "/collect", requestBody: nil)
            captureViaProxy(host: proxyHost, method: "GET", path: "/collect", requestBody: nil)

            #expect(await CaptureBridge.confirmNeverCaptured(host: jsHost), "JS mode drops the filtered request")
            #expect(await CaptureBridge.confirmNeverCaptured(host: proxyHost), "network mode drops it too")
        }
    }
}
