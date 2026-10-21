// DemoFlow.swift — 被 `obelisk demo:record` 录制成 App Review 演示视频
// （Apple 2.1 首次提交就绪门禁要求核心流程录屏）。
// 节奏刻意放缓：每个画面停留数秒，审核员能看清发生了什么。

import XCTest

final class DemoFlow: XCTestCase {
    func testReviewDemo() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(3) // 首页：开始卡片 + 词书列表

        let start = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "开始学习")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        XCTAssertTrue(app.staticTexts["上滑或点击卡片查看释义"].waitForExistence(timeout: 8))
        sleep(3) // 卡片正面：单词 + 音标

        // 上滑翻面（演示手势）
        window().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            .press(forDuration: 0.05, thenDragTo: window().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        XCTAssertTrue(app.staticTexts["中文释义"].waitForExistence(timeout: 5))
        sleep(3) // 翻面：释义 + 词形 + 例句

        // 认识 → 下一张
        app.buttons["认识"].tap()
        XCTAssertTrue(app.staticTexts["上滑或点击卡片查看释义"].waitForExistence(timeout: 5))
        sleep(3) // 第二张正面

        // 再翻面
        window().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            .press(forDuration: 0.05, thenDragTo: window().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        XCTAssertTrue(app.staticTexts["中文释义"].waitForExistence(timeout: 5))
        sleep(3)

        // 左滑 = 不认识（答错的词会当场插回牌组）
        window().coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: window().coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)))
        sleep(3) // 下一张正面
    }

    private func window() -> XCUIElement {
        XCUIApplication().windows.firstMatch
    }
}
