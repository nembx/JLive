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
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4))
        app.buttons["收起键盘"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 4))
        field.tap()
        field.typeText("游戏")
        app.buttons["submitSearch"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["搜索结果"].waitForExistence(timeout: 4))
        let login = app.buttons["douyinSearchLogin"]
        XCTAssertTrue(login.waitForExistence(timeout: 4))
        login.tap()
        XCTAssertTrue(app.navigationBars["登录抖音"].waitForExistence(timeout: 4))
        app.buttons["cancelDouyinLogin"].tap()
        field.tap()
        app.buttons["cancelSearch"].tap()
        XCTAssertTrue(app.buttons["搜索直播"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 4))
        app.buttons["搜索直播"].tap()
        app.buttons["收起键盘"].tap()
        app.buttons["抖音"].tap()
        app.buttons["打开直播间链接"].tap()
        XCTAssertTrue(app.buttons["打开直播间"].waitForExistence(timeout: 4))
        app.buttons["cancelRoomLink"].tap()
        app.buttons["cancelSearch"].tap()
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
        app.buttons["未开播 · 1"].tap()
        XCTAssertTrue(app.buttons["room-bilibili:2"].exists)
        XCTAssertFalse(app.buttons["room-bilibili:1"].exists)
        app.buttons["全部 · 3"].tap()
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
