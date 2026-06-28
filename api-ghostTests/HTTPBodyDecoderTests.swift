import Compression
import Foundation
import Testing

@testable import APIGhost

// MARK: - Content-Encoding decode (4.2.9)

/// Pure, singleton-free: every case is a round-trip or a fail-safe assertion against a known payload.
@Suite
struct HTTPBodyDecoderTests {
    private static let payload = Data(
        String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 64).utf8
    )

    // MARK: gzip

    @Test
    func gzipRoundTrips() {
        let encoded = GzipFixture.gzip(Self.payload)
        let decoded = HTTPBodyDecoder.decode(encoded, contentEncoding: "gzip", truncated: false)
        #expect(decoded == Self.payload)
    }

    @Test
    func gzipIsCaseAndAliasInsensitive() {
        let encoded = GzipFixture.gzip(Self.payload)
        #expect(HTTPBodyDecoder.decode(encoded, contentEncoding: "GZIP", truncated: false) == Self.payload)
        #expect(HTTPBodyDecoder.decode(encoded, contentEncoding: " x-gzip ", truncated: false) == Self.payload)
    }

    @Test
    func gzipWithExtraFieldsRoundTrips() {
        let encoded = GzipFixture.gzip(Self.payload, filename: "report.json", comment: "qa", extra: [0x01, 0x02, 0x03])
        let decoded = HTTPBodyDecoder.decode(encoded, contentEncoding: "gzip", truncated: false)
        #expect(decoded == Self.payload)
    }

    // MARK: deflate

    @Test
    func rawDeflateRoundTrips() {
        let encoded = GzipFixture.rawDeflate(Self.payload)
        let decoded = HTTPBodyDecoder.decode(encoded, contentEncoding: "deflate", truncated: false)
        #expect(decoded == Self.payload)
    }

    @Test
    func zlibWrappedDeflateRoundTrips() {
        // Spec-compliant `deflate` is zlib-framed (RFC 1950); the decoder sniffs + strips the zlib header (BUG-003 fixed).
        let encoded = GzipFixture.zlibDeflate(Self.payload)
        let decoded = HTTPBodyDecoder.decode(encoded, contentEncoding: "deflate", truncated: false)
        #expect(decoded == Self.payload)
    }

    @Test
    func decompressionBombIsCappedAtMaxDecodedSize() {
        // 5MB highly-compressible payload; output capped at 64KB regardless of inflated size (SEC-006).
        let big = Data(repeating: 0x41, count: 5 * 1024 * 1024)
        let encoded = GzipFixture.gzip(big)
        let cap = 64 * 1024
        let decoded = HTTPBodyDecoder.decode(encoded, contentEncoding: "gzip", truncated: false, maxDecodedSize: cap)
        #expect(decoded.count <= cap, "decode output must not exceed the cap regardless of inflated size")
    }

    // MARK: passthrough

    @Test
    func identityReturnsRaw() {
        #expect(HTTPBodyDecoder.decode(Self.payload, contentEncoding: "identity", truncated: false) == Self.payload)
    }

    @Test
    func absentEncodingReturnsRaw() {
        #expect(HTTPBodyDecoder.decode(Self.payload, contentEncoding: nil, truncated: false) == Self.payload)
        #expect(HTTPBodyDecoder.decode(Self.payload, contentEncoding: "   ", truncated: false) == Self.payload)
    }

    @Test
    func brotliIsStoredRaw() {
        // No Compression-framework brotli codec — the bytes pass through untouched (ENH-001).
        #expect(HTTPBodyDecoder.decode(Self.payload, contentEncoding: "br", truncated: false) == Self.payload)
    }

    @Test
    func unknownEncodingReturnsRaw() {
        #expect(HTTPBodyDecoder.decode(Self.payload, contentEncoding: "snappy", truncated: false) == Self.payload)
    }

    @Test
    func emptyBodyReturnsEmpty() {
        #expect(HTTPBodyDecoder.decode(Data(), contentEncoding: "gzip", truncated: false).isEmpty)
    }

    // MARK: fail-safe

    @Test
    func malformedGzipReturnsRaw() {
        let garbage = Data([0x1F, 0x8B, 0x08, 0x00, 0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00, 0x11, 0x22, 0x33])
        let decoded = HTTPBodyDecoder.decode(garbage, contentEncoding: "gzip", truncated: false)
        #expect(decoded == garbage, "an undecodable gzip stream falls back to the raw bytes, never crashes")
    }

    @Test
    func gzipMagicWithoutDeflatePayloadReturnsRaw() {
        let shortHeaderOnly = GzipFixture.gzipHeader + Data([0x00])
        let decoded = HTTPBodyDecoder.decode(shortHeaderOnly, contentEncoding: "gzip", truncated: false)
        #expect(decoded == shortHeaderOnly)
    }

    @Test
    func malformedDeflateNeverCrashes() {
        // The deflate path's only firm guarantee is no-crash: a corrupt stream may yield best-effort bytes rather
        // than the raw input (the greedy first-inflate keeps partial output) — see BUG-003. It must never trap.
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        let decoded = HTTPBodyDecoder.decode(garbage, contentEncoding: "deflate", truncated: false)
        #expect(decoded.count <= garbage.count, "decode completes and returns a bounded result, never crashes")
    }

    // MARK: truncation

    @Test
    func truncatedGzipDecodesBestEffortPrefix() {
        let full = GzipFixture.gzip(Self.payload)
        let cut = full.prefix(full.count - 24)
        let decoded = HTTPBodyDecoder.decode(Data(cut), contentEncoding: "gzip", truncated: true)
        // Best-effort: either a recovered prefix of the original, or the raw bytes if nothing inflated. Never a crash.
        #expect(Self.payload.starts(with: decoded) || decoded == Data(cut))
        #expect(!decoded.isEmpty)
    }

    @Test
    func truncatedDeflateDecodesBestEffortPrefix() {
        let full = GzipFixture.rawDeflate(Self.payload)
        let cut = Data(full.prefix(full.count - 8))
        let decoded = HTTPBodyDecoder.decode(cut, contentEncoding: "deflate", truncated: true)
        #expect(Self.payload.starts(with: decoded) || decoded == cut)
    }
}

// MARK: - Compression fixtures

/// Produces real gzip / deflate streams the decoder must accept. Apple's `COMPRESSION_ZLIB` is raw DEFLATE (RFC 1951).
enum GzipFixture {
    static let gzipHeader = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])

    static func rawDeflate(_ data: Data) -> Data {
        let capacity = data.count + 64 * 1024
        var destination = [UInt8](repeating: 0, count: capacity)
        let written = data.withUnsafeBytes { src -> Int in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(&destination, capacity, base, data.count, nil, COMPRESSION_ZLIB)
        }
        return Data(destination.prefix(written))
    }

    static func zlibDeflate(_ data: Data) -> Data {
        // zlib header (CMF=0x78, FLG=0x9C) + raw DEFLATE; the decoder strips the 2-byte header on its fallback path.
        Data([0x78, 0x9C]) + rawDeflate(data)
    }

    static func gzip(_ data: Data, filename: String? = nil, comment: String? = nil, extra: [UInt8]? = nil) -> Data {
        var flags: UInt8 = 0
        var header = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])
        var optional = Data()
        if let extra {
            flags |= 0x04
            optional.append(UInt8(extra.count & 0xFF))
            optional.append(UInt8((extra.count >> 8) & 0xFF))
            optional.append(contentsOf: extra)
        }
        if let filename {
            flags |= 0x08
            optional.append(contentsOf: Array(filename.utf8))
            optional.append(0x00)
        }
        if let comment {
            flags |= 0x10
            optional.append(contentsOf: Array(comment.utf8))
            optional.append(0x00)
        }
        header[3] = flags
        return header + optional + rawDeflate(data)
    }
}
