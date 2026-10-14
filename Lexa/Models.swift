import SwiftUI

struct Word: Codable, Identifiable, Hashable {
    let id: String
    let word: String
    let phonetic: String?
    let pos: String?
    let defsEn: [String]
    let zh: [String]
    let examples: [String]
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

enum Theme {
    static let accent = Color(red: 0.35, green: 0.37, blue: 0.92)
    static let accentSecondary = Color(red: 0.13, green: 0.62, blue: 0.78)
}
