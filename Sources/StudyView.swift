import SwiftUI

struct StudyView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var items: [SessionItem]
    @State private var index = 0
    @State private var revealed = ProcessInfo.processInfo.arguments.contains("--revealed")
    @State private var newIDs = Set<String>()       // 完成页统计按词去重
    @State private var reviewIDs = Set<String>()
    @State private var requeuedIDs = Set<String>()  // 错词插回最多一次
    @State private var rightCount = 0               // sensoryFeedback 触发器
    @State private var wrongCount = 0

    // 答题会改变 Store，导致上层用新配额重建 session；这里只在进入时取一次，冻结牌组
    init(session: [SessionItem]) {
        _items = State(initialValue: session)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if items.isEmpty {
                finishedView(doneSomething: false)
            } else if index >= items.count {
                finishedView(doneSomething: true)
            } else {
                StudyCard(item: items[index], revealed: revealed) {
                    withAnimation(.snappy) { revealed = true }
                }
                .gesture(swipeGesture)
                answerBar
            }
        }
        .background(Color(.secondarySystemBackground))
        .sensoryFeedback(.success, trigger: rightCount)
        .sensoryFeedback(.error, trigger: wrongCount)
        .task {
            await runDemoIfRequested()
        }
    }

    // 右滑=认识，左滑=不认识；仅在翻面后生效，与按钮行为一致
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard revealed else { return }
                let t = value.translation
                guard abs(t.width) > 60, abs(t.width) > abs(t.height) * 1.5 else { return }
                answer(t.width > 0)
            }
    }

    // 自动化验证用：--demo-answer 自动答 3 题（对、对、错），走完 record→持久化全链路
    private func runDemoIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--demo-answer") else { return }
        try? await Task.sleep(nanoseconds: 800_000_000)
        for i in 0..<min(3, items.count) {
            withAnimation(.snappy) { revealed = true }
            try? await Task.sleep(nanoseconds: 400_000_000)
            answer(i == 2 ? false : true)
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            ProgressView(value: progressFraction)
                .tint(Theme.accent)
            Text("\(min(index + 1, max(items.count, 1)))/\(items.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var progressFraction: Double {
        items.isEmpty ? 0 : Double(min(index, items.count)) / Double(items.count)
    }

    private var answerBar: some View {
        HStack(spacing: 12) {
            Button {
                answer(false)
            } label: {
                Label("不认识", systemImage: "xmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)

            Button {
                answer(true)
            } label: {
                Label("认识", systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .disabled(!revealed)
        .opacity(revealed ? 1 : 0.4)
    }

    private func answer(_ knew: Bool) {
        let item = items[index]
        store.record(item, knew: knew)
        if item.isNew { newIDs.insert(item.word.id) } else { reviewIDs.insert(item.word.id) }
        if knew {
            rightCount += 1
        } else {
            wrongCount += 1
            // 答错的词隔 3 张插回牌组再过一遍（每词限一次），当场巩固
            if !requeuedIDs.contains(item.word.id) {
                requeuedIDs.insert(item.word.id)
                items.insert(item, at: min(index + 4, items.count))
            }
        }
        withAnimation(.snappy) {
            index += 1
            revealed = false
        }
    }

    private func finishedView(doneSomething: Bool) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Text(doneSomething ? "🎉" : "☕️")
                .font(.system(size: 64))
            Text(doneSomething ? "今日学习完成" : "暂时没有要学的词")
                .font(.title2.bold())
            if doneSomething {
                Text("新词 \(newIDs.count) 个 · 复习 \(reviewIDs.count) 个")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("休息一下，明天再来")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button {
                dismiss()
            } label: {
                Text("收工")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

private struct StudyCard: View {
    @EnvironmentObject var store: Store

    let item: SessionItem
    let revealed: Bool
    let onReveal: () -> Void

    var body: some View {
        ZStack {
            if revealed {
                back
            } else {
                front
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 28).fill(Color(.systemBackground)))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .onTapGesture(perform: onReveal)
        .onAppear {
            if store.autoSpeak { store.speak(item.word.word) }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private var front: some View {
        VStack(spacing: 14) {
            HStack {
                chip(item.isNew ? "新词" : "复习", color: item.isNew ? Theme.accent : .orange)
                Spacer()
                Button {
                    store.speak(item.word.word)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
            Spacer()
            Text(item.word.word)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let phonetic = cleanedPhonetic {
                Text("/\(phonetic)/")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("点击卡片查看释义")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(22)
    }

    private var back: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.word.word)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(2)
                    if let phonetic = cleanedPhonetic {
                        Text("/\(phonetic)/")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.speak(item.word.word)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
                if let pos = item.word.pos, !pos.isEmpty {
                    chip(pos, color: .gray)
                }
                if !item.word.defsEn.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("英语释义")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(item.word.defsEn.indices, id: \.self) { i in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(i + 1).")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(item.word.defsEn[i])
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                if !item.word.zh.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("中文释义")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(item.word.zh, id: \.self) { line in
                            Text(line)
                                .font(.body)
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cleanedPhonetic: String? {
        guard let phonetic = item.word.phonetic else { return nil }
        let trimmed = phonetic.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return trimmed.isEmpty ? nil : trimmed
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}
