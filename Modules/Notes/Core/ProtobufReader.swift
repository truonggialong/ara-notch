import Foundation

enum ProtobufValue {
    case varint(UInt64)
    case bytes(Data)
    case fixed32(UInt32)
    case fixed64(UInt64)
}

/// Reads the fields of one protobuf message in order. Every length is bounds-checked, so hostile
/// input throws `NoteStoreDecoderError.malformed` instead of crashing.
struct ProtobufReader {
    private let data: Data
    private var position: Data.Index

    init(_ data: Data) {
        self.data = data
        position = data.startIndex
    }

    /// The next field, or nil at the end of the message.
    mutating func next() throws -> (field: Int, value: ProtobufValue)? {
        guard position < data.endIndex else { return nil }
        let tag = try readVarint()
        let field = tag >> 3
        guard field > 0, field <= UInt64(Int32.max) else { throw NoteStoreDecoderError.malformed("bad field number") }
        switch tag & 7 {
        case 0:
            return (Int(field), .varint(try readVarint()))
        case 1:
            return (Int(field), .fixed64(UInt64(try readFixed(8))))
        case 2:
            let length = try readVarint()
            guard length <= UInt64(data.endIndex - position) else { throw NoteStoreDecoderError.malformed("length past end") }
            let end = position + Int(length)
            defer { position = end }
            return (Int(field), .bytes(data.subdata(in: position..<end)))
        case 5:
            return (Int(field), .fixed32(UInt32(try readFixed(4))))
        default:
            throw NoteStoreDecoderError.malformed("unsupported wire type")
        }
    }

    private mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        for index in 0..<10 {
            guard position < data.endIndex else { throw NoteStoreDecoderError.malformed("truncated varint") }
            let byte = data[position]
            position += 1
            result |= UInt64(byte & 0x7F) << UInt64(7 * index)
            if byte & 0x80 == 0 { return result }
        }
        throw NoteStoreDecoderError.malformed("varint too long")
    }

    private mutating func readFixed(_ count: Int) throws -> UInt64 {
        guard data.endIndex - position >= count else { throw NoteStoreDecoderError.malformed("truncated fixed value") }
        var result: UInt64 = 0
        for index in 0..<count { result |= UInt64(data[position + index]) << UInt64(8 * index) }
        position += count
        return result
    }
}
