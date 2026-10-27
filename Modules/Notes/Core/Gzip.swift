import Compression
import Foundation

/// Gzip decompression with the system Compression framework: the header is parsed here and the
/// raw deflate stream inflated with COMPRESSION_ZLIB (which is RFC 1951 deflate).
enum Gzip {
    /// Upper bound on the inflated size, so a hostile stream cannot exhaust memory.
    static let maxOutput = 512 * 1024 * 1024

    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 2, bytes[0] == 0x1F, bytes[1] == 0x8B else { throw NoteStoreDecoderError.notGzip }
        guard bytes.count >= 18, bytes[2] == 8 else { throw NoteStoreDecoderError.malformed("gzip header") }
        let flags = bytes[3]
        var position = 10
        if flags & 0x04 != 0 {   // FEXTRA
            guard position + 2 <= bytes.count else { throw NoteStoreDecoderError.malformed("gzip extra") }
            position += 2 + Int(bytes[position]) + Int(bytes[position + 1]) << 8
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {   // FNAME, FCOMMENT: zero-terminated
            guard let end = bytes[min(position, bytes.count)...].firstIndex(of: 0) else { throw NoteStoreDecoderError.malformed("gzip header") }
            position = end + 1
        }
        if flags & 0x02 != 0 { position += 2 }   // FHCRC
        let trailer = bytes.count - 8
        guard position <= trailer else { throw NoteStoreDecoderError.malformed("gzip truncated") }
        let output = try inflate(Array(bytes[position..<trailer]))
        // The trailer's ISIZE is the inflated size modulo 2^32; the CRC is not checked.
        let isize = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[trailer + 4 + $1]) << UInt32(8 * $1) }
        guard UInt32(truncatingIfNeeded: output.count) == isize else { throw NoteStoreDecoderError.malformed("gzip size mismatch") }
        return output
    }

    private static func inflate(_ input: [UInt8]) throws -> Data {
        let bufferSize = 64 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destination.deallocate() }
        // Placeholder pointers: they are replaced before the first process call.
        var stream = compression_stream(dst_ptr: destination, dst_size: 0, src_ptr: destination, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw NoteStoreDecoderError.malformed("inflate init")
        }
        defer { compression_stream_destroy(&stream) }
        var output = Data()
        return try input.withUnsafeBufferPointer { source in
            stream.src_ptr = source.baseAddress ?? UnsafePointer(destination)
            stream.src_size = source.count
            while true {
                stream.dst_ptr = destination
                stream.dst_size = bufferSize
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                output.append(destination, count: bufferSize - stream.dst_size)
                guard output.count <= maxOutput else { throw NoteStoreDecoderError.malformed("gzip output too large") }
                switch status {
                case COMPRESSION_STATUS_END: return output
                case COMPRESSION_STATUS_OK:
                    // Output space left and no input left means the deflate stream was cut short.
                    if stream.dst_size > 0 && stream.src_size == 0 { throw NoteStoreDecoderError.malformed("gzip truncated") }
                default: throw NoteStoreDecoderError.malformed("inflate failed")
                }
            }
        }
    }
}
