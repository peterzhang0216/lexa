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

    @MainActor
    func testExamCollectionSharesEntriesWithoutDoubleCount() throws {
        let store = Store()
        // 展示层多一本聚合书，词条引用原词书 entry
        let display = store.displayBooks
        XCTAssertEqual(display.count, store.books.count + 1)
        let collection = try XCTUnwrap(display.first { $0.id == Store.examCollectionID })
        let sourceIDs = Set(["cet4", "cet6", "ky"])
        let sources = store.books.filter { sourceIDs.contains($0.id) }.flatMap(\.words)
        XCTAssertEqual(collection.words.count, sources.count)
        XCTAssertEqual(Set(collection.words.map(\.id)), Set(sources.map(\.id)))
        XCTAssertEqual(store.words(bookID: Store.examCollectionID).count, sources.count)
        // 全局口径只算真实词书，聚合不双计
        XCTAssertEqual(store.words(bookID: nil).count, store.totalWords)
    }

    func testStudyHeatmapGridMath() {
        let cal = Calendar.current
        let now = Date()
        let model = StudyHeatmap(weeksCount: 12, now: now, calendar: cal)
        XCTAssertEqual(model.weeks.count, 12)
        XCTAssertTrue(model.weeks.allSatisfy { $0.count == 7 })
        // 每周从周一开始
        XCTAssertTrue(model.weeks.allSatisfy { cal.component(.weekday, from: $0[0]) == 2 })
        // 84 天互不重复、含今天、首日不晚于 11 周前
        let all = model.allDays
        XCTAssertEqual(Set(all.map { cal.startOfDay(for: $0) }).count, 84)
        XCTAssertTrue(all.contains { cal.isDate($0, inSameDayAs: now) })
        XCTAssertLessThanOrEqual(model.weeks[0][0], now)
    }

    @MainActor
    func testRecordAccumulatesDailyCount() {
        let store = Store()
        let todayKey = Store.dayString(Date())
        let todayBefore = store.dailyCounts[todayKey] ?? 0
        let totalBefore = store.totalAnswered
        let word = Word(id: "test-rec-1", word: "record", phonetic: nil, pos: nil,
                        defsEn: [], zh: [], forms: nil, examples: [], exampleZh: nil)
        store.record(SessionItem(word: word, isNew: true), knew: true)
        XCTAssertEqual(store.dailyCounts[todayKey], todayBefore + 1)
        XCTAssertEqual(store.totalAnswered, totalBefore + 1)
    }
}
