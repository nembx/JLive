// Swift adaptation of the WBI signing algorithm in dart_simple_live.
// Copyright (C) 2023-2025 xiaoyaocz. GPL-3.0-or-later. See LICENSE.
import CryptoKit
import Foundation

public enum WBISigner {
    private static let permutation = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52
    ]

    public static func sign(_ parameters: [String: String], imageKey: String, subKey: String, timestamp: Int) throws -> [String: String] {
        let key = Array(imageKey + subKey)
        guard key.count == 64 else { throw LiveError.invalidResponse }
        let mixin = String(permutation.prefix(32).map { key[$0] })
        var query = parameters.filter { $0.key != "w_rid" }
        query["wts"] = String(timestamp)
        query = query.mapValues { String($0.filter { !"!'()*".contains($0) }) }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let canonical = query.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&")
        query["w_rid"] = Insecure.MD5.hash(data: Data((canonical + mixin).utf8))
            .map { String(format: "%02x", $0) }.joined()
        return query
    }
}
