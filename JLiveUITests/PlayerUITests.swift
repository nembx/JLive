import XCTest

@MainActor
final class PlayerUITests: XCTestCase {
    func testFullscreenReturnsToThePreviousLandscapeLayout() throws {
        let app = try launchQualityFixture(fallsBack: false)
        defer { XCUIDevice.shared.orientation = .portrait; app.terminate() }
        XCTAssertTrue(app.buttons["全屏播放"].waitForExistence(timeout: 8))
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = NSPredicate { _, _ in app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height }
        wait(for: [expectation(for: landscape, evaluatedWith: app)], timeout: 5)
        if !app.buttons["全屏播放"].exists { app.otherElements["videoSurface"].tap() }
        app.buttons["全屏播放"].tap()
        let exit = app.buttons["退出全屏"].firstMatch
        XCTAssertTrue(exit.waitForExistence(timeout: 5))
        exit.tap()
        XCTAssertTrue(app.buttons["全屏播放"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["roomInformation"].exists)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, window.height, "退出全屏应恢复原来的横屏，而不是强制竖屏")
    }

    func testQualityMenuUpdatesToTheConfirmedQuality() throws {
        let app = try launchQualityFixture(fallsBack: false)
        defer { app.terminate() }
        let quality = app.buttons["切换清晰度"]
        XCTAssertTrue(quality.waitForExistence(timeout: 8))
        quality.tap()
        app.buttons["蓝光"].tap()
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "蓝光"), evaluatedWith: quality)], timeout: 8)
        XCTAssertTrue(app.staticTexts["已切换至蓝光"].exists)
        app.buttons["播放器设置"].tap()
        let picker = app.buttons["playerQualityPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        XCTAssertEqual(picker.value as? String, "蓝光")
        picker.tap()
        app.buttons["超清"].tap()
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "超清"), evaluatedWith: picker)], timeout: 8)
        app.buttons["关闭设置"].tap()
        XCTAssertEqual(quality.value as? String, "超清", "设置面板和播放器标签应同步")
    }

    func testUnavailableQualityKeepsActualLabelAndExplainsFallback() throws {
        let app = try launchQualityFixture(fallsBack: true)
        defer { app.terminate() }
        let quality = app.buttons["切换清晰度"]
        XCTAssertTrue(quality.waitForExistence(timeout: 8))
        XCTAssertEqual(quality.value as? String, "超清")
        quality.tap()
        app.buttons["原画"].tap()
        XCTAssertTrue(app.staticTexts["原画暂不可用，当前为超清"].waitForExistence(timeout: 8))
        XCTAssertEqual(quality.value as? String, "超清")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "画质回退反馈"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testPlatformQualityNoticeRemainsAvailableInPlayerSettings() throws {
        let app = try launchQualityFixture(fallsBack: true, showsNotice: true)
        defer { app.terminate() }
        let quality = app.buttons["切换清晰度"]
        XCTAssertTrue(quality.waitForExistence(timeout: 8))
        quality.tap()
        app.buttons["原画"].tap()
        XCTAssertTrue(app.staticTexts["原画暂不可用，当前为超清\n平台当前仅提供超清"].waitForExistence(timeout: 8))
        XCTAssertEqual(quality.value as? String, "超清")
        app.buttons["播放器设置"].tap()
        let notice = app.staticTexts["qualityAvailabilityNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        XCTAssertEqual(notice.label, "平台当前仅提供超清")
    }

    func testQualityNoticeOnlyAppearsAfterChoosingAQuality() throws {
        let app = try launchQualityFixture(fallsBack: true, showsNotice: true)
        defer { XCUIDevice.shared.orientation = .portrait; app.terminate() }
        let quality = app.buttons["切换清晰度"]
        let message = app.staticTexts["qualitySwitchMessage"]
        XCTAssertTrue(quality.waitForExistence(timeout: 8))
        XCTAssertFalse(message.waitForExistence(timeout: 2), "打开直播间不应弹出画质提示")
        app.buttons["全屏播放"].tap()
        XCTAssertTrue(app.buttons["退出全屏"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(message.waitForExistence(timeout: 2), "进入全屏不应弹出画质提示")
        app.buttons["退出全屏"].firstMatch.tap()
        XCTAssertTrue(app.buttons["全屏播放"].waitForExistence(timeout: 5))
        quality.tap()
        app.buttons["原画"].tap()
        XCTAssertTrue(message.waitForExistence(timeout: 8), "手动切换画质后才提示")
        XCTAssertEqual(message.label, "原画暂不可用，当前为超清\n平台当前仅提供超清")
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: message)], timeout: 10)
        if !app.buttons["全屏播放"].exists { app.otherElements["videoSurface"].tap() }
        app.buttons["全屏播放"].tap()
        XCTAssertTrue(app.buttons["退出全屏"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(message.waitForExistence(timeout: 2), "提示消失后，进入全屏不应再次弹出")
    }

    func testBilibiliLoginIsAnInAppPageWithAConfirmationCode() throws {
        let app = try launchQualityFixture(fallsBack: false)
        defer { app.terminate() }
        let quality = app.buttons["切换清晰度"]
        XCTAssertTrue(quality.waitForExistence(timeout: 8))
        quality.tap()
        app.buttons["登录 B站获取更多画质"].tap()
        XCTAssertTrue(app.images["bilibiliLoginCode"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.exists, "登录先显示应用内页面，不直接打开网页")
        XCTAssertEqual(app.descendants(matching: .any)["bilibiliLoginStatus"].label, "等待确认")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "B站应用内登录页"; screenshot.lifetime = .keepAlways; add(screenshot)
        // The simulator has no Bilibili app, so the page has to say so and keep the other ways to sign in.
        app.buttons["bilibiliLoginOpenApp"].tap()
        XCTAssertTrue(app.staticTexts["bilibiliLoginAppMessage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["改用网页登录（短信或密码）"].exists)
        app.buttons["取消"].tap()
        XCTAssertTrue(quality.waitForExistence(timeout: 5))
    }

    func testExpiredLoginCodeOffersAFreshOne() throws {
        let app = try launchQualityFixture(fallsBack: false, extraArguments: ["--fixture-qr-expired"])
        defer { app.terminate() }
        let quality = app.buttons["切换清晰度"]
        XCTAssertTrue(quality.waitForExistence(timeout: 8))
        quality.tap()
        app.buttons["登录 B站获取更多画质"].tap()
        XCTAssertTrue(app.buttons["刷新二维码"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["bilibiliLoginOpenApp"].isEnabled, "过期的二维码不能再用于确认")
    }

    func testLoginPageFitsTheFullscreenLandscapePlayer() throws {
        let app = try launchQualityFixture(fallsBack: false)
        defer { XCUIDevice.shared.orientation = .portrait; app.terminate() }
        XCTAssertTrue(app.buttons["全屏播放"].waitForExistence(timeout: 8))
        app.buttons["全屏播放"].tap()
        XCTAssertTrue(app.buttons["退出全屏"].firstMatch.waitForExistence(timeout: 5))
        let quality = app.buttons["切换清晰度"]
        if !quality.exists { app.otherElements["videoSurface"].tap() }
        quality.tap()
        app.buttons["登录 B站获取更多画质"].tap()
        let code = app.images["bilibiliLoginCode"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, window.height)
        XCTAssertTrue(window.contains(code.frame), "横屏时二维码应完整显示")
        XCTAssertTrue(app.buttons["bilibiliLoginOpenApp"].isHittable, "横屏时不需要滚动就能点确认按钮")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "B站应用内登录页（横屏）"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testLiveBilibiliLoginCode() throws {
        guard ProcessInfo.processInfo.environment["JLIVE_UI_LIVE_TESTS"] == "1" else { throw XCTSkip("真实登录二维码验证按需启用") }
        let app = try launchQualityFixture(fallsBack: false, extraArguments: ["--live-qr-login"])
        defer { app.terminate() }
        let quality = app.buttons["切换清晰度"]
        XCTAssertTrue(quality.waitForExistence(timeout: 8))
        quality.tap()
        app.buttons["登录 B站获取更多画质"].tap()
        XCTAssertTrue(app.images["bilibiliLoginCode"].waitForExistence(timeout: 20), "应取得 B站返回的真实二维码")
        // Stay through a few status requests: an unconfirmed code must keep waiting, not fail.
        Thread.sleep(forTimeInterval: 7)
        XCTAssertEqual(app.descendants(matching: .any)["bilibiliLoginStatus"].label, "等待确认")
        XCTAssertTrue(app.buttons["bilibiliLoginOpenApp"].isEnabled)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "B站真实登录二维码"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["改用网页登录（短信或密码）"].tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 8)
        let web = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        web.name = "B站网页登录"; web.lifetime = .keepAlways; add(web)
    }

    func testFLVPlaybackAndQualitySwitchKeepPlaying() throws {
        let app = try launchQualityFixture(fallsBack: false, videoExtension: "flv")
        defer { app.terminate() }
        let surface = app.otherElements["videoSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "播放中"), evaluatedWith: surface)], timeout: 15)
        let quality = app.buttons["切换清晰度"]
        if !quality.exists { surface.tap() }
        quality.tap()
        app.buttons["蓝光"].tap()
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "蓝光"), evaluatedWith: quality)], timeout: 8)
        XCTAssertEqual(quality.value as? String, "蓝光")
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "播放中"), evaluatedWith: surface)], timeout: 15)
        app.buttons["全屏播放"].tap()
        XCTAssertTrue(app.buttons["退出全屏"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(surface.value as? String, "播放中")
        app.buttons["退出全屏"].firstMatch.tap()
        XCTAssertTrue(app.buttons["全屏播放"].waitForExistence(timeout: 5))
    }

    func testLiveDouyuQualitySwitch() throws {
        guard ProcessInfo.processInfo.environment["JLIVE_UI_LIVE_TESTS"] == "1" else { throw XCTSkip("真实直播验证按需启用") }
        let app = XCUIApplication()
        app.launchArguments = ["--muted", "--open-room", "https://www.douyu.com/36252"]
        app.launch()
        defer { app.terminate() }
        let surface = app.otherElements["videoSurface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "播放中"), evaluatedWith: surface)], timeout: 30)
        let quality = app.buttons["切换清晰度"]
        for name in ["高清", "超清"] {
            if !quality.exists { surface.tap() }
            quality.tap()
            let tier = app.buttons[name]
            XCTAssertTrue(tier.waitForExistence(timeout: 5))
            tier.tap()
            wait(for: [expectation(for: NSPredicate(format: "value == %@", name), evaluatedWith: quality)], timeout: 15)
            wait(for: [expectation(for: NSPredicate(format: "value == %@", "播放中"), evaluatedWith: surface)], timeout: 30)
        }
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "斗鱼真实超清 FLV 播放"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    private func launchQualityFixture(fallsBack: Bool, showsNotice: Bool = false, videoExtension: String = "mp4", extraArguments: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        let video = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "landscape", withExtension: videoExtension))
        app.launchArguments = ["--muted", "--ui-fixtures", "--fixture-quality-switch", "--fixture-video", video.path, "--open-room", "https://live.bilibili.com/1"]
        if fallsBack { app.launchArguments.append("--fixture-quality-fallback") }
        if showsNotice { app.launchArguments.append("--fixture-quality-notice") }
        app.launchArguments += extraArguments
        app.launch()
        return app
    }

    func testFullscreenVideoReachesBothVerticalEdges() throws {
        try checkFullscreenVideoEdges(resource: "landscape")
    }

    func testUltrawideVideoAlsoFillsTheFullscreenHeight() throws {
        try checkFullscreenVideoEdges(resource: "ultrawide")
    }

    private func checkFullscreenVideoEdges(resource: String) throws {
        let app = XCUIApplication()
        let videoURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: resource, withExtension: "mp4"))
        app.launchArguments = ["--muted", "--ui-fixtures", "--fixture-video", videoURL.path, "--open-room", "https://live.bilibili.com/1"]
        app.launch()
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
        let full = app.buttons["全屏播放"]
        XCTAssertTrue(full.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["暂停"].waitForExistence(timeout: 5), "边界检查应使用真正播放的视频")
        full.tap()
        let exit = app.buttons["退出全屏"].firstMatch
        XCTAssertTrue(exit.waitForExistence(timeout: 5))
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            let fillsHeight = NSPredicate { _, _ in
                let video = app.otherElements["videoSurface"].frame
                let window = app.windows.firstMatch.frame
                return window.width > window.height && abs(video.minY - window.minY) < 1 && abs(video.maxY - window.maxY) < 1
            }
            let filled = expectation(for: fillsHeight, evaluatedWith: app)
            wait(for: [filled], timeout: 5)
            let video = app.otherElements["videoSurface"].frame
            let window = app.windows.firstMatch.frame
            XCTAssertEqual(video.minY, window.minY, accuracy: 1)
            XCTAssertEqual(video.maxY, window.maxY, accuracy: 1)
            let capture = XCUIScreen.main.screenshot()
            try assertColoredVideoReachesVerticalEdges(capture)
            let screenshot = XCTAttachment(screenshot: capture)
            screenshot.name = "\(resource)-横屏画面边界-\(orientation.rawValue)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        if !exit.exists { app.otherElements["videoSurface"].tap() }
        exit.tap()
        XCTAssertTrue(full.waitForExistence(timeout: 5))
    }

    private func assertColoredVideoReachesVerticalEdges(_ screenshot: XCUIScreenshot) throws {
        // Device screenshots retain portrait pixels with an orientation tag; draw it before sampling.
        let source = screenshot.image
        let size = CGSize(width: max(source.size.width, source.size.height), height: min(source.size.width, source.size.height))
        let normalized = UIGraphicsImageRenderer(size: size).image { _ in source.draw(in: CGRect(origin: .zero, size: size)) }
        let image = try XCTUnwrap(normalized.cgImage)
        XCTAssertGreaterThan(image.width, image.height)
        // The silent fixture has colored bands along both edges. Sample away from the rounded corners.
        for y in [image.height / 100, image.height - image.height / 100] {
            let sample = try XCTUnwrap(image.cropping(to: CGRect(x: image.width / 2, y: y, width: 1, height: 1)))
            var pixel = [UInt8](repeating: 0, count: 4)
            try pixel.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            XCTAssertGreaterThan(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2]), 60, "屏幕顶部和底部应显示视频，而不是黑色空隙")
        }
    }

    func testDouyinNativePlayerIsMutedAndOffersChatSettings() throws {
        guard let roomID = ProcessInfo.processInfo.environment["JLIVE_DOUYIN_UI_ROOM"] else {
            throw XCTSkip("设置 JLIVE_DOUYIN_UI_ROOM 验证正在直播的抖音房间")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--muted", "--open-room", "https://live.douyin.com/\(roomID)"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["暂停"].waitForExistence(timeout: 25), "HLS 应进入实际播放状态")
        XCTAssertTrue(app.buttons["开启声音"].exists, "测试期间应保持静音")
        XCTAssertTrue(app.staticTexts["实时"].waitForExistence(timeout: 15), "应收到弹幕服务端推送")
        let settings = app.buttons["播放器设置"]
        if !settings.exists { app.otherElements["videoSurface"].tap() }
        XCTAssertTrue(settings.exists)
        XCTAssertTrue(app.buttons["切换清晰度"].exists)
        settings.tap()
        XCTAssertTrue(app.switches["画面弹幕"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.sliders["不透明度"].exists)
        app.buttons["关闭设置"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "抖音原生播放与聊天"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["完成"].tap()
        XCTAssertFalse(app.buttons["全屏播放"].exists)
    }

    func testSearchCanDismissKeyboardSubmitAndCancel() {
        let app = XCUIApplication()
        app.launchArguments = ["--muted", "--ui-fixtures"]
        app.launch()
        defer { app.terminate() }
        XCTAssertFalse(app.tabBars.buttons["搜索"].exists)
        app.buttons["搜索直播"].tap()
        let field = app.textFields["searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        XCTAssertFalse(app.tabBars.buttons["发现"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["收起键盘"].exists)
        // Tapping the empty area below the field puts the keyboard away.
        app.staticTexts["输入关键词搜索"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 4))
        field.tap()
        field.typeText("游戏")
        app.buttons["submitSearch"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["搜索结果"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["room-bilibili:1"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["douyinSearchLogin"].exists)
        field.tap()
        app.buttons["cancelSearch"].tap()
        XCTAssertTrue(app.buttons["搜索直播"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 4))
        app.buttons["搜索直播"].tap()
        app.buttons["抖音"].tap()
        XCTAssertTrue(app.staticTexts["通过链接打开抖音直播"].waitForExistence(timeout: 4))
        app.buttons["打开直播间链接"].tap()
        XCTAssertTrue(app.buttons["打开直播间"].waitForExistence(timeout: 4))
        app.buttons["cancelRoomLink"].tap()
        app.buttons["cancelSearch"].tap()
    }

    func testDiscoverKeepsItsListAcrossTabsAndWhileRefreshing() {
        let app = XCUIApplication()
        app.launchArguments = ["--muted", "--ui-fixtures"]
        app.launch()
        defer { app.terminate() }
        // The fixture puts the request number in the first card's popularity.
        let card = app.buttons["room-bilibili:1"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let first = card.label
        app.tabBars.buttons["收藏"].tap()
        app.tabBars.buttons["我的"].tap()
        app.tabBars.buttons["发现"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 2))
        XCTAssertFalse(app.descendants(matching: .any)["roomListLoading"].exists)
        // Longer than a fixture request: a reload started by coming back would have arrived.
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(card.label, first, "回到发现页不应重新请求")

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertTrue(card.exists, "下拉刷新时列表不应消失")
        XCTAssertFalse(app.descendants(matching: .any)["roomListLoading"].exists)
        let refreshed = NSPredicate(format: "label != %@", first)
        wait(for: [expectation(for: refreshed, evaluatedWith: card)], timeout: 6)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "下拉刷新后的发现页"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testFavoriteStatusFiltersAndHistoryInMyPage() {
        let app = XCUIApplication()
        app.launchArguments = ["--muted", "--ui-fixtures"]
        app.launch()
        defer { app.terminate() }
        app.tabBars.buttons["收藏"].tap()
        XCTAssertTrue(app.segmentedControls["favoriteStatusPicker"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["最近观看"].exists)
        // Room 4 was saved as offline and has started since. The page finds out without being pulled.
        XCTAssertTrue(app.buttons["正在开播 · 2"].waitForExistence(timeout: 6), "打开收藏页应自动更新开播状态")
        XCTAssertTrue(app.buttons["room-bilibili:4"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["room-bilibili:1"].exists)
        XCTAssertFalse(app.buttons["room-bilibili:3"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "开播状态更新于")).firstMatch.exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "全部")).count, 0)
        let live = XCTAttachment(screenshot: app.screenshot())
        live.name = "自动更新后的正在开播"; live.lifetime = .keepAlways; add(live)
        app.buttons["未开播 · 2"].tap()
        XCTAssertTrue(app.buttons["room-bilibili:2"].exists)
        XCTAssertFalse(app.buttons["room-bilibili:1"].exists)
        XCTAssertFalse(app.buttons["room-bilibili:4"].exists)
        XCTAssertTrue(app.buttons["room-bilibili:3"].exists)
        let cards = XCTAttachment(screenshot: app.screenshot())
        cards.name = "收藏卡片与开播筛选"; cards.lifetime = .keepAlways; add(cards)
        app.tabBars.buttons["我的"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "最近观看")).firstMatch.tap()
        XCTAssertTrue(app.buttons["room-bilibili:1"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["room-bilibili:2"].exists)
        app.buttons["清空"].tap()
        app.buttons["清空记录"].tap()
        XCTAssertTrue(app.staticTexts["还没有观看记录"].waitForExistence(timeout: 4))
    }

    func testDiscoverCategorySelectionPaginationAndReturnToRecommendations() {
        let app = XCUIApplication()
        app.launchArguments = ["--muted", "--ui-fixtures"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["room-bilibili:1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["全部"].exists)
        app.buttons["browseCategories"].tap()
        let game = app.buttons["category-bilibili:2:86"]
        XCTAssertTrue(game.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["关闭"].exists)
        let overview = XCTAttachment(screenshot: app.screenshot())
        overview.name = "分区目录"; overview.lifetime = .keepAlways; add(overview)
        let search = app.searchFields.firstMatch
        if !search.exists { app.swipeDown() }
        if search.exists {
            search.tap()
            search.typeText("网游")
            XCTAssertTrue(game.exists)
            XCTAssertFalse(app.staticTexts["没有匹配的分区"].exists, "匹配父分区时也应显示子分区")
            XCTAssertFalse(app.buttons["category-bilibili:3:235"].exists)
        }
        let directory = XCTAttachment(screenshot: app.screenshot())
        directory.name = "分区目录与筛选"; directory.lifetime = .keepAlways; add(directory)
        game.tap()
        let first = app.buttons["room-bilibili:861"]
        XCTAssertTrue(first.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["browseCategories"].label.contains("英雄联盟"))
        app.buttons["加载更多"].tap()
        XCTAssertTrue(app.buttons["room-bilibili:862"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["加载更多"].exists)
        app.tabBars.buttons["收藏"].tap()
        app.tabBars.buttons["发现"].tap()
        XCTAssertTrue(app.buttons["room-bilibili:862"].exists, "回到发现页保留分区分页")
        // Every fixture category has rooms of its own: another category must replace the list.
        app.buttons["browseCategories"].tap()
        let console = app.buttons["category-bilibili:2:240"]
        XCTAssertTrue(console.waitForExistence(timeout: 4))
        console.tap()
        XCTAssertTrue(app.buttons["room-bilibili:2401"].waitForExistence(timeout: 4), "更换分区后应显示新分区的直播间")
        XCTAssertFalse(first.exists, "更换分区后不应留下上一个分区的直播间")
        XCTAssertFalse(app.buttons["room-bilibili:862"].exists)
        XCTAssertTrue(app.buttons["browseCategories"].label.contains("单机游戏"))
        app.buttons["推荐"].tap()
        XCTAssertTrue(app.buttons["room-bilibili:1"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["room-bilibili:2401"].exists)
        app.buttons["browseCategories"].tap()
        XCTAssertTrue(game.waitForExistence(timeout: 4))
        game.tap()
        XCTAssertTrue(app.buttons["room-bilibili:862"].waitForExistence(timeout: 4))
        let result = XCTAttachment(screenshot: app.screenshot())
        result.name = "分区直播列表与缓存"; result.lifetime = .keepAlways; add(result)
    }

    func testRoomInformationAndChatSpacing() {
        let app = XCUIApplication()
        app.launchArguments = ["--muted", "--ui-fixtures"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["room-bilibili:2"].waitForExistence(timeout: 4))
        app.buttons["room-bilibili:2"].tap()
        XCTAssertTrue(app.scrollViews["roomInformation"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.tabBars.buttons["发现"].exists, "直播间应隐藏底部标签栏")
        XCTAssertTrue(app.staticTexts["聊天"].exists)
        let info = XCTAttachment(screenshot: app.screenshot())
        info.name = "直播信息与聊天留白"; info.lifetime = .keepAlways; add(info)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.tabBars.buttons["发现"].waitForExistence(timeout: 4))
    }

    func testFullscreenKeepsSettingsAndReturnsToInlinePlayer() throws {
        // This checks presentation and settings; an anchor going offline must not change the test path.
        let app = try launchQualityFixture(fallsBack: false)
        defer { app.terminate() }
        let surface = app.otherElements["videoSurface"]
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "播放中"), evaluatedWith: surface)], timeout: 8)
        let full = app.buttons["全屏播放"]
        XCTAssertTrue(full.waitForExistence(timeout: 12))
        // Keep the controls visible while making assertions, just as a viewer taps the picture.
        if !full.exists { surface.tap() }
        // The full screen action is the final control in the bottom right of the video.
        let settings = app.buttons["播放器设置"]
        XCTAssertGreaterThan(full.frame.minX, settings.frame.minX)
        full.tap()
        let exit = app.buttons["退出全屏"].firstMatch
        XCTAssertTrue(exit.waitForExistence(timeout: 8))
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 3))
        if !settings.exists { app.otherElements["videoSurface"].tap() }
        settings.tap()
        let opacity = app.sliders["不透明度"]
        XCTAssertTrue(opacity.waitForExistence(timeout: 4))
        opacity.adjust(toNormalizedSliderPosition: 0.5)
        let chatSwitch = app.switches["画面弹幕"]
        XCTAssertTrue(chatSwitch.exists)
        let before = chatSwitch.value as? String
        chatSwitch.tap()
        let after = chatSwitch.value as? String
        XCTAssertNotEqual(before, after)
        app.buttons["关闭设置"].tap()
        exit.tap()
        XCTAssertTrue(full.waitForExistence(timeout: 8))
        settings.tap()
        XCTAssertTrue(chatSwitch.waitForExistence(timeout: 4))
        XCTAssertEqual(chatSwitch.value as? String, after)
        // Restore the user's initial danmaku preference before ending the test.
        chatSwitch.tap()
        app.buttons["关闭设置"].tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "内嵌播放器"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAppearanceAndLibraryBackupActions() {
        let app = XCUIApplication()
        app.launchArguments = ["--muted", "--ui-fixtures"]
        app.launch()
        defer { app.terminate() }
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["appearancePicker"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["平台接入"].exists)
        let cellularQuality = app.buttons["cellularQualityPicker"]
        let wifiQuality = app.buttons["wifiQualityPicker"]
        if !cellularQuality.isHittable { app.swipeUp() }
        XCTAssertTrue(cellularQuality.exists)
        XCTAssertTrue(wifiQuality.exists)
        cellularQuality.tap()
        app.buttons["标清"].tap()
        wifiQuality.tap()
        app.buttons["蓝光"].tap()
        XCTAssertTrue(cellularQuality.label.contains("标清"))
        XCTAssertTrue(wifiQuality.label.contains("蓝光"))
        app.swipeUp()
        if !app.buttons["导入收藏"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["导出收藏"].exists)
        XCTAssertTrue(app.buttons["导入收藏"].exists)
        app.swipeDown()
        if !app.buttons["appearancePicker"].isHittable { app.swipeDown() }
        app.buttons["appearancePicker"].tap()
        app.buttons["深色"].tap()
        let dark = XCTAttachment(screenshot: app.screenshot())
        dark.name = "深色主题"; dark.lifetime = .keepAlways; add(dark)
        app.buttons["appearancePicker"].tap()
        app.buttons["浅色"].tap()
        let light = XCTAttachment(screenshot: app.screenshot())
        light.name = "浅色主题"; light.lifetime = .keepAlways; add(light)
        app.buttons["appearancePicker"].tap()
        app.buttons["跟随系统"].tap()
    }
}
