// Platform stream signing and mappings adapted from dart_simple_live.
// Copyright (C) 2023-2025 xiaoyaocz. GPL-3.0-or-later. See LICENSE.
import Foundation
import CryptoKit
import JavaScriptCore

func md5(_ value: String) -> String {
    Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}

func capture(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[range])
}

extension HuyaProvider {
    static let mobileAgent = "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36"

    private func roomData(_ id: String) async throws -> (JSONValue, String) {
        let html = try await client.text(try endpoint("https://m.huya.com/\(id)"), headers: ["User-Agent": Self.mobileAgent])
        guard let raw = capture(#"window\.HNF_GLOBAL_INIT\s*=\s*(\{[\s\S]*?\})\s*;?\s*</script>"#, in: html) else {
            throw LiveError.invalidResponse
        }
        let clean = raw.replacingOccurrences(of: #"function\s*[^\(]*\([^\)]*\)\s*\{[^\}]*\}"#, with: "\"\"", options: .regularExpression)
        return (try JSONDecoder().decode(JSONValue.self, from: Data(clean.utf8)), html)
    }

    public func detail(room: LiveRoom) async throws -> LiveRoom {
        let (data, _) = try await roomData(room.roomID)
        let live = data["roomInfo"]["tLiveInfo"]
        let profile = data["roomInfo"]["tProfileInfo"]
        guard !live["lProfileRoom"].string.isEmpty else { throw LiveError.invalidResponse }
        return LiveRoom(platform: .huya, roomID: live["lProfileRoom"].string,
            title: live["sIntroduction"].string.isEmpty ? live["sRoomName"].string : live["sIntroduction"].string,
            streamer: profile["sNick"].string, coverURL: imageURL(live["sScreenshot"].string),
            avatarURL: imageURL(profile["sAvatar180"].string), viewerCount: live["lTotalCount"].int,
            category: live["sGameFullName"].string, isLive: data["roomInfo"]["eLiveStatus"].int == 2)
    }

    public func playback(roomID: String, quality: Int?) async throws -> PlaybackInfo {
        let (data, _) = try await roomData(roomID)
        guard data["roomInfo"]["eLiveStatus"].int == 2 else { throw LiveError.offline }
        return try Self.parsePlayback(data, quality: quality)
    }

    static func parsePlayback(_ data: JSONValue, quality: Int?, timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000), uid: Int64 = Int64.random(in: 1_400_000_000_000...1_400_009_999_999)) throws -> PlaybackInfo {
        let stream = data["roomInfo"]["tLiveInfo"]["tLiveStreamInfo"]
        // The mobile HLS service provides AVC streams; avoid the HDR variants advertised for desktop clients.
        var seen = Set<Int>()
        var qualities = stream["vBitRateInfo"]["value"].array.compactMap { item -> StreamQuality? in
            let id = item["iBitRate"].int, name = item["sDisplayName"].string
            guard !name.contains("HDR"), !name.isEmpty, seen.insert(id).inserted else { return nil }
            return StreamQuality(id: id, name: name)
        }
        if qualities.isEmpty { qualities = [StreamQuality(id: 0, name: "原画")] }
        let selected = quality.flatMap { q in qualities.first { $0.id == q }?.id } ?? (qualities.first { $0.id == 0 }?.id ?? qualities[0].id)
        var urls = Set<URL>()
        let lines = try stream["vStreamInfo"]["value"].array.compactMap { item -> StreamLine? in
            guard !item["sHlsUrl"].string.isEmpty, !item["sStreamName"].string.isEmpty else { return nil }
            let params = try Self.antiCode(item["sHlsAntiCode"].string, stream: item["sStreamName"].string, uid: uid, timestamp: timestamp)
            var query = params
            query["codec"] = "264"
            if selected > 0 { query["ratio"] = String(selected) }
            let base = item["sHlsUrl"].string.replacingOccurrences(of: "http://", with: "https://")
            let url = try endpoint("\(base)/\(item["sStreamName"].string).m3u8", query)
            guard urls.insert(url).inserted else { return nil }
            return StreamLine(url: url)
        }
        guard !lines.isEmpty else { throw LiveError.noPlayableStream }
        return PlaybackInfo(lines: lines, qualities: qualities, currentQuality: selected,
            headers: ["User-Agent": Self.mobileAgent, "Referer": "https://m.huya.com/"])
    }

    static func antiCode(_ input: String, stream: String, uid: Int64, timestamp: Int64) throws -> [String: String] {
        guard let items = URLComponents(string: "https://huya.com/?\(input)")?.queryItems else { throw LiveError.invalidResponse }
        var query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        guard let fm = query["fm"] else { return query }
        guard let bytes = Data(base64Encoded: fm), let decoded = String(data: bytes, encoding: .utf8),
              let prefix = decoded.split(separator: "_").first, let time = query["wsTime"] else { throw LiveError.invalidResponse }
        let type = query["ctype"] ?? "tars_mobile", platform = query["t"] ?? "103"
        let sequence = uid + timestamp
        let converted = platform == "103" ? UInt64(uid) : (UInt64(uid) << 8 | UInt64(uid) >> 56)
        let hash = md5("\(sequence)|\(type)|\(platform)")
        query["wsSecret"] = md5("\(prefix)_\(converted)_\(stream)_\(hash)_\(time)")
        query["seqid"] = String(sequence)
        query["ver"] = "1"
        query.removeValue(forKey: "fm")
        if platform == "103" {
            query["uid"] = String(uid)
            query["uuid"] = String(UInt32.random(in: 1...UInt32.max))
        } else { query["u"] = String(converted) }
        return query
    }

    public func chat(roomID: String) async throws -> LiveChatEndpoint {
        let (data, html) = try await roomData(roomID)
        let uid = data["roomInfo"]["tLiveInfo"]["lYyid"].int
        let top = Int(capture(#"lChannelId":([0-9]+)"#, in: html) ?? "") ?? 0
        let sub = Int(capture(#"lSubChannelId":([0-9]+)"#, in: html) ?? "") ?? top
        guard uid > 0, top > 0 else { throw LiveError.invalidResponse }
        return LiveChatEndpoint(urls: [URL(string: "wss://cdnws.api.huya.com")!],
            headers: ["Origin": "https://www.huya.com", "User-Agent": HTTPClient.userAgent],
            handshake: HuyaChatCodec.handshake(uid: Int64(uid), top: Int64(top), sub: Int64(sub)),
            heartbeat: Data(base64Encoded: "ABQdAAwsNgBM")!, heartbeatInterval: 60,
            decode: { try HuyaChatCodec.decode($0) })
    }
}

extension DouyuProvider {
    public func detail(room: LiveRoom) async throws -> LiveRoom {
        let result = try await client.get(try endpoint("https://www.douyu.com/betard/\(room.roomID)"), headers: ["Referer": room.webURL.absoluteString])
        let info = result["room"]
        guard !info["room_id"].string.isEmpty else { throw LiveError.invalidResponse }
        return LiveRoom(platform: .douyu, roomID: info["room_id"].string, title: info["room_name"].string,
            streamer: info["owner_name"].string, coverURL: imageURL(info["room_pic"].string),
            avatarURL: imageURL(info["owner_avatar"].string), viewerCount: info["room_biz_all"]["hot"].int,
            category: info["second_lvl_name"].string, isLive: info["show_status"].int == 1 && info["videoLoop"].int != 1)
    }

    public func playback(roomID: String, quality: Int?) async throws -> PlaybackInfo {
        let headers = ["Referer": "https://www.douyu.com/\(roomID)", "User-Agent": HTTPClient.userAgent]
        let result = try await client.get(try endpoint("https://www.douyu.com/swf_api/homeH5Enc", ["rids": roomID]), headers: headers)
        let signature = try DouyuSigner.sign(result["data"]["room\(roomID)"].string, roomID: roomID)
        // Mobile ratestream returns HLS instead of the desktop endpoint's FLV stream.
        let body = "\(signature)&ver=219032101&rid=\(roomID)&rate=\(quality ?? 0)"
        let response = try await client.post(try endpoint("https://m.douyu.com/api/room/ratestream"), body: body, headers: headers)
        return try Self.parsePlayback(response, quality: quality, headers: headers)
    }

    static func parsePlayback(_ response: JSONValue, quality: Int?, headers: [String: String]) throws -> PlaybackInfo {
        guard response["code"].int == 0 else { throw LiveError.platform(response["msg"].string) }
        let data = response["data"]
        let raw = data["url"].string.replacingOccurrences(of: "&amp;", with: "&")
        guard let url = URL(string: raw), ["http", "https"].contains(url.scheme ?? ""), url.path.contains(".m3u8") else {
            throw LiveError.noPlayableStream
        }
        var qualities = data["multirates"].array.map { StreamQuality(id: $0["rate"].int, name: $0["name"].string) }
        if qualities.isEmpty { qualities = [StreamQuality(id: data["rate"].int, name: "自动画质")] }
        return PlaybackInfo(lines: [StreamLine(url: url)], qualities: qualities,
            currentQuality: data["rate"].isNull ? (quality ?? 0) : data["rate"].int, headers: headers)
    }

    public func chat(roomID: String) async throws -> LiveChatEndpoint {
        guard let id = Int(roomID), id > 0 else { throw LiveError.invalidResponse }
        return LiveChatEndpoint(urls: [URL(string: "wss://danmuproxy.douyu.com:8506/")!, URL(string: "wss://danmuproxy.douyu.com:8503/")!],
            headers: ["Origin": "https://www.douyu.com"], handshake: DouyuChatCodec.handshake(roomID: id),
            heartbeat: DouyuChatCodec.packet("type@=mrkl/"), heartbeatInterval: 45,
            decode: { DouyuChatCodec.decode($0) })
    }
}

enum DouyuSigner {
    static func sign(_ script: String, roomID: String, timestamp: Int = Int(Date().timeIntervalSince1970)) throws -> String {
        guard script.count < 200_000, !script.isEmpty, let context = JSContext() else { throw LiveError.invalidResponse }
        // Isolated JavaScriptCore context: no browser, filesystem or network objects are exposed.
        let hash: @convention(block) (String) -> String = { md5($0) }
        context.setObject(hash, forKeyedSubscript: "jliveMD5" as NSString)
        context.evaluateScript("var CryptoJS = { MD5: function(s) { var h = jliveMD5(String(s)); return { toString: function() { return h; } }; } };")
        context.evaluateScript(script)
        guard context.exception == nil, let function = context.objectForKeyedSubscript("ub98484234"), !function.isUndefined else { throw LiveError.invalidResponse }
        let value = function.call(withArguments: [roomID, "10000000000000000000000000001501", String(timestamp)])?.toString() ?? ""
        guard context.exception == nil, value.contains("sign="), value.count < 4096 else { throw LiveError.invalidResponse }
        return value
    }
}
