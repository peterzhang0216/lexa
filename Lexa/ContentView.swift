import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("学习", systemImage: "book.pages") }
            BrowseView()
                .tabItem { Label("词库", systemImage: "books.vertical") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
    }
}
