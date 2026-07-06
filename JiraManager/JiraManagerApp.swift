import SwiftUI

@main
struct JiraManagerApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var updater = UpdateService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(updater)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            SidebarCommands()
            CommandGroup(after: .appInfo) {
                Button("Güncellemeleri Denetle…") {
                    Task { await updater.check(silent: false) }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .frame(width: 460)
        }
    }
}
