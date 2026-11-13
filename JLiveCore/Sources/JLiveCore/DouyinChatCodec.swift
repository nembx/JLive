// Protocol field mappings adapted from dart_simple_live's douyin.proto.
// Copyright (C) 2023-2025 xiaoyaocz. GPL-3.0-or-later. See LICENSE.
import Foundation
import zlib

enum DouyinChatCodec {
    static let maxPayloadSize = 4 * 1024 * 1024
    static var heartbeat: Data { packet(type: "hb") }

    static func packet(type: String, logID: UInt64 = 0, payload: Data = Data()) -> Data {
        var result = ProtoWriter()
        if logID != 0 { result.integer(logID, field: 2) }
        result.bytes(Data(type.utf8), field: 7)
        if !payload.isEmpty { result.bytes(payload, field: 8) }
        return result.data
    }

    static func process(_ data: Data) throws -> LiveChatFrame {
        let frame = try ProtoFields(data)
        guard let payload = frame.bytes(8), !payload.isEmpty else { return LiveChatFrame(events: []) }
        let encoding = frame.string(6)
        let isGzip = payload.starts(with: [0x1f, 0x8b])
        // The live server uses "pb" for protobuf, independently of gzip compression.
        guard ["", "pb", "gzip", "identity"].contains(encoding) else { throw LiveError.invalidResponse }
        let response = try ProtoFields(isGzip || encoding == "gzip" ? gunzip(payload) : payload)
        var replies: [Data] = []
        if response.integer(9) != 0 {
            replies = [packet(type: "ack", logID: frame.integer(2), payload: response.bytes(5) ?? Data())]
        }
        var events: [LiveChatEvent] = [.connected]
        for bytes in response.allBytes(1) {
            let message = try ProtoFields(bytes)
            guard message.string(1) == "WebcastChatMessage", let payload = message.bytes(2) else { continue }
            let chat = try ProtoFields(payload)
            let content = chat.string(3)
            guard !content.isEmpty else { continue }
            let user = try ProtoFields(chat.bytes(2) ?? Data())
            events.append(.message(LiveChatMessage(kind: .chat, userName: user.string(3), text: content)))
        }
        return LiveChatFrame(events: events, replies: replies)
    }

    /// zlib handles optional gzip headers and checks both CRC and uncompressed size.
    /// Limit output independently of the untrusted trailer to bound decompression memory.
    private static func gunzip(_ input: Data) throws -> Data {
        guard input.count <= maxPayloadSize else { throw LiveError.invalidResponse }
        var stream = z_stream()
        guard inflateInit2_(&stream, 15 + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw LiveError.invalidResponse
        }
        defer { inflateEnd(&stream) }
        return try input.withUnsafeBytes { bytes in
            stream.next_in = UnsafeMutablePointer(mutating: bytes.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            var result = Data()
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
                let status = buffer.withUnsafeMutableBytes { output in
                    stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(output.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let count = buffer.count - Int(stream.avail_out)
                guard result.count + count <= maxPayloadSize else { throw LiveError.invalidResponse }
                result.append(contentsOf: buffer.prefix(count))
                if status == Z_STREAM_END {
                    guard stream.avail_in == 0 else { throw LiveError.invalidResponse }
                    return result
                }
                guard status == Z_OK, count > 0 else { throw LiveError.invalidResponse }
            }
        }
    }
}

/// Flat protobuf reader. Callers explicitly read nested messages, keeping depth bounded.
struct ProtoFields {
    private enum Value { case integer(UInt64), bytes(Data) }
    private var fields: [Int: [Value]] = [:]

    init(_ data: Data) throws {
        guard data.count <= DouyinChatCodec.maxPayloadSize else { throw LiveError.invalidResponse }
        let bytes = Array(data)
        var offset = 0
        var count = 0
        func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for index in 0..<10 {
                guard offset < bytes.count else { throw LiveError.invalidResponse }
                let byte = bytes[offset]
                offset += 1
                if index == 9, byte > 1 { throw LiveError.invalidResponse }
                value |= UInt64(byte & 0x7f) << (index * 7)
                if byte & 0x80 == 0 { return value }
            }
            throw LiveError.invalidResponse
        }
        func skip(_ size: Int) throws {
            guard size <= bytes.count - offset else { throw LiveError.invalidResponse }
            offset += size
        }
        while offset < bytes.count {
            count += 1
            guard count <= 4096 else { throw LiveError.invalidResponse }
            let tag = try varint()
            let number = tag >> 3
            guard number > 0, number <= 0x1fffffff else { throw LiveError.invalidResponse }
            let field = Int(number)
            switch tag & 7 {
            case 0: fields[field, default: []].append(.integer(try varint()))
            case 1: try skip(8)
            case 2:
                let length = try varint()
                guard length <= UInt64(bytes.count - offset) else { throw LiveError.invalidResponse }
                fields[field, default: []].append(.bytes(Data(bytes[offset..<(offset + Int(length))])))
                offset += Int(length)
            case 5: try skip(4)
            default: throw LiveError.invalidResponse
            }
        }
    }

    func integer(_ field: Int) -> UInt64 {
        guard case .integer(let value) = fields[field]?.last else { return 0 }
        return value
    }
    func bytes(_ field: Int) -> Data? {
        guard case .bytes(let value) = fields[field]?.last else { return nil }
        return value
    }
    func allBytes(_ field: Int) -> [Data] {
        (fields[field] ?? []).compactMap { if case .bytes(let value) = $0 { value } else { nil } }
    }
    func string(_ field: Int) -> String { bytes(field).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
}

struct ProtoWriter {
    private(set) var data = Data()

    private mutating func varint(_ value: UInt64) {
        var remaining = value
        while remaining >= 0x80 {
            data.append(UInt8(remaining & 0x7f) | 0x80)
            remaining >>= 7
        }
        data.append(UInt8(remaining))
    }
    mutating func integer(_ value: UInt64, field: Int) {
        varint(UInt64(field) << 3)
        varint(value)
    }
    mutating func bytes(_ value: Data, field: Int) {
        varint(UInt64(field) << 3 | 2)
        varint(UInt64(value.count))
        data.append(value)
    }
}
