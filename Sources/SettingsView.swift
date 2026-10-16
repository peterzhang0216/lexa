import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                if let storageError = store.storageError {
                    Section {
                        Label(storageError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
                Section("学习偏好") {
                    Stepper("每日新词：\(store.dailyNewGoal) 个",
                            value: $store.dailyNewGoal, in: 5...100, step: 5)
                    Toggle("自动发音", isOn: $store.autoSpeak)
                }
                Section {
                    LabeledContent("VOA 核心词汇", value: "VOA 官方词表 · 公有领域")
                    LabeledContent("四六级 · 考研词汇", value: "ECDICT 词表标签 · MIT")
                    LabeledContent("AWL 学术词汇", value: "A. Coxhead · 教学免费")
                    LabeledContent("词典释义 · 词形", value: "ECDICT · MIT")
                    LabeledContent("例句", value: "Tatoeba · CC BY 2.0 FR")
                } header: {
                    Text("词库来源")
                } footer: {
                    Text("VOA Learning English Word Book 为美国政府作品（公有领域）；Academic Word List 可自由用于教学与科研（© Averil Coxhead）；词典数据来自开源项目 ECDICT（MIT 协议）；例句来自 Tatoeba.org 开放句库（CC BY 2.0 FR，tatoeba.org）。")
                }
                Section("统计") {
                    LabeledContent("已学单词", value: "\(store.learnedCount) / \(store.totalWords)")
                    LabeledContent("连续打卡", value: "\(store.streakDays) 天")
                }
                Section {
                    Button("重置全部学习进度", role: .destructive) {
                        confirmReset = true
                    }
                }
            }
            .navigationTitle("设置")
            .confirmationDialog("重置后无法恢复，确定继续吗？", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("重置全部进度", role: .destructive) {
                    store.resetAllProgress()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}
