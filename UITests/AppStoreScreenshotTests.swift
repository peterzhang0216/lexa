// AppStoreScreenshotTests.swift
// 按 fleet 约定由 `obelisk screenshots` 驱动：在声明的模拟器上捕获
// App Store 营销截图，落盘 obelisk/screenshots/app/<locale>/。

import XCTest

final class AppStoreScreenshotTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testCaptureAppStoreScreenshots() throws {
        app.launch()
        sleep(2)
        attach(name: "01_home")

        // 学习流程：开始卡片（SwiftUI 会把卡内多行文本合成一条 label，用 CONTAINS 匹配）
        let start = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "开始学习")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(app.staticTexts["上滑或点击卡片查看释义"].waitForExistence(timeout: 8))
        sleep(1)
        attach(name: "02_study_card")

        app.staticTexts["上滑或点击卡片查看释义"].tap()
        XCTAssertTrue(app.staticTexts["中文释义"].waitForExistence(timeout: 5))
        sleep(1)
        attach(name: "03_study_revealed")

        // 词库 / 设置用启动参数直达（iPad 的 TabView a11y 结构不稳，点 tab 不可靠）
        app.terminate()
        app.launchArguments += ["--tab-browse"]
        app.launch()
        sleep(2)
        attach(name: "04_browse")

        app.terminate()
        app.launchArguments = ["--tab-settings"]
        app.launch()
        sleep(1)
        attach(name: "05_settings")
    }

    private func attach(name: String) {
        let att = XCTAttachment(screenshot: app.screenshot())
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }
}
