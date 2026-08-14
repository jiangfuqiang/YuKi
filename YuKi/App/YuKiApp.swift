import SwiftUI
import SwiftData

@main
struct YuKiApp: App {
    let container: ModelContainer?
    let startupError: String?

    init() {
        do {
            let schema = Schema([
                Scene.self, Series.self, Buddy.self, ChatSession.self, Message.self
            ])
            let createdContainer = try ModelContainer(for: schema)
            SampleData.seedIfNeeded(in: createdContainer.mainContext)
            if ProcessInfo.processInfo.arguments.contains("--uitest-chinese-scene") {
                SampleData.seedChineseModelTest(in: createdContainer.mainContext)
            }
            container = createdContainer
            startupError = nil
        } catch {
            container = nil
            startupError = error.localizedDescription
        }
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            if let container {
                RootView()
                    .modelContainer(container)
                    .preferredColorScheme(.dark)
            } else {
                ContentUnavailableView {
                    Label("无法打开本地数据", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("请重新启动 App。若问题持续，请先保留设备数据并联系支持。\n\(startupError ?? "未知错误")")
                }
                .preferredColorScheme(.dark)
            }
        }
    }
}
