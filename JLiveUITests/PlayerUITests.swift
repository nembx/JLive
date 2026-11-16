import XCTest

@MainActor
final class PlayerUITests: XCTestCase {
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
        app.staticTexts["找到你喜欢的直播"].tap()
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
        XCTAssertFalse(app.staticTexts["正在寻找精彩…"].exists)
        // Longer than a fixture request: a reload started by coming back would have arrived.
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(card.label, first, "回到发现页不应重新请求")

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertTrue(card.exists, "下拉刷新时列表不应消失")
        XCTAssertFalse(app.staticTexts["正在寻找精彩…"].exists)
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
        app.buttons["正在开播 · 1"].tap()
        XCTAssertTrue(app.buttons["room-bilibili:1"].exists)
        XCTAssertFalse(app.buttons["room-bilibili:3"].exists)
        XCTAssertFalse(app.buttons["全部 · 3"].exists)
        app.buttons["未开播 · 2"].tap()
        XCTAssertTrue(app.buttons["room-bilibili:2"].exists)
        XCTAssertFalse(app.buttons["room-bilibili:1"].exists)
        XCTAssertTrue(app.buttons["room-bilibili:3"].exists)
        let cards = XCTAttachment(screenshot: app.screenshot())
        cards.name = "收藏卡片与开播筛选"; cards.lifetime = .keepAlways; add(cards)
        app.tabBars.buttons["我的"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "最近观看")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["最近打开的 2 个直播间，按时间排列"].waitForExistence(timeout: 4))
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
        let first = app.buttons["room-bilibili:101"]
        XCTAssertTrue(first.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["browseCategories"].label.contains("英雄联盟"))
        app.buttons["加载更多"].tap()
        XCTAssertTrue(app.buttons["room-bilibili:102"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["加载更多"].exists)
        app.tabBars.buttons["收藏"].tap()
        app.tabBars.buttons["发现"].tap()
        XCTAssertTrue(app.buttons["room-bilibili:102"].exists, "回到发现页保留分区分页")
        app.buttons["推荐"].tap()
        XCTAssertTrue(app.buttons["room-bilibili:1"].waitForExistence(timeout: 4))
        XCTAssertFalse(first.exists)
        app.buttons["browseCategories"].tap()
        XCTAssertTrue(game.waitForExistence(timeout: 4))
        game.tap()
        XCTAssertTrue(app.buttons["room-bilibili:102"].waitForExistence(timeout: 4))
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
        let app = XCUIApplication()
        app.launchArguments = ["--muted", "--open-room", "https://live.bilibili.com/545068"]
        app.launch()
        defer { app.terminate() }
        let full = app.buttons["全屏播放"]
        XCTAssertTrue(full.waitForExistence(timeout: 12))
        // Keep the controls visible while making assertions, just as a viewer taps the picture.
        app.otherElements["videoSurface"].tap()
        if !full.exists { app.otherElements["videoSurface"].tap() }
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
