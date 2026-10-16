import XCTest
@testable import Lexa

final class LexaTests: XCTestCase {
    func testBoxIntervalsGrowMonotonically() {
        let intervals = Store.boxIntervals
        XCTAssertEqual(intervals.count, Store.maxBox + 1)
        for i in 1..<intervals.count {
            XCTAssertGreaterThan(intervals[i], intervals[i - 1],
                                 "复习间隔必须逐级递增（Leitner 语义）")
        }
    }

    func testWordDecodesFromFactorySchema() throws {
        let json = """
        {"id":"voa-1","word":"test","phonetic":"test","pos":"n.",
         "defsEn":["a procedure"],"zh":["试验"],"examples":[]}
        """.data(using: .utf8)!
        let word = try JSONDecoder().decode(Word.self, from: json)
        XCTAssertEqual(word.word, "test")
        XCTAssertEqual(word.zh, ["试验"])
    }

    func testExampleHighlightMatchesInflectionsOnly() {
        // 词形变化命中：大小写、复数、时态、双写辅音
        XCTAssertTrue(WordHighlight.isMatch("accept,", for: "accept"))
        XCTAssertTrue(WordHighlight.isMatch("Accepts", for: "accept"))
        XCTAssertTrue(WordHighlight.isMatch("studies", for: "study"))
        XCTAssertTrue(WordHighlight.isMatch("stopped", for: "stop"))
        XCTAssertTrue(WordHighlight.isMatch("running", for: "run"))
        // 前缀相同不算命中，避免 catalog 被当作 cat 高亮
        XCTAssertFalse(WordHighlight.isMatch("catalog", for: "cat"))
        XCTAssertFalse(WordHighlight.isMatch("accepted", for: "accepts"))
        // 纯标点不命中
        XCTAssertFalse(WordHighlight.isMatch("—", for: "run"))
    }

    @MainActor
    func testFavoritesRoundTripAndOldStateMigration() throws {
        // 往返：toggle 落盘后新 Store 实例能读回，再 toggle 移除
        let store = Store()
        let id = "test-fav-\(UUID().uuidString)"
        store.toggleFavorite(id)
        XCTAssertTrue(store.isFavorite(id))
        let reloaded = Store()
        XCTAssertTrue(reloaded.isFavorite(id), "收藏必须持久化到 state.json")
        reloaded.toggleFavorite(id)
        XCTAssertFalse(reloaded.isFavorite(id))

        // 旧版 state.json（无 favorites 键）解码后收藏为空数组而非失败
        struct LegacyState: Codable {
            var progress: [String: WordProgress] = [:]
            var dailyNewGoal = 10
            var autoSpeak = true
            var streakDays = 0
            var lastStudyDay: String?
        }
        let data = try JSONEncoder().encode(LegacyState())
        XCTAssertNoThrow(try JSONDecoder().decode(Store.StateFile.self, from: data))
    }
}
