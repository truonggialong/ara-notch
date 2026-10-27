import Foundation

/// Builds protobuf messages for tests (the app only reads protobuf).
struct ProtobufWriter {
    private(set) var data = Data()

    private mutating func varint(_ value: UInt64) {
        var v = value
        while v >= 0x80 {
            data.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
    }

    mutating func varint(_ field: Int, _ value: UInt64) {
        varint(UInt64(field << 3))
        varint(value)
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        varint(UInt64(field << 3 | 2))
        varint(UInt64(value.count))
        data.append(value)
    }

    mutating func string(_ field: Int, _ value: String) { bytes(field, Data(value.utf8)) }

    mutating func message(_ field: Int, _ build: (inout ProtobufWriter) -> Void) {
        var inner = ProtobufWriter()
        build(&inner)
        bytes(field, inner.data)
    }

    mutating func fixed32(_ field: Int, _ value: UInt32) {
        varint(UInt64(field << 3 | 5))
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func fixed64(_ field: Int, _ value: UInt64) {
        varint(UInt64(field << 3 | 1))
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    /// Raw bytes with no framing, for building malformed input.
    mutating func raw(_ value: [UInt8]) { data.append(contentsOf: value) }
}
