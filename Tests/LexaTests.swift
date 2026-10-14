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
}
