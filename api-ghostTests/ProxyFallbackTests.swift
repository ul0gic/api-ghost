import Foundation
import Testing

@testable import APIGhost

// MARK: - Anti-MITM fallback detection (5.2.2)

/// `ProxyFallback` decides when a TLS failure means the proxy's MITM leaf was rejected (→ fall back to JS mode)
/// versus a plain connectivity error that fails in JS mode too (→ not breakage). Pure logic, no socket.
struct ProxyFallbackTests {
    private static func urlError(_ code: Int, failingURL: URL? = nil) -> NSError {
        var info: [String: Any] = [:]
        if let failingURL { info[NSURLErrorFailingURLErrorKey] = failingURL }
        return NSError(domain: NSURLErrorDomain, code: code, userInfo: info)
    }

    @Test(arguments: [
        NSURLErrorSecureConnectionFailed,
        NSURLErrorServerCertificateUntrusted,
        NSURLErrorServerCertificateHasBadDate,
        NSURLErrorServerCertificateHasUnknownRoot,
        NSURLErrorServerCertificateNotYetValid,
        NSURLErrorClientCertificateRejected,
        NSURLErrorClientCertificateRequired
    ])
    func tlsFailuresAreTreatedAsMITMBreakage(_ code: Int) {
        #expect(ProxyFallback.isMITMHandshakeFailure(Self.urlError(code)))
    }

    @Test(arguments: [
        NSURLErrorCannotConnectToHost,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorNotConnectedToInternet,
        NSURLErrorCannotFindHost,
        NSURLErrorTimedOut
    ])
    func connectivityFailuresAreNotMITMBreakage(_ code: Int) {
        // These fail in JS mode too, so they are not evidence the MITM leaf was rejected.
        #expect(!ProxyFallback.isMITMHandshakeFailure(Self.urlError(code)))
    }

    @Test
    func nonURLDomainErrorsAreNotMITMBreakage() {
        let posix = NSError(domain: NSPOSIXErrorDomain, code: NSURLErrorSecureConnectionFailed, userInfo: nil)
        #expect(!ProxyFallback.isMITMHandshakeFailure(posix), "a matching code in another domain is not a TLS failure")
    }

    @Test
    func failingHostIsExtractedFromTheFailingURL() throws {
        let url = try #require(URL(string: "https://pinned.example.com/path"))
        let error = Self.urlError(NSURLErrorServerCertificateUntrusted, failingURL: url)
        #expect(ProxyFallback.failingHost(error) == "pinned.example.com")
    }

    @Test
    func failingHostIsNilWhenNoFailingURLIsPresent() {
        #expect(ProxyFallback.failingHost(Self.urlError(NSURLErrorSecureConnectionFailed)) == nil)
    }

    @Test
    func failingHostIsNilForANonNSError() {
        struct Plain: Error {}
        #expect(ProxyFallback.failingHost(Plain()) == nil)
    }
}
