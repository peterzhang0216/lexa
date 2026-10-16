import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store
    @State private var launch: StudyLaunch?
    @State private var nothingToDo = false

    struct StudyLaunch: Identifiable {
        let id = UUID()
        let bookID: String?
        var favoritesOnly = false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    greeting
                    startCard
                    if !store.favorites.isEmpty {
                        favoritesCard
                    }
                    ForEach(store.books) { book in
                        BookCard(book: book, learned: learnedCount(in: book)) {
                            tryLaunch(bookID: book.id)
                        }
                    }
                    statsRow
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.secondarySystemBackground))
            .navigationTitle("Lexa · 拾词")
            .navigationBarTitleDisplayMode(.large)
        }
        .fullScreenCover(item: $launch) { item in
            StudyView(session: item.favoritesOnly
                      ? store.buildFavoritesSession()
                      : store.buildSession(bookID: item.bookID))
                .environmentObject(store)
        }
        .task {
            // 自动化验证用：--auto-study 启动即进入学习页（配合 --demo-answer/--revealed）
            if ProcessInfo.processInfo.arguments.contains("--auto-study") {
                tryLaunch(bookID: nil)
            }
        }
        .alert("现在没有要学的词", isPresented: $nothingToDo) {
            Button("好", role: .cancel) {}
        } message: {
            Text("这里的内容都学过了，新词额度今天也已用完。复习词到点后会自动出现在这里。")
        }
    }

    // 配额到点与否随时在变，入口处即时判断，避免点进全屏才看到空态
    private func tryLaunch(bookID: String?) {
        if store.dueCount(bookID: bookID) == 0 && store.newCount(bookID: bookID) == 0 {
            nothingToDo = true
        } else {
            launch = StudyLaunch(bookID: bookID)
        }
    }

    private func learnedCount(in book: WordBook) -> Int {
        book.words.filter { (store.progress[$0.id]?.seen ?? 0) > 0 }.count
    }

    private var greeting: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.streakDays > 0 ? "坚持第 \(store.streakDays) 天 🔥" : "今天开始打卡吧")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("今天背点什么？")
                    .font(.title3.bold())
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private var startCard: some View {
        Button {
            tryLaunch(bookID: nil)
        } label: {
            VStack(spacing: 8) {
                Text("开始学习")
                    .font(.title2.bold())
                Text("待复习 \(store.dueCount(bookID: nil)) 词 · 新词 \(store.newCount(bookID: nil)) 词")
                    .font(.subheadline)
                    .opacity(0.92)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accentSecondary],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .foregroundStyle(.white)
            .shadow(color: Theme.accent.opacity(0.3), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statTile("已学", store.learnedCount, "book.closed")
            statTile("已掌握", store.masteredCount, "checkmark.seal")
            statTile("待复习", store.dueCount(bookID: nil), "clock.arrow.circlepath")
        }
    }

    private var favoritesCard: some View {
        Button {
            launch = StudyLaunch(bookID: nil, favoritesOnly: true)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "star.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color(.systemBackground)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("生词本")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(store.favorites.count) 词 · 待复习 \(store.favoriteDueCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)))
        }
        .buttonStyle(.plain)
    }

    private func statTile(_ title: String, _ value: Int, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
            Text("\(value)")
                .font(.title3.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.systemBackground)))
    }
}

private struct BookCard: View {
    let book: WordBook
    let learned: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RingView(progress: book.words.isEmpty ? 0 : Double(learned) / Double(book.words.count))
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("已学 \(learned) / \(book.words.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)))
        }
        .buttonStyle(.plain)
    }
}

private struct RingView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
