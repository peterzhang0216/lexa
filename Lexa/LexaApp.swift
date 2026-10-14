import SwiftUI

@main
struct LexaApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            root
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private var root: some View {
        switch Self.forcedScreen {
        case "study":
            StudyView(session: store.buildSession(bookID: nil))
        case "browse":
            BrowseView()
        case "settings":
            SettingsView()
        default:
            ContentView()
        }
    }

    // 截图/自动化用：--screen study|browse|settings 直达对应界面
    static var forcedScreen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--screen"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
}
