import Foundation

/// Detection contract for network-proxy MITM breakage (cert pinning / TLS rejection) and the fallback signal to JS mode.
nonisolated enum ProxyFallback {
    static let mitmHandshakeFailed = Notification.Name("corelift.api-ghost.proxyMITMHandshakeFailed")
    static let hostKey = "host"

    /// True for TLS/certificate failures that indicate the proxy's MITM leaf was rejected — the anti-MITM signal.
    /// Plain connectivity errors (host unreachable, connection lost) are excluded: they fail in JS mode too, so they are not breakage.
    static func isMITMHandshakeFailure(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return tlsFailureCodes.contains(nsError.code)
    }

    static func failingHost(_ error: Error) -> String? {
        ((error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.host
    }

    private static let tlsFailureCodes: Set<Int> = [
        NSURLErrorSecureConnectionFailed,
        NSURLErrorServerCertificateUntrusted,
        NSURLErrorServerCertificateHasBadDate,
        NSURLErrorServerCertificateHasUnknownRoot,
        NSURLErrorServerCertificateNotYetValid,
        NSURLErrorClientCertificateRejected,
        NSURLErrorClientCertificateRequired
    ]
}
