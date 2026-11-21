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
        do {
            return try await desktopPlayback(roomID: roomID, quality: quality)
        } catch {
            try Task.checkCancellation()
            return try await mobilePlayback(roomID: roomID, quality: quality)
        }
    }

    private func desktopPlayback(roomID: String, quality: Int?) async throws -> PlaybackInfo {
        let headers = ["Referer": "https://www.douyu.com/\(roomID)", "User-Agent": HTTPClient.userAgent]
        let result = try await client.get(try endpoint("https://www.douyu.com/swf_api/homeH5Enc", ["rids": roomID]), headers: headers)
        let signature = try DouyuSigner.sign(result["data"]["room\(roomID)"].string, roomID: roomID)
        let url = try endpoint("https://www.douyu.com/lapi/live/getH5Play/\(roomID)")
        let metadata = try await client.post(url,
            body: "\(signature)&cdn=&rate=-1&ver=Douyu_223061205&iar=1&ive=1&hevc=0&fa=0", headers: headers)
        guard !metadata["error"].isNull, metadata["error"].int == 0 else { throw LiveError.invalidResponse }
        let cdns = metadata["data"]["cdnsWithName"].array.map { $0["cdn"].string }.filter { !$0.isEmpty }
            .sorted { !$0.hasPrefix("scdn") && $1.hasPrefix("scdn") }
        guard !cdns.isEmpty else { throw LiveError.noPlayableStream }
        let selected = quality ?? metadata["data"]["multirates"].array.first?["rate"].int ?? 0
        for cdn in cdns {
            // Match Simple Live's quality request exactly. The discovery flags belong
            // to the metadata request; adding them here can make the service ignore rate.
            do {
                let response = try await client.post(url, body: "\(signature)&cdn=\(cdn)&rate=\(selected)", headers: headers)
                if let info = try? Self.parseDesktopPlayback(response, quality: selected, headers: headers) { return info }
            } catch { try Task.checkCancellation() }
        }
        throw LiveError.noPlayableStream
    }

    static func parseDesktopPlayback(_ response: JSONValue, quality: Int?, headers: [String: String]) throws -> PlaybackInfo {
        guard !response["error"].isNull, response["error"].int == 0 else { throw LiveError.platform(response["msg"].string) }
        let data = response["data"]
        let raw = (data["rtmp_url"].string + "/" + data["rtmp_live"].string).replacingOccurrences(of: "&amp;", with: "&")
        guard let url = URL(string: raw), ["https", "http"].contains(url.scheme ?? ""), url.host != nil,
              ["flv", "m3u8"].contains(url.pathExtension.lowercased()), !data["rate"].isNull else { throw LiveError.noPlayableStream }
        var seen = Set<Int>()
        let qualities = data["multirates"].array.compactMap { item -> StreamQuality? in
            guard !item["rate"].isNull, !item["name"].string.isEmpty, seen.insert(item["rate"].int).inserted else { return nil }
            return StreamQuality(id: item["rate"].int, name: item["name"].string)
        }
        var actual = data["rate"].int
        if let bitrate = capture(#"_([0-9]+)\.(?:flv|m3u8)$"#, in: url.path).flatMap(Int.init),
           let rendition = data["multirates"].array.first(where: { $0["bit"].int == bitrate }) {
            actual = rendition["rate"].int
        }
        guard let current = qualities.first(where: { $0.id == actual }) else { throw LiveError.invalidResponse }
        let notice = quality.map { $0 != actual } == true ? "斗鱼本次返回\(current.name)，所选画质被平台回退。" : nil
        return PlaybackInfo(lines: [StreamLine(url: url)], qualities: qualities, currentQuality: actual, headers: headers, qualityNotice: notice)
    }

    private func mobilePlayback(roomID: String, quality: Int?) async throws -> PlaybackInfo {
        let headers = ["Referer": "https://m.douyu.com/\(roomID)", "User-Agent": HTTPClient.userAgent]
        let deviceID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var requestHeaders = headers
        requestHeaders["Cookie"] = "dy_did=\(deviceID);acf_did=\(deviceID);"
        async let metadata = playbackRates(roomID: roomID, deviceID: deviceID, headers: requestHeaders)
        // The mobile player has its own signing script and now uses getStreamUrl.
        // ratestream ignores rate, and the desktop signing script is a different version.
        let html = try await client.text(try endpoint("https://m.douyu.com/\(roomID)"), headers: requestHeaders)
        let signature = try DouyuSigner.sign(Self.mobileSigningScript(html), roomID: roomID, deviceID: deviceID)
        let body = "\(signature)&ver=22011191&rid=\(roomID)&rate=\(quality ?? -1)"
        let response = try await client.post(try endpoint("https://m.douyu.com/hgapi/livenc/room/getStreamUrl"), body: body, headers: requestHeaders)
        // Some mobile responses echo rate even when the HLS URL is a different rendition.
        // The desktop metadata supplies the authoritative rate -> bitrate mapping.
        let rates = (try? await metadata) ?? []
        try Task.checkCancellation()
        return try Self.parsePlayback(response, quality: quality, headers: headers, rates: rates)
    }

    static func mobileSigningScript(_ html: String) throws -> String {
        let regex = try NSRegularExpression(pattern: #"<script\b[^>]*>([\s\S]*?)</script>"#, options: .caseInsensitive)
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let script = String(html[range])
            if script.contains("function ub98484234(") { return script }
        }
        throw LiveError.invalidResponse
    }

    private func playbackRates(roomID: String, deviceID: String, headers: [String: String]) async throws -> [JSONValue] {
        let result = try await client.get(try endpoint("https://www.douyu.com/swf_api/homeH5Enc", ["rids": roomID]), headers: headers)
        let signature = try DouyuSigner.sign(result["data"]["room\(roomID)"].string, roomID: roomID, deviceID: deviceID)
        let response = try await client.post(try endpoint("https://www.douyu.com/lapi/live/getH5Play/\(roomID)"),
            body: "\(signature)&cdn=&rate=-1&ver=Douyu_223061205&iar=0&ive=0&hevc=0&fa=0", headers: headers)
        guard !response["error"].isNull, response["error"].int == 0 else { throw LiveError.invalidResponse }
        return response["data"]["multirates"].array
    }

    static func parsePlayback(_ response: JSONValue, quality: Int?, headers: [String: String], rates: [JSONValue] = []) throws -> PlaybackInfo {
        let status = response["error"].isNull ? response["code"] : response["error"]
        guard !status.isNull else { throw LiveError.invalidResponse }
        guard status.int == 0 else { throw LiveError.platform(response["msg"].string) }
        let data = response["data"]
        guard data["pass"].int == 0 else { throw LiveError.platform("该直播间需要在斗鱼官网验证密码") }
        let raw = data["url"].string.replacingOccurrences(of: "&amp;", with: "&")
        guard let url = URL(string: raw), ["http", "https"].contains(url.scheme ?? ""), url.host != nil, url.path.contains(".m3u8") else {
            throw LiveError.noPlayableStream
        }
        let settings = data["settings"].isNull ? data["multirates"].array : data["settings"].array
        var seen = Set<Int>()
        var qualities = settings.compactMap { item -> StreamQuality? in
            guard !item["rate"].isNull, !item["name"].string.isEmpty, item["high_bit"].int == 0,
                  seen.insert(item["rate"].int).inserted else { return nil }
            return StreamQuality(id: item["rate"].int, name: item["name"].string)
        }
        var actual = data["rate"].isNull ? -1 : data["rate"].int
        if let bitrate = capture(#"_([0-9]+)\.m3u8$"#, in: url.path).flatMap(Int.init) {
            let mapping = rates.isEmpty ? data["multirates"].array : rates
            // Never label a suffixed HLS stream with an unverified, echoed rate.
            let rendition = mapping.first { $0["bit"].int == bitrate }
            actual = rendition?["rate"].int ?? -1
            if let rendition, !qualities.contains(where: { $0.id == actual }) {
                qualities.append(StreamQuality(id: actual, name: rendition["name"].string))
            }
        }
        if !qualities.contains(where: { $0.id == actual }) {
            qualities.append(StreamQuality(id: actual, name: "平台默认"))
        }
        let actualName = qualities.first { $0.id == actual }?.name ?? "平台默认"
        let notice: String?
        if actual == -1 {
            notice = "斗鱼未提供可核实的当前画质，暂按平台默认播放。"
        } else if quality.map({ $0 != actual }) == true {
            notice = "斗鱼本次返回\(actualName)，所选画质被平台回退。"
        } else if quality == nil, actual != data["rate"].int {
            notice = "斗鱼当前实际提供\(actualName)，更多画质以平台返回为准。"
        } else { notice = nil }
        return PlaybackInfo(lines: [StreamLine(url: url)], qualities: qualities,
            currentQuality: actual, headers: headers, qualityNotice: notice)
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
    static func sign(_ script: String, roomID: String, timestamp: Int = Int(Date().timeIntervalSince1970), deviceID: String = "10000000000000000000000000001501") throws -> String {
        guard script.count < 200_000, !script.isEmpty, let context = JSContext() else { throw LiveError.invalidResponse }
        // Isolated JavaScriptCore context: no browser, filesystem or network objects are exposed.
        let hash: @convention(block) (String) -> String = { md5($0) }
        context.setObject(hash, forKeyedSubscript: "jliveMD5" as NSString)
        context.evaluateScript("var CryptoJS = { MD5: function(s) { var h = jliveMD5(String(s)); return { toString: function() { return h; } }; } };")
        context.evaluateScript(script)
        guard context.exception == nil, let function = context.objectForKeyedSubscript("ub98484234"), !function.isUndefined else { throw LiveError.invalidResponse }
        let value = function.call(withArguments: [roomID, deviceID, String(timestamp)])?.toString() ?? ""
        guard context.exception == nil, value.contains("sign="), value.count < 4096 else { throw LiveError.invalidResponse }
        return value
    }
}
