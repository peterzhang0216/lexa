import SwiftUI
import AVFoundation

@MainActor
final class Store: ObservableObject {
    @Published private(set) var books: [WordBook] = []
    @Published private(set) var progress: [String: WordProgress] = [:]
    @Published var dailyNewGoal = 10 { didSet { saveState() } }
    @Published var autoSpeak = true { didSet { saveState() } }
    @Published private(set) var streakDays = 0
    @Published private(set) var lastStudyDay: String?

    // Leitner 盒子间隔：第 0 盒 10 分钟后重现，之后按天翻倍
    static let boxIntervals: [TimeInterval] = [10 * 60, 86_400, 2 * 86_400, 4 * 86_400, 8 * 86_400, 16 * 86_400, 32 * 86_400]
    static let maxBox = 6
    static let masteredBox = 4

    private let speech = AVSpeechSynthesizer()
    private let stateURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lexa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }()

    init() {
        loadBooks()
        loadState()
    }

    var totalWords: Int { books.reduce(0) { $0 + $1.words.count } }
    var learnedCount: Int { progress.values.filter { $0.seen > 0 }.count }
    var masteredCount: Int { progress.values.filter { $0.box >= Self.masteredBox }.count }

    func words(bookID: String?) -> [Word] {
        guard let id = bookID, let book = books.first(where: { $0.id == id }) else {
            return books.flatMap(\.words)
        }
        return book.words
    }

    func dueWords(bookID: String?, now: Date = Date()) -> [Word] {
        let nowStamp = now.timeIntervalSince1970
        return words(bookID: bookID).filter { progress[$0.id].map { $0.due <= nowStamp } ?? false }
    }

    func dueCount(bookID: String?) -> Int { dueWords(bookID: bookID).count }

    // 今日还能学的新词数 = 每日目标 - 今天已引入的词数，再和未学词数取小
    func newCount(bookID: String?) -> Int {
        let today = Self.dayString(Date())
        let introducedToday = progress.values.filter { $0.introducedDay == today }.count
        let quota = max(0, dailyNewGoal - introducedToday)
        let unseen = words(bookID: bookID).filter { progress[$0.id] == nil }.count
        return min(unseen, quota)
    }

    func buildSession(bookID: String?) -> [SessionItem] {
        let reviews = dueWords(bookID: bookID).map { SessionItem(word: $0, isNew: false) }
        let fresh = words(bookID: bookID)
            .filter { progress[$0.id] == nil }
            .prefix(newCount(bookID: bookID))
            .map { SessionItem(word: $0, isNew: true) }
        return reviews + fresh
    }

    func record(_ item: SessionItem, knew: Bool) {
        let now = Date()
        var prog = progress[item.word.id] ?? WordProgress(box: 0, due: 0, seen: 0, correct: 0, introducedDay: nil)
        prog.seen += 1
        if knew {
            prog.correct += 1
            prog.box = min(prog.box + 1, Self.maxBox)
        } else {
            prog.box = 0
        }
        prog.due = now.timeIntervalSince1970 + Self.boxIntervals[prog.box]
        if prog.introducedDay == nil { prog.introducedDay = Self.dayString(now) }
        progress[item.word.id] = prog
        touchStreak(now: now)
        saveState()
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.45
        speech.speak(utterance)
    }

    func resetAllProgress() {
        progress = [:]
        streakDays = 0
        lastStudyDay = nil
        saveState()
    }

    private func touchStreak(now: Date) {
        let today = Self.dayString(now)
        guard lastStudyDay != today else { return }
        let yesterday = Self.dayString(Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now)
        streakDays = lastStudyDay == yesterday ? streakDays + 1 : 1
        lastStudyDay = today
    }

    // MARK: - Persistence

    private struct StateFile: Codable {
        var progress: [String: WordProgress]
        var dailyNewGoal: Int
        var autoSpeak: Bool
        var streakDays: Int
        var lastStudyDay: String?
    }

    private func saveState() {
        let state = StateFile(progress: progress, dailyNewGoal: dailyNewGoal, autoSpeak: autoSpeak,
                              streakDays: streakDays, lastStudyDay: lastStudyDay)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(StateFile.self, from: data) else { return }
        progress = state.progress
        dailyNewGoal = state.dailyNewGoal
        autoSpeak = state.autoSpeak
        streakDays = state.streakDays
        lastStudyDay = state.lastStudyDay
    }

    private func loadBooks() {
        for name in ["voa_core", "awl_academic", "exam_plus"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let book = try? JSONDecoder().decode(WordBook.self, from: data) else { continue }
            books.append(book)
        }
    }

    static func dayString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
