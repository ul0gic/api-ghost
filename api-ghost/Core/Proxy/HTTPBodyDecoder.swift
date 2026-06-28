import Compression
import Foundation

/// Decodes Content-Encoding for captured proxy bodies. Fails safe — any malformed/unsupported stream returns the raw bytes.
/// brotli (`br`) is unsupported (no Compression-framework codec / dependency) and stored raw — see ENH-001.
enum HTTPBodyDecoder {
    static func decode(_ body: Data, contentEncoding: String?, truncated: Bool) -> Data {
        guard !body.isEmpty, let encoding = normalized(contentEncoding) else { return body }
        switch encoding {
        case "gzip", "x-gzip":
            guard let deflate = stripGzipHeader(body) else { return body }
            return inflate(deflate, truncated: truncated) ?? body
        case "deflate":
            return inflateDeflate(body, truncated: truncated) ?? body
        default:
            return body
        }
    }

    private static func normalized(_ contentEncoding: String?) -> String? {
        guard let value = contentEncoding?.trimmingCharacters(in: .whitespaces).lowercased(), !value.isEmpty else {
            return nil
        }
        return value == "identity" ? nil : value
    }
}

// MARK: - Raw DEFLATE (RFC 1951) inflate via Compression framework

private extension HTTPBodyDecoder {
    /// `Content-Encoding: deflate` is usually zlib-wrapped (RFC 1950); COMPRESSION_ZLIB needs raw DEFLATE (RFC 1951).
    static func inflateDeflate(_ body: Data, truncated: Bool) -> Data? {
        if looksZlibWrapped(body), let stripped = stripZlibHeader(body),
           let inflated = inflate(stripped, truncated: truncated) {
            return inflated
        }
        return inflate(body, truncated: truncated)
    }

    static func looksZlibWrapped(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let cmf = Int(data[data.startIndex])
        let flg = Int(data[data.startIndex + 1])
        return (cmf & 0x0F) == 0x08 && (cmf << 8 | flg).isMultiple(of: 31)
    }

    static func inflate(_ source: Data, truncated: Bool) -> Data? {
        guard !source.isEmpty else { return nil }
        let bufferSize = 64 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destination.deallocate() }

        var stream = compression_stream(
            dst_ptr: destination,
            dst_size: bufferSize,
            src_ptr: UnsafePointer(destination),
            src_size: 0,
            state: nil
        )
        let initStatus = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard initStatus == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(&stream) }

        // A truncated body is an incomplete DEFLATE stream; FINALIZE would reject it, so decode best-effort without it.
        let flags = truncated ? 0 : Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
        return source.withUnsafeBytes { raw -> Data? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            stream.src_ptr = base
            stream.src_size = source.count

            var output = Data()
            while true {
                stream.dst_ptr = destination
                stream.dst_size = bufferSize
                let status = compression_stream_process(&stream, flags)
                let produced = bufferSize - stream.dst_size
                if produced > 0 { output.append(destination, count: produced) }

                switch status {
                case COMPRESSION_STATUS_END:
                    return output
                case COMPRESSION_STATUS_OK:
                    // Ran out of input without END: complete only if truncated, else a misparse — fail to the caller's fallback.
                    if produced == 0, stream.src_size == 0 { return truncated ? output : nil }
                default:
                    return output.isEmpty ? nil : output
                }
            }
        }
    }
}

// MARK: - Header framing

private extension HTTPBodyDecoder {
    static func stripGzipHeader(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 0x08 else { return nil }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 {
            guard index + 2 <= bytes.count else { return nil }
            index += 2 + (Int(bytes[index]) | (Int(bytes[index + 1]) << 8))
        }
        if flags & 0x08 != 0 { index = skipCString(bytes, from: index) }
        if flags & 0x10 != 0 { index = skipCString(bytes, from: index) }
        if flags & 0x02 != 0 { index += 2 }
        guard index < data.count else { return nil }
        return data.subdata(in: index..<data.count)
    }

    static func stripZlibHeader(_ data: Data) -> Data? {
        guard data.count > 2 else { return nil }
        return data.subdata(in: 2..<data.count)
    }

    static func skipCString(_ bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        return index + 1
    }
}
