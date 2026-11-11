// Packet framing and command mapping adapted from dart_simple_live.
// Copyright (C) 2023-2025 xiaoyaocz. GPL-3.0-or-later. See LICENSE.
import Foundation

/// Bilibili live chat wire format: a 16-byte big-endian header followed by a JSON or zlib body.
public enum BilibiliChatCodec {
    public static let fallbackHost = "broadcastlv.chat.bilibili.com"

    private static let headerLength = 16

    private enum Operation {
        static let heartbeat: UInt32 = 2
        static let message: UInt32 = 5
        static let authenticate: UInt32 = 7
        static let authenticated: UInt32 = 8
    }

    /// Join packet for a guest viewer.
    ///
    /// `protover` 2 asks the server for zlib frames, which Foundation can inflate.
    /// The web client asks for version 3, which is brotli.
    public static func handshake(roomID: Int, token: String, buvid: String, uid: Int = 0) throws -> Data {
        let body: [String: Any] = [
            "uid": uid, "roomid": roomID, "protover": 2, "buvid": buvid,
            "platform": "web", "type": 2, "key": token
        ]
        return packet(
            operation: Operation.authenticate,
            body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        )
    }

    public static func heartbeat() -> Data { packet(operation: Operation.heartbeat) }

    public static func packet(operation: UInt32, version: UInt16 = 1, body: Data = Data()) -> Data {
        var data = Data(capacity: headerLength + body.count)
        data.appendBigEndian(UInt32(headerLength + body.count))
        data.appendBigEndian(UInt16(headerLength))
        data.appendBigEndian(version)
        data.appendBigEndian(operation)
        data.appendBigEndian(UInt32(1))
        data.append(body)
        return data
    }

    /// Decodes every packet in a socket frame. Throws when the server rejects the handshake.
    public static func decode(_ frame: Data) throws -> [LiveChatEvent] {
        try decode(frame, depth: 0)
    }

    private static func decode(_ frame: Data, depth: Int) throws -> [LiveChatEvent] {
        var events: [LiveChatEvent] = []
        var offset = frame.startIndex
        while frame.endIndex - offset >= headerLength {
            let length = Int(frame.bigEndian(UInt32.self, at: offset))
            let header = Int(frame.bigEndian(UInt16.self, at: offset + 4))
            let version = frame.bigEndian(UInt16.self, at: offset + 6)
            let operation = frame.bigEndian(UInt32.self, at: offset + 8)
            guard header >= headerLength, length >= header, length <= frame.endIndex - offset else { break }
            let body = frame[(offset + header)..<(offset + length)]
            offset += length

            switch operation {
            case Operation.authenticated:
                if let reply = try? JSONDecoder().decode(JSONValue.self, from: body),
                   !reply["code"].isNull, reply["code"].int != 0 {
                    throw LiveError.platform("弹幕服务器拒绝了连接")
                }
                events.append(.connected)
            case Operation.message where version == 2:
                // A compressed body is a batch of ordinary packets.
                guard depth < 2, let inflated = inflate(body) else { continue }
                events += try decode(inflated, depth: depth + 1)
            case Operation.message where version < 2:
                if let message = message(fromJSON: body) { events.append(.message(message)) }
            default:
                continue
            }
        }
        return events
    }

    static func message(fromJSON body: Data) -> LiveChatMessage? {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: body) else { return nil }
        let command = json["cmd"].string
        // The command can carry a suffix, e.g. "DANMU_MSG:4:0:2:2:2:0".
        if command.hasPrefix("DANMU_MSG") {
            let info = json["info"]
            let text = info[1].string
            guard !text.isEmpty else { return nil }
            let color = info[0][3].int
            return LiveChatMessage(
                kind: .chat, userName: info[2][1].string, text: text,
                color: color > 0 ? UInt32(color & 0xFFFFFF) : nil
            )
        }
        let data = json["data"]
        switch command {
        case "SUPER_CHAT_MESSAGE":
            let text = data["message"].string
            guard !text.isEmpty else { return nil }
            return LiveChatMessage(
                kind: .superChat(price: data["price"].int), userName: data["user_info"]["uname"].string,
                text: text, color: hexColor(data["background_bottom_color"].string)
            )
        case "SEND_GIFT":
            let gift = data["giftName"].string
            guard !gift.isEmpty else { return nil }
            let action = data["action"].string
            return LiveChatMessage(
                kind: .gift, userName: data["uname"].string,
                text: "\(action.isEmpty ? "赠送" : action) \(gift) ×\(max(1, data["num"].int))"
            )
        default:
            return nil
        }
    }

    /// zlib (RFC 1950) wraps a raw DEFLATE stream in a two-byte header; Foundation only decodes the raw stream.
    static func inflate(_ data: Data) -> Data? {
        guard data.count > 2, let method = data.first, method & 0x0F == 8 else { return nil }
        return try? (Data(data.dropFirst(2)) as NSData).decompressed(using: .zlib) as Data
    }

    private static func hexColor(_ value: String) -> UInt32? {
        guard value.hasPrefix("#"), value.count == 7 else { return nil }
        return UInt32(value.dropFirst(), radix: 16)
    }
}

private extension Data {
    func bigEndian<T: FixedWidthInteger>(_ type: T.Type, at index: Index) -> T {
        self[index..<index + MemoryLayout<T>.size].reduce(0 as T) { $0 << 8 | T($1) }
    }

    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}
