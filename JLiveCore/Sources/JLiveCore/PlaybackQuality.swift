import Foundation

/// Shared tiers across platforms; platform quality IDs are only valid for their own streams.
public enum PlaybackQuality: Int, CaseIterable, Codable, Identifiable, Sendable {
    case smooth, standard, high, ultra, blueRay, original

    public var id: Int { rawValue }
    public var name: String {
        switch self {
        case .smooth: "流畅"
        case .standard: "标清"
        case .high: "高清"
        case .ultra: "超清"
        case .blueRay: "蓝光"
        case .original: "原画"
        }
    }

    /// Prefer the requested tier, then the nearest higher tier, then the nearest lower tier.
    /// Unrecognized labels leave the platform's default selection in place.
    public func select(from qualities: [StreamQuality]) -> StreamQuality? {
        let ranked = qualities.compactMap { quality in
            Self.tier(for: quality.name).map { (quality: quality, tier: $0) }
        }
        if let exact = ranked.first(where: { $0.tier == self }) { return exact.quality }
        if let higher = ranked.filter({ $0.tier.rawValue > rawValue }).min(by: { $0.tier.rawValue < $1.tier.rawValue }) {
            return higher.quality
        }
        return ranked.filter { $0.tier.rawValue < rawValue }.max { $0.tier.rawValue < $1.tier.rawValue }?.quality
    }

    private static func tier(for name: String) -> PlaybackQuality? {
        let label = name.uppercased().replacingOccurrences(of: " ", with: "")
        if ["原画", "原质", "ORIGIN", "SOURCE", "4K", "8K", "2160"].contains(where: label.contains) { return .original }
        if ["蓝光", "BLURAY", "BLU-RAY"].contains(where: label.contains) { return .blueRay }
        if ["超清", "全高清", "FHD", "FULL_HD", "FULLHD", "1080"].contains(where: label.contains) { return .ultra }
        if ["高清", "HD", "720"].contains(where: label.contains) { return .high }
        if ["标清", "SD", "480", "540"].contains(where: label.contains) { return .standard }
        if ["流畅", "低清", "LD", "360", "240"].contains(where: label.contains) { return .smooth }
        return nil
    }
}
