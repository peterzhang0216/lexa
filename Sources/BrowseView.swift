import SwiftUI

struct BrowseView: View {
    @EnvironmentObject var store: Store
    @State private var selectedBookID = ""
    @State private var query = ""
    @State private var detail: Word?
    @State private var favoritesOnly = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !favoritesOnly {
                    bookPicker
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                wordList
            }
            .navigationTitle("词库")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索英文单词")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        favoritesOnly.toggle()
                    } label: {
                        Image(systemName: favoritesOnly ? "star.fill" : "star")
                            .foregroundStyle(favoritesOnly ? .yellow : Theme.accent)
                    }
                    .disabled(store.favorites.isEmpty && !favoritesOnly)
                }
            }
            .onAppear {
                if selectedBookID.isEmpty {
                    selectedBookID = store.books.first?.id ?? ""
                }
            }
            .sheet(item: $detail) { word in
                WordDetailView(word: word)
                    .environmentObject(store)
            }
        }
    }

    // 6 本书塞不进 segmented，>4 本时降级为下拉菜单
    @ViewBuilder
    private var bookPicker: some View {
        let picker = Picker("词书", selection: $selectedBookID) {
            ForEach(store.displayBooks) { book in
                Text(book.title).tag(book.id)
            }
        }
        if store.displayBooks.count > 4 {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    // 只渲染前 200 条，避免空搜索时超长列表掉帧
    private var filteredWords: [Word] {
        let words = favoritesOnly
            ? store.favoriteWords
            : store.words(bookID: selectedBookID)
        if query.isEmpty {
            return Array(words.prefix(200))
        }
        return words.filter { $0.word.localizedCaseInsensitiveContains(query) }
    }

    private var wordList: some View {
        List {
            ForEach(filteredWords) { word in
                Button {
                    detail = word
                } label: {
                    WordRow(word: word, progress: store.progress[word.id])
                }
                .buttonStyle(.plain)
            }
            if query.isEmpty, filteredWords.count >= 200 {
                Section {
                    Text("已显示前 200 词（本书共 \(store.words(bookID: selectedBookID).count) 词）\n用搜索框查找全部单词")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .listStyle(.plain)
    }
}

struct WordRow: View {
    let word: Word
    let progress: WordProgress?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(word.word)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if let first = word.zh.first {
                    Text(first)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            statusChip
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusChip: some View {
        switch progress {
        case nil:
            chip("新", color: .gray)
        case .some(let prog) where prog.box >= 4:
            chip("已掌握", color: .green)
        case .some:
            chip("学习中", color: Theme.accent)
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
            .foregroundStyle(color)
    }
}

struct WordDetailView: View {
    @EnvironmentObject var store: Store
    let word: Word

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let bookTitle = bookTitle {
                    Text(bookTitle)
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.accent.opacity(0.12)))
                        .foregroundStyle(Theme.accent)
                }
                if !word.defsEn.isEmpty {
                    section("英语释义") {
                        ForEach(word.defsEn.indices, id: \.self) { i in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(i + 1).")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(word.defsEn[i])
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                if !word.zh.isEmpty {
                    section("中文释义") {
                        ForEach(word.zh, id: \.self) { line in
                            Text(line)
                                .font(.body)
                        }
                    }
                }
                if let forms = word.forms, !forms.isEmpty {
                    section("词形变化") {
                        Text(forms.joined(separator: " · "))
                            .font(.subheadline)
                    }
                }
                if !word.examples.isEmpty {
                    section("例句") {
                        ForEach(word.examples.indices, id: \.self) { i in
                            ExampleRow(sentence: word.examples[i],
                                       word: word.word,
                                       translation: word.exampleTranslation(i))
                        }
                    }
                }
                progressSection
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(word.word)
                .font(.largeTitle.bold())
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            if let phonetic = word.phonetic {
                let trimmed = phonetic.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                if !trimmed.isEmpty {
                    Text("/\(trimmed)/")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                store.speak(word.word)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            FavoriteButton(wordID: word.id)
        }
    }

    private var bookTitle: String? {
        store.books.first { $0.words.contains(where: { $0.id == word.id }) }?.title
    }

    @ViewBuilder
    private var progressSection: some View {
        if let prog = store.progress[word.id] {
            section("学习记录") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("已学 \(prog.seen) 次 · 认对 \(prog.correct) 次 · 当前第 \(prog.box + 1) 阶")
                        .font(.subheadline)
                    if prog.due > Date().timeIntervalSince1970 {
                        Text("下次复习：\(Date(timeIntervalSince1970: prog.due).formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content()
        }
    }
}
