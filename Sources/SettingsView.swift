import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var confirmReset = false
    @State private var permissionDenied = false

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
                Section("提醒") {
                    Toggle("每日学习提醒", isOn: reminderToggle)
                    if store.reminderEnabled {
                        DatePicker("提醒时间", selection: reminderDate,
                                   displayedComponents: .hourAndMinute)
                    }
                    if let reminderError = store.reminderError {
                        Label(reminderError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
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
                    LabeledContent("今日答题", value: "\(store.dailyCounts[Store.dayString(Date())] ?? 0)")
                    LabeledContent("累计答题", value: "\(store.totalAnswered)")
                    heatmapRow
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
            .alert("需要通知权限", isPresented: $permissionDenied) {
                Button("去系统设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请在系统设置中允许拾词发送通知，才能收到每日提醒。")
            }
        }
    }

    // 打开开关前先请求通知权限，被拒时不改状态并引导去系统设置
    private var reminderToggle: Binding<Bool> {
        Binding(
            get: { store.reminderEnabled },
            set: { newValue in
                if newValue {
                    Task { @MainActor in
                        if await ReminderScheduler.requestAuthorization() {
                            store.reminderEnabled = true
                        } else {
                            permissionDenied = true
                        }
                    }
                } else {
                    store.reminderEnabled = false
                }
            })
    }

    private var reminderDate: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: store.reminderHour,
                                      minute: store.reminderMinute,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.reminderHour = comps.hour ?? 20
                store.reminderMinute = comps.minute ?? 0
            })
    }

    // 最近 12 周的学习日历（列=周，行=周一…周日），未来的格子透明
    @ViewBuilder
    private var heatmapRow: some View {
        if store.totalAnswered == 0 {
            Text("答题后这里会出现你的学习日历")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            let model = StudyHeatmap()
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(model.weeks.indices, id: \.self) { week in
                        VStack(spacing: 3) {
                            ForEach(model.weeks[week].indices, id: \.self) { day in
                                let date = model.weeks[week][day]
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(cellColor(model: model, date: date))
                                    .frame(width: 13, height: 13)
                            }
                        }
                    }
                }
                HStack(spacing: 4) {
                    Text("少").font(.caption2).foregroundStyle(.secondary)
                    ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.accent.opacity(level))
                            .frame(width: 10, height: 10)
                    }
                    Text("多").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func cellColor(model: StudyHeatmap, date: Date) -> Color {
        if date > model.today {
            return .clear
        }
        let level = StudyHeatmap.intensity(for: model.count(for: date, in: store.dailyCounts))
        return level == 0 ? Color(.systemFill) : Theme.accent.opacity(level)
    }
}
