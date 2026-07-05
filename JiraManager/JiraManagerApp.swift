import SwiftUI

@main
struct JiraManagerApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            SidebarCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .frame(width: 460)
        }
    }
}
