import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("学习", systemImage: "book.pages") }
                .tag(0)
            BrowseView()
                .tabItem { Label("词库", systemImage: "books.vertical") }
                .tag(1)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(2)
        }
        .tint(Theme.accent)
        .onAppear {
            // 自动化验证用：--tab-browse / --tab-settings 直达对应 tab
            if ProcessInfo.processInfo.arguments.contains("--tab-settings") {
                selectedTab = 2
            }
            if ProcessInfo.processInfo.arguments.contains("--tab-browse") {
                selectedTab = 1
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.syncReminder()   // 提醒文案里的待学词数按当下值刷新
            }
        }
    }
}
