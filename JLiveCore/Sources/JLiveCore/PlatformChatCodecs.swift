// Wire formats adapted from dart_simple_live. Copyright (C) 2023-2025 xiaoyaocz.
// GPL-3.0-or-later. See LICENSE.
import Foundation

public enum DouyuChatCodec {
    public static func handshake(roomID: Int) -> Data {
        packet("type@=loginreq/roomid@=\(roomID)/") + packet("type@=joingroup/rid@=\(roomID)/gid@=-9999/")
    }

    public static func packet(_ body: String) -> Data {
        let bytes = Data(body.utf8)
        var data = Data()
        let length = UInt32(bytes.count + 9)
        for value in [length, length] {
            for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8(truncatingIfNeeded: value >> shift)) }
        }
        data.append(contentsOf: [0xb1, 0x02, 0, 0])
        data.append(bytes)
        data.append(0)
        return data
    }

    public static func decode(_ frame: Data) -> [LiveChatEvent] {
        let data = Data(frame)
        var offset = 0
        var result: [LiveChatEvent] = []
        while data.count - offset >= 13 {
            let length = (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[offset + $1]) << ($1 * 8) }
            let duplicate = (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[offset + 4 + $1]) << ($1 * 8) }
            guard length == duplicate, length >= 9, length <= data.count - offset - 4 else { break }
            let end = offset + Int(length) + 4
            guard data[end - 1] == 0 else { break }
            let body = String(decoding: data[(offset + 12)..<(end - 1)], as: UTF8.self)
            offset = end
            var fields: [String: String] = [:]
            for item in body.split(separator: "/") {
                guard let split = item.range(of: "@=") else { continue }
                fields[String(item[..<split.lowerBound])] = String(item[split.upperBound...])
                    .replacingOccurrences(of: "@S", with: "/").replacingOccurrences(of: "@A", with: "@")
            }
            switch fields["type"] {
            case "loginres": result.append(.connected)
            case "chatmsg":
                guard let text = fields["txt"], !text.isEmpty, fields["dms"] != nil else { continue }
                let colors: [UInt32] = [0xFFFFFF, 0xFF0000, 0x1E87F0, 0x7AC84B, 0xFF7F00, 0x9B39F4, 0xFF69B4]
                let color = Int(fields["col"] ?? "") ?? 0
                result.append(.message(LiveChatMessage(kind: .chat, userName: fields["nn"] ?? "观众", text: text,
                    color: colors.indices.contains(color) ? colors[color] : nil)))
            default: break
            }
        }
        return result
    }
}

public enum HuyaChatCodec {
    public static func handshake(uid: Int64, top: Int64, sub: Int64) -> Data {
        var user = TarsWriter()
        user.integer(uid, tag: 0)
        user.integer(1, tag: 1)
        user.string("", tag: 2)
        user.string("", tag: 3)
        user.integer(top, tag: 4)
        user.integer(sub, tag: 5)
        user.integer(0, tag: 6)
        user.integer(0, tag: 7)
        var command = TarsWriter()
        command.integer(1, tag: 0)
        command.bytes(user.data, tag: 1)
        return command.data
    }

    public static func decode(_ frame: Data) throws -> [LiveChatEvent] {
        var reader = TarsReader(data: Data(frame))
        let command = try reader.fields()
        if command[0]?.int == 2 { return [.connected] }
        guard command[0]?.int == 7, let raw = command[1]?.bytes else { return [] }
        var pushReader = TarsReader(data: raw)
        let push = try pushReader.fields()
        guard push[1]?.int == 1400, let rawMessage = push[2]?.bytes else { return [] }
        var messageReader = TarsReader(data: rawMessage)
        let message = try messageReader.fields()
        guard let text = message[3]?.string, !text.isEmpty else { return [] }
        let name = message[0]?.fields?[2]?.string ?? "观众"
        let color = message[6]?.fields?[0]?.int ?? 0
        return [.message(LiveChatMessage(kind: .chat, userName: name, text: text,
            color: color > 0 ? UInt32(truncatingIfNeeded: color) & 0xffffff : nil))]
    }
}

indirect enum TarsValue {
    case integer(Int64), text(String), data(Data), structure([Int: TarsValue]), skipped
    var int: Int64? { if case .integer(let value) = self { value } else { nil } }
    var string: String? { if case .text(let value) = self { value } else { nil } }
    var bytes: Data? { if case .data(let value) = self { value } else { nil } }
    var fields: [Int: TarsValue]? { if case .structure(let value) = self { value } else { nil } }
}

struct TarsWriter {
    var data = Data()
    mutating func head(_ type: UInt8, tag: Int) {
        if tag < 15 { data.append(UInt8(tag) << 4 | type) }
        else { data.append(0xf0 | type); data.append(UInt8(tag)) }
    }
    mutating func integer(_ value: Int64, tag: Int) {
        if value == 0 { head(12, tag: tag); return }
        let count = value >= -128 && value <= 127 ? 1 : value >= -32768 && value <= 32767 ? 2 : value >= Int32.min && value <= Int32.max ? 4 : 8
        head(count == 1 ? 0 : count == 2 ? 1 : count == 4 ? 2 : 3, tag: tag)
        for shift in stride(from: (count - 1) * 8, through: 0, by: -8) { data.append(UInt8(truncatingIfNeeded: value >> shift)) }
    }
    mutating func string(_ value: String, tag: Int) {
        let bytes = Data(value.utf8)
        head(6, tag: tag)
        data.append(UInt8(bytes.count))
        data.append(bytes)
    }
    mutating func bytes(_ value: Data, tag: Int) {
        head(13, tag: tag); head(0, tag: 0)
        integer(Int64(value.count), tag: 0)
        data.append(value)
    }
}

struct TarsReader {
    let data: Data
    var offset = 0
    mutating func take(_ count: Int) throws -> Data {
        guard count >= 0, count <= data.count - offset else { throw LiveError.invalidResponse }
        defer { offset += count }
        return Data(data[offset..<(offset + count)])
    }
    mutating func head() throws -> (Int, UInt8) {
        let byte = try take(1)[0]
        return (byte >> 4 == 15 ? Int(try take(1)[0]) : Int(byte >> 4), byte & 15)
    }
    mutating func fields(depth: Int = 0) throws -> [Int: TarsValue] {
        guard depth < 16 else { throw LiveError.invalidResponse }
        var result: [Int: TarsValue] = [:]
        while offset < data.count {
            let (tag, type) = try head()
            if type == 11 { break }
            result[tag] = try value(type, depth: depth)
        }
        return result
    }
    mutating func number(_ count: Int) throws -> Int64 {
        let raw = try take(count)
        var value: Int64 = raw.first.map { $0 & 0x80 == 0 ? 0 : -1 } ?? 0
        for byte in raw { value = (value << 8) | Int64(byte) }
        return value
    }
    mutating func count() throws -> Int {
        let (_, type) = try head()
        guard let size = try value(type, depth: 0).int, size >= 0, size <= 10_000 else { throw LiveError.invalidResponse }
        return Int(size)
    }
    mutating func value(_ type: UInt8, depth: Int) throws -> TarsValue {
        guard depth < 16 else { throw LiveError.invalidResponse }
        switch type {
        case 0...3: return .integer(try number(1 << Int(type)))
        case 4, 5: _ = try take(type == 4 ? 4 : 8); return .skipped
        case 6: let n = Int(try take(1)[0]); return .text(String(decoding: try take(n), as: UTF8.self))
        case 7:
            let n = try number(4)
            guard n >= 0, n <= data.count else { throw LiveError.invalidResponse }
            return .text(String(decoding: try take(Int(n)), as: UTF8.self))
        case 8, 9:
            let n = try count() * (type == 8 ? 2 : 1)
            for _ in 0..<n { let (_, t) = try head(); _ = try value(t, depth: depth + 1) }
            return .skipped
        case 10: return .structure(try fields(depth: depth + 1))
        case 12: return .integer(0)
        case 13:
            let (_, itemType) = try head()
            guard itemType == 0 else { throw LiveError.invalidResponse }
            return .data(try take(count()))
        default: throw LiveError.invalidResponse
        }
    }
}
