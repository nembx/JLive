import XCTest
import SwiftUI
import AVFoundation
import JLiveCore
@testable import JLive

@MainActor
final class AdaptiveLayoutTests: XCTestCase {
    func testDuoScreenSizesKeepTheSamePlayerAndLeaveRoomForInformation() async throws {
        // Points derived from Xcode's iPhone Duo display profiles (3× pixels).
        let sizes = [CGSize(width: 466, height: 678), CGSize(width: 951, height: 669),
                     CGSize(width: 669, height: 951), CGSize(width: 466, height: 678)]
        let suite = "jlive-duo-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = LibraryStore(defaults: defaults)
        let room = LiveRoom(platform: .bilibili, roomID: "1", title: "直播", streamer: "主播", isLive: false)
        let host = UIHostingController(rootView: RoomDetailView(room: room, service: LiveService(providers: [])).environment(library))
        let container = UIViewController()
        let window = UIWindow(frame: CGRect(origin: .zero, size: sizes[0]))
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.addChild(host)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        defer {
            window.isHidden = true
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }
        var original: AVPlayerLayer?
        for size in sizes {
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            host.view.layoutIfNeeded()
            let surface = try XCTUnwrap(videoSurface(in: host.view))
            let layer = try XCTUnwrap(surface.layer as? AVPlayerLayer)
            if let original { XCTAssertTrue(layer === original, "展开和折叠不能重建播放层") }
            else { original = layer }
            let frame = surface.convert(surface.bounds, to: host.view)
            XCTAssertGreaterThan(frame.width, 300)
            XCTAssertGreaterThan(frame.height, 150)
            XCTAssertLessThanOrEqual(frame.maxX, size.width + 1)
            XCTAssertLessThanOrEqual(frame.maxY, size.height + 1)
            if size.width > 700 {
                XCTAssertLessThan(frame.width, size.width - 250, "展开横屏时右侧应留出聊天与直播信息")
            } else {
                XCTAssertEqual(frame.width, size.width, accuracy: 1)
                XCTAssertLessThan(frame.height, size.height - 250, "竖屏时下方应留出聊天与直播信息")
            }
        }
    }

    private func videoSurface(in view: UIView) -> UIView? {
        if view.layer is AVPlayerLayer { return view }
        return view.subviews.lazy.compactMap { self.videoSurface(in: $0) }.first
    }
}
