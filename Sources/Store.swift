import SwiftUI
import AVFoundation

@MainActor
final class Store: ObservableObject {
    @Published private(set) var books: [WordBook] = []
    @Published private(set) var progress: [String: WordProgress] = [:]
    @Published private(set) var favorites: [String] = []   // 生词本，按收藏顺序
    @Published var dailyNewGoal = 10 { didSet { saveState() } }
    @Published var autoSpeak = true { didSet { saveState() } }
    @Published private(set) var streakDays = 0
    @Published private(set) var lastStudyDay: String?
    @Published private(set) var storageError: String?

    // Leitner 盒子间隔：第 0 盒 10 分钟后重现，之后按天翻倍
    static let boxIntervals: [TimeInterval] = [10 * 60, 86_400, 2 * 86_400, 4 * 86_400, 8 * 86_400, 16 * 86_400, 32 * 86_400]
    static let maxBox = 6
    static let masteredBox = 4

    private let speech = AVSpeechSynthesizer()
    private let stateURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lexa", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("Lexa: 创建数据目录失败：\(error.localizedDescription)")
        }
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

    // MARK: - 生词本

    var favoriteWords: [Word] {
        let byID = Dictionary(uniqueKeysWithValues: books.flatMap(\.words).map { ($0.id, $0) })
        return favorites.compactMap { byID[$0] }
    }

    var favoriteDueCount: Int {
        let nowStamp = Date().timeIntervalSince1970
        return favorites.filter { id in
            guard let p = progress[id] else { return false }
            return p.due <= nowStamp
        }.count
    }

    /// 生词练习：到期的优先，其余按收藏顺序补足 20 个，全部按复习计（不占新词额度）
    func buildFavoritesSession() -> [SessionItem] {
        let words = favoriteWords
        let nowStamp = Date().timeIntervalSince1970
        let dueIDs = Set(words.filter { progress[$0.id]?.due ?? .infinity <= nowStamp }.map(\.id))
        let due = words.filter { dueIDs.contains($0.id) }
        let rest = words.filter { !dueIDs.contains($0.id) }
        return (due + Array(rest.prefix(20))).map { SessionItem(word: $0, isNew: false) }
    }

    func isFavorite(_ wordID: String) -> Bool {
        favorites.contains(wordID)
    }

    func toggleFavorite(_ wordID: String) {
        if let i = favorites.firstIndex(of: wordID) {
            favorites.remove(at: i)
        } else {
            favorites.append(wordID)
        }
        saveState()
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

    func speak(_ text: String, rate: Float = 0.45) {
        speech.stopSpeaking(at: .immediate)   // 重复点击重新起读，不排队堆积
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = rate
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

    struct StateFile: Codable {   // internal：单测验证旧版 state.json 迁移
        var progress: [String: WordProgress]
        var dailyNewGoal: Int
        var autoSpeak: Bool
        var streakDays: Int
        var lastStudyDay: String?
        var favorites: [String]?   // 可选：旧版 state.json 无此键
    }

    private func saveState() {
        let state = StateFile(progress: progress, dailyNewGoal: dailyNewGoal, autoSpeak: autoSpeak,
                              streakDays: streakDays, lastStudyDay: lastStudyDay,
                              favorites: favorites)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: stateURL, options: .atomic)
            storageError = nil
        } catch {
            storageError = "学习进度保存失败：\(error.localizedDescription)"
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
        favorites = state.favorites ?? []
    }

    private func loadBooks() {
        // 顺序即展示顺序：基础 → 四六级/考研 → 学术 → 进阶
        for name in ["voa_core", "cet4_core", "cet6_core", "ky_core",
                     "awl_academic", "exam_plus"] {
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
