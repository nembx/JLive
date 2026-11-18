import Testing
@testable import JLiveCore

struct PlaybackQualityTests {
    @Test func selectsByTierRatherThanPlatformIDOrListOrder() {
        let qualities = [StreamQuality(id: 0, name: "原画"), StreamQuality(id: 10000, name: "高清"), StreamQuality(id: 2, name: "标清")]
        #expect(PlaybackQuality.high.select(from: qualities)?.id == 10000)
        #expect(PlaybackQuality.original.select(from: qualities)?.id == 0)
        #expect(PlaybackQuality.standard.select(from: qualities)?.id == 2)
    }

    @Test func prefersNearestHigherTierBeforeALowerTier() {
        let qualities = [StreamQuality(id: 0, name: "原画"), StreamQuality(id: 1, name: "流畅"), StreamQuality(id: 2, name: "超清")]
        #expect(PlaybackQuality.high.select(from: qualities)?.id == 2)
        #expect(PlaybackQuality.standard.select(from: qualities)?.id == 2)
        #expect(PlaybackQuality.blueRay.select(from: qualities)?.id == 0)
    }

    @Test func fallsBackToNearestLowerTierWhenNothingHigherExists() {
        let qualities = [StreamQuality(id: 100, name: "高清"), StreamQuality(id: 999, name: "流畅"), StreamQuality(id: 3, name: "标清")]
        #expect(PlaybackQuality.original.select(from: qualities)?.id == 100)
        #expect(PlaybackQuality.ultra.select(from: qualities)?.id == 100)
        #expect(PlaybackQuality.standard.select(from: qualities)?.id == 3)
    }

    @Test(arguments: [
        ("蓝光4M", PlaybackQuality.blueRay), ("蓝光8M", .blueRay), ("超清60帧", .ultra),
        ("1080P", .ultra), ("720p", .high), ("480P", .standard), ("360p", .smooth),
        ("4K", .original), ("原画60", .original), ("全高清", .ultra), ("FULL HD", .ultra)
    ])
    func recognizesPlatformLabels(label: String, tier: PlaybackQuality) {
        let quality = StreamQuality(id: 7, name: label)
        #expect(tier.select(from: [quality, StreamQuality(id: 8, name: tier.name)])?.id == 7)
    }

    @Test func keepsPlatformDefaultForUnknownOrEmptyQualityLists() {
        #expect(PlaybackQuality.high.select(from: []) == nil)
        #expect(PlaybackQuality.high.select(from: [StreamQuality(id: 0, name: "自动画质"), StreamQuality(id: 3, name: "画质 3")]) == nil)
    }
}
