import SwiftUI

struct Word: Codable, Identifiable, Hashable {
    let id: String
    let word: String
    let phonetic: String?
    let pos: String?
    let defsEn: [String]
    let zh: [String]
    let forms: [String]?        // 词形变化，如 "复数 studies"；旧数据无此字段为 nil
    let examples: [String]
    let exampleZh: [String]?    // 与 examples 平行的中文翻译；旧数据无此字段为 nil

    func exampleTranslation(_ index: Int) -> String? {
        guard let zs = exampleZh, index < zs.count, !zs[index].isEmpty else { return nil }
        return zs[index]
    }
}

struct WordBook: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let words: [Word]
}

struct WordProgress: Codable, Hashable {
    var box: Int
    var due: TimeInterval
    var seen: Int
    var correct: Int
    var introducedDay: String?
}

struct SessionItem: Identifiable, Hashable {
    let word: Word
    let isNew: Bool
    var id: String { word.id + (isNew ? "+new" : "+review") }
}

/// 例句中目标词的识别与高亮：词形变化（复数/时态/-ing）也算命中，
/// 与 build_vocab.py 里例句匹配用的屈折表保持一致。
enum WordHighlight {
    static func inflectedForms(of word: String) -> Set<String> {
        var forms: Set<String> = [word]
        let stem = word.hasSuffix("y") ? String(word.dropLast()) : word
        forms.insert(word + "s")
        forms.insert(word + "es")
        forms.insert(word + "d")
        forms.insert(word + "ed")
        forms.insert(word + "ing")
        forms.insert(stem + "ies")
        forms.insert(stem + "ied")
        if let last = word.last, last.isLetter, !"aeiou".contains(last) {
            forms.insert(word + String(last) + "ing")
            forms.insert(word + String(last) + "ed")
        }
        return forms
    }

    /// token 去掉首尾标点后是否为目标词本身或其屈折形式（大小写不敏感）
    static func isMatch(_ token: String, for word: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'`()[]—-"))
            .lowercased()
        guard !trimmed.isEmpty else { return false }
        return inflectedForms(of: word.lowercased()).contains(trimmed)
    }

    /// 把例句渲染成目标词加粗（着主题色）的 Text；无匹配则原样返回
    static func text(_ sentence: String, highlighting word: String) -> Text {
        var out = Text("")
        for (i, token) in sentence.components(separatedBy: " ").enumerated() {
            let piece = i == 0 ? token : " " + token
            out = out + (isMatch(token, for: word)
                         ? Text(piece).bold().foregroundColor(Theme.accent)
                         : Text(piece))
        }
        return out
    }
}

/// 例句行：点按朗读整句（略慢于单词朗读，适合跟读），小喇叭提示可点；有译文时附灰字
struct ExampleRow: View {
    @EnvironmentObject var store: Store
    let sentence: String
    let word: String
    var translation: String?

    var body: some View {
        Button {
            store.speak(sentence, rate: 0.4)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    WordHighlight.text(sentence, highlighting: word)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "speaker.wave.1.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let translation {
                    Text(translation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// 学习热力图的网格数学：最近 weeksCount 个自然周（每周从周一开始），
/// 列为周、旧→新，行为周一…周日。纯计算，可单测。
struct StudyHeatmap {
    let weeks: [[Date]]
    let today: Date

    init(weeksCount: Int = 12, now: Date = Date(), calendar cal: Calendar = .current) {
        today = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: today)   // 1=周日 … 7=周六
        let mondayOffset = (weekday + 5) % 7                 // 周一 → 0
        let thisMonday = cal.date(byAdding: .day, value: -mondayOffset, to: today)!
        let firstMonday = cal.date(byAdding: .day, value: -(weeksCount - 1) * 7, to: thisMonday)!
        var out: [[Date]] = []
        var cursor = firstMonday
        while cursor <= thisMonday {
            out.append((0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: cursor) })
            cursor = cal.date(byAdding: .day, value: 7, to: cursor)!
        }
        weeks = out
    }

    var allDays: [Date] { weeks.flatMap { $0 } }

    func count(for date: Date, in dailyCounts: [String: Int]) -> Int {
        dailyCounts[Store.dayString(date)] ?? 0
    }

    /// 颜色强度分档：0 / 1-4 / 5-14 / 15-29 / 30+
    static func intensity(for count: Int) -> Double {
        switch count {
        case ..<1: return 0
        case 1...4: return 0.25
        case 5...14: return 0.5
        case 15...29: return 0.75
        default: return 1
        }
    }
}

/// 生词本星标按钮：学习卡与词条详情页共用
struct FavoriteButton: View {
    @EnvironmentObject var store: Store
    let wordID: String

    var body: some View {
        Button {
            store.toggleFavorite(wordID)
        } label: {
            Image(systemName: store.isFavorite(wordID) ? "star.fill" : "star")
                .font(.title3)
                .foregroundStyle(store.isFavorite(wordID) ? .yellow : Theme.accent)
        }
        .buttonStyle(.plain)
    }
}

enum Theme {
    static let accent = Color(red: 0.35, green: 0.37, blue: 0.92)
    static let accentSecondary = Color(red: 0.13, green: 0.62, blue: 0.78)
}
