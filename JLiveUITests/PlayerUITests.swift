import XCTest

@MainActor
final class PlayerUITests: XCTestCase {
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
        app.launchArguments = ["--muted"]
        app.launch()
        defer { app.terminate() }
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["收藏备份"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.buttons["导出收藏"].exists)
        XCTAssertTrue(app.buttons["导入收藏"].exists)
        app.swipeDown()
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
